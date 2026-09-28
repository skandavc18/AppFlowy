import 'dart:async';
import 'dart:convert';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/appflowy_cloud_auth.dart';
import 'package:appflowy/shared/cover_image_decode.dart';
import 'package:appflowy/shared/custom_image_cache_manager.dart';
import 'package:appflowy/util/string_extension.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:crypto/crypto.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/uuid.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:string_validator/string_validator.dart';

/// Allows isolated caches in previews/tests without replacing the singleton.
class FlowyImageCacheScope extends InheritedWidget {
  const FlowyImageCacheScope(
      {super.key, required this.manager, required super.child});
  final BaseCacheManager manager;

  static BaseCacheManager? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<FlowyImageCacheScope>()
      ?.manager;

  @override
  bool updateShouldNotify(FlowyImageCacheScope oldWidget) =>
      manager != oldWidget.manager;
}

/// This widget handles the downloading and caching of either internal or network images.
/// Supplied cloud profiles carry the access token in headers, never in the URL.
class FlowyNetworkImage extends StatefulWidget {
  const FlowyNetworkImage({
    super.key,
    this.userProfilePB,
    this.width,
    this.height,
    this.memCacheWidth,
    this.memCacheHeight,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.progressIndicatorBuilder,
    this.errorWidgetBuilder,
    required this.url,
    this.maxRetries = 5,
    this.retryDuration = const Duration(seconds: 6),
    this.retryErrorCodes = const {404},
    this.onImageLoaded,
    this.placeholderBuilder,
    this.coverDecodeSize,
    this.fadeInDuration = const Duration(milliseconds: 500),
    this.fadeOutDuration = const Duration(milliseconds: 1000),
  });

  /// The URL of the image.
  final String url;

  /// The width of the image.
  final double? width;

  /// The height of the image.
  final double? height;

  /// Optional in-memory decode dimensions in physical pixels.
  final int? memCacheWidth;
  final int? memCacheHeight;

  /// The fit of the image.
  final BoxFit fit;
  final Alignment alignment;

  /// The user profile.
  ///
  /// A supplied profile authenticates the request, including self-hosted cloud
  /// URLs. Callers remain responsible for selecting the appropriate profile.
  final UserProfilePB? userProfilePB;

  /// The progress indicator builder.
  final ProgressIndicatorBuilder? progressIndicatorBuilder;

  /// The error widget builder.
  final LoadingErrorWidgetBuilder? errorWidgetBuilder;

  /// Retry loading the image if it fails.
  final int maxRetries;

  /// Retry duration
  final Duration retryDuration;

  /// Retry error codes.
  final Set<int> retryErrorCodes;

  final void Function(bool isImageInCache)? onImageLoaded;

  final PlaceholderWidgetBuilder? placeholderBuilder;
  final Duration fadeInDuration;
  final Duration fadeOutDuration;

  /// Opt-in cover-only aspect-aware decoding. Other image/fullscreen callers
  /// retain CachedNetworkImage's public memCacheWidth/memCacheHeight behavior.
  final CoverImageDecodeSize? coverDecodeSize;

  @override
  FlowyNetworkImageState createState() => FlowyNetworkImageState();
}

class FlowyNetworkImageState extends State<FlowyNetworkImage> {
  late BaseCacheManager _manager;
  // Preserve the existing public singleton API; scoped caches are internal.
  CustomImageCacheManager get manager => CustomImageCacheManager();
  final retryCounter = FlowyNetworkRetryCounter();
  String? retryTag;
  String? _sourceUrl;
  String? _token;
  String? _userId;
  String? _cacheKey;
  Map<String, String> _headers = const {};
  int _epoch = 0;
  int _probe = 0;
  int _retryVersion = 0;
  bool _bound = false;
  bool _retryPending = false;
  Timer? _retryTimer;
  VoidCallback? _unsubscribe;

  @override
  void initState() {
    super.initState();

    assert(isURL(widget.url));

    if (widget.url.isAppFlowyCloudUrl) {
      assert(
        widget.userProfilePB != null && widget.userProfilePB!.token.isNotEmpty,
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next =
        FlowyImageCacheScope.maybeOf(context) ?? CustomImageCacheManager();
    _syncSource(next);
  }

  @override
  void didUpdateWidget(covariant FlowyNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = _syncSource(_manager);
    if (!changed &&
        oldWidget.onImageLoaded == null &&
        widget.onImageLoaded != null) {
      unawaited(_reportCacheStatus());
    } else if (widget.onImageLoaded == null) {
      _probe++;
    }
    if (oldWidget.maxRetries != widget.maxRetries ||
        oldWidget.retryDuration != widget.retryDuration ||
        !setEquals(oldWidget.retryErrorCodes, widget.retryErrorCodes)) {
      _cancelRetry();
    }
  }

  bool _syncSource(BaseCacheManager next) {
    // Snapshot scalars: callers can mutate a protobuf in place.
    final token = widget.userProfilePB?.token;
    final userId = widget.userProfilePB?.id.toString();
    if (_bound &&
        _sourceUrl == widget.url &&
        _token == token &&
        _userId == userId &&
        identical(_manager, next)) return false;
    _releaseSource();
    _manager = next;
    _sourceUrl = widget.url;
    _token = token;
    _userId = userId;
    _headers = const {};
    if (token != null && token.isNotEmpty) {
      try {
        // Validate before calling the shared helper: its FormatException log
        // includes the source string, which must never expose a malformed token.
        jsonDecode(token);
        _headers = appFlowyCloudAuthHeaders(widget.userProfilePB);
      } on FormatException {
        Log.warn('Image authentication token is malformed.');
      }
    }
    // CachedNetworkImageProvider equality ignores headers. Authenticated
    // requests need a non-secret cache identity to reject old-token results.
    final isolatedCache = next is! CustomImageCacheManager;
    final authenticated = token?.isNotEmpty ?? false;
    _cacheKey = authenticated || isolatedCache
        ? 'flowy-image-${sha256.convert(utf8.encode(jsonEncode([
                widget.url,
                if (authenticated) ...[userId, token],
                if (isolatedCache) identityHashCode(next),
              ])))}'
        : null;
    retryTag = retryCounter.add(widget.url);
    _unsubscribe = retryCounter.listenToUrl(widget.url, () {
      _cancelRetry();
      if (mounted) setState(() {});
    });
    _bound = true;
    unawaited(_reportCacheStatus());
    return true;
  }

  Future<void> _reportCacheStatus() async {
    if (widget.onImageLoaded == null) return;
    final epoch = _epoch;
    final probe = ++_probe;
    final url = widget.url;
    var cached = false;
    try {
      final file = await _manager.getFileFromCache(_cacheKey ?? url);
      cached =
          file != null && file.file.path.isNotEmpty && file.originalUrl == url;
    } catch (_) {
      // Metadata is advisory; a cache lookup failure must not break loading.
    }
    if (mounted && epoch == _epoch && probe == _probe) {
      widget.onImageLoaded?.call(cached);
    }
  }

  void _cancelRetry() {
    _retryVersion++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryPending = false;
  }

  void _releaseSource() {
    _epoch++;
    _probe++;
    _cancelRetry();
    _unsubscribe?.call();
    _unsubscribe = null;
    if (retryTag != null) {
      retryCounter.clear(
        tag: retryTag!,
        url: _sourceUrl!,
        maxRetries: widget.maxRetries,
      );
    }
    retryTag = null;
  }

  @override
  void dispose() {
    _releaseSource();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final retryCount = retryCounter.getRetryCount(widget.url);
    final epoch = _epoch;
    final decodeSize = widget.coverDecodeSize;
    final key = ValueKey((epoch, retryCount));
    if (decodeSize != null) {
      // CachedNetworkImage's two memCache dimensions force an exact aspect
      // ratio. A cover needs the encoded aspect before choosing its decode
      // size; use the SAME disk-cache provider with a resize-only adapter.
      return Image(
        key: key,
        image: CoverImageProvider(
          CachedNetworkImageProvider(widget.url,
              cacheKey: _cacheKey, cacheManager: _manager, headers: _headers),
          decodeSize,
          widget.fit,
        ),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        alignment: widget.alignment,
        frameBuilder: (context, child, frame, synchronous) {
          if (frame != null || synchronous) {
            if (epoch == _epoch) _cancelRetry();
            return child;
          }
          return widget.placeholderBuilder?.call(context, widget.url) ??
              const SizedBox.shrink();
        },
        errorBuilder: (context, error, stack) {
          _handleImageError(error, epoch, retryCount);
          return _errorWidgetBuilder(context, widget.url, error);
        },
      );
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return CachedNetworkImage(
      key: key,
      cacheManager: _manager,
      cacheKey: _cacheKey,
      httpHeaders: _headers,
      imageUrl: widget.url,
      fit: widget.fit,
      alignment: widget.alignment,
      width: widget.width,
      height: widget.height,
      memCacheWidth: widget.memCacheWidth,
      memCacheHeight: widget.memCacheHeight,
      placeholder: widget.placeholderBuilder,
      fadeInDuration: reduceMotion ? Duration.zero : widget.fadeInDuration,
      fadeOutDuration: reduceMotion ? Duration.zero : widget.fadeOutDuration,
      progressIndicatorBuilder: widget.progressIndicatorBuilder,
      errorWidget: _errorWidgetBuilder,
      errorListener: (error) => _handleImageError(error, epoch, retryCount),
    );
  }

  /// if the error is 404 and the retry count is less than the max retries, it return a loading indicator.
  Widget _errorWidgetBuilder(BuildContext context, String url, Object error) {
    final retryCount = retryCounter.getRetryCount(url);
    if (error is HttpExceptionWithStatus) {
      if (widget.retryErrorCodes.contains(error.statusCode) &&
          retryCount < widget.maxRetries) {
        final fakeDownloadProgress = DownloadProgress(url, null, 0);
        return widget.progressIndicatorBuilder?.call(
              context,
              url,
              fakeDownloadProgress,
            ) ??
            widget.placeholderBuilder?.call(context, url) ??
            const Center(
              child: _SensitiveContent(),
            );
      }

      if (error.statusCode == 422) {
        // Unprocessable Entity: Used when the server understands the request but cannot process it due to
        //semantic issues (e.g., sensitive keywords).
        return const _SensitiveContent();
      }
    }

    return widget.errorWidgetBuilder?.call(context, url, error) ??
        const SizedBox.shrink();
  }

  void _handleImageError(Object error, int epoch, int attempt) {
    if (!mounted ||
        epoch != _epoch ||
        _retryPending ||
        retryCounter.getRetryCount(widget.url) != attempt ||
        attempt >= widget.maxRetries ||
        error is! HttpExceptionWithStatus ||
        !widget.retryErrorCodes.contains(error.statusCode)) return;
    // Never log a URL, authorization header, or server-provided error body.
    Log.debug(
        'Image retry scheduled: HTTP ${error.statusCode}, attempt $attempt');
    _retryPending = true;
    final version = ++_retryVersion;
    final url = widget.url;
    final cacheKey = _cacheKey ?? url;
    final cache = _manager;
    _retryTimer = Timer(widget.retryDuration, () async {
      bool current() =>
          mounted &&
          epoch == _epoch &&
          version == _retryVersion &&
          _retryPending &&
          retryCounter.getRetryCount(url) == attempt;
      if (!current()) return;
      try {
        await retryCounter._evictForRetry(cache, cacheKey, attempt);
      } catch (_) {
        // Still allow the bounded retry if advisory disk eviction fails.
      }
      if (!current()) return;
      _retryPending = false;
      _retryTimer = null;
      retryCounter.increment(url);
    });
  }
}

/// This class is used to count the number of retries for a given URL.
@visibleForTesting
class FlowyNetworkRetryCounter with ChangeNotifier {
  FlowyNetworkRetryCounter._();

  factory FlowyNetworkRetryCounter() => _instance;
  static final _instance = FlowyNetworkRetryCounter._();

  final Map<String, int> _values = <String, int>{};
  final Map<String, Set<String>> _owners = {};
  final Map<String, Map<Object, VoidCallback>> _urlListeners = {};
  final Map<(BaseCacheManager, String, int), Future<void>> _evictions = {};
  Map<String, int> get values => {..._values};

  Future<void> _evictForRetry(BaseCacheManager cache, String key, int attempt) {
    final request = (cache, key, attempt);
    return _evictions.putIfAbsent(request, () {
      return Future<void>.sync(() => cache.removeFile(key)).whenComplete(() {
        _evictions.removeWhere((entry, _) => entry == request);
      });
    });
  }

  /// O(listeners for this URL), not O(all mounted images). Unsubscribing the
  /// last consumer frees the URL entry. Legacy ChangeNotifier API is retained.
  VoidCallback listenToUrl(String url, VoidCallback listener) {
    final tag = Object();
    (_urlListeners[url] ??= {})[tag] = listener;
    return () {
      final listeners = _urlListeners[url];
      listeners?.remove(tag);
      if (listeners?.isEmpty ?? false) _urlListeners.remove(url);
    };
  }

  @visibleForTesting
  int get scopedUrlCount => _urlListeners.length;

  /// Get the retry count for a given URL.
  int getRetryCount(String url) => _values[url] ?? 0;

  /// Add a new URL to the retry counter. Don't call notifyListeners() here.
  ///
  /// This function will return a tag, use it to clear the retry count.
  /// Because the url may be the same, we need to add a unique tag to the url.
  String add(String url) {
    _values.putIfAbsent(url, () => 0);
    final tag = uuid();
    (_owners[url] ??= {}).add(tag);
    return tag;
  }

  /// Increment the retry count for a given URL.
  void increment(String url) {
    final count = _values[url];
    if (count == null) {
      _values[url] = 1;
    } else {
      _values[url] = count + 1;
    }
    final listeners = _urlListeners[url];
    if (listeners != null) {
      for (final entry in listeners.entries.toList()) {
        if (identical(listeners[entry.key], entry.value)) entry.value();
      }
    }
    notifyListeners();
  }

  /// Clear the retry count for a given tag.
  void clear({
    required String tag,
    required String url,
    int? maxRetries,
  }) {
    final owners = _owners[url];
    if (owners?.remove(tag) != true) return;
    if (owners!.isEmpty) {
      _owners.remove(url);
      _values.remove(url);
    }
  }

  /// Reset the retry counter.
  void reset() {
    _values.clear();
  }
}

class _SensitiveContent extends StatelessWidget {
  const _SensitiveContent();

  @override
  Widget build(BuildContext context) {
    return FlowyText(LocaleKeys.ai_contentPolicyViolation.tr());
  }
}
