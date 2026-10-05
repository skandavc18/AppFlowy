import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/shared/maps/map_style.dart';
import 'package:appflowy/shared/maps/map_suggestions.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A field that offers places while they are being typed, in a list that
/// drops out underneath it.
///
/// Typing three letters is enough: places are looked up as you go, a typed
/// coordinate pair is offered first, and one is chosen with a click or with
/// the arrow keys and Enter. Enter on its own hands the words to
/// [onSubmitted], for a host that can still make sense of them (a pasted
/// link, say).
///
/// The list is drawn in the window's own overlay, so a field inside a small
/// embed — a canvas card, a dashboard widget — is not cropped by its host.
class MapPlaceField extends StatefulWidget {
  const MapPlaceField({
    super.key,
    required this.palette,
    required this.controller,
    required this.onPicked,
    this.onSubmitted,
    this.hintText = '',
    this.autofocus = false,
    this.height = 34,
  });

  final MapPalette palette;
  final TextEditingController controller;
  final ValueChanged<MapSuggestion> onPicked;
  final ValueChanged<String>? onSubmitted;
  final String hintText;
  final bool autofocus;
  final double height;

  @override
  State<MapPlaceField> createState() => _MapPlaceFieldState();
}

class _MapPlaceFieldState extends State<MapPlaceField> {
  static const double _gap = 6;
  static const double _margin = 12;
  static const double _minListHeight = 120;
  static const double _maxListHeight = 264;

  final FocusNode _focus = FocusNode(debugLabel: 'map_place_field');
  final LayerLink _link = LayerLink();
  final GlobalKey _anchor = GlobalKey();
  final OverlayPortalController _portal = OverlayPortalController();

  /// What the list holds right now, as last built — read by the keyboard.
  MapSuggestionStatus _status = const MapSuggestionStatus(
    suggestions: [],
    open: false,
    busy: false,
  );
  int? _highlighted;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _pick(MapSuggestion suggestion) {
    widget.controller.value = TextEditingValue(
      text: suggestion.title,
      selection: TextSelection.collapsed(offset: suggestion.title.length),
    );
    _highlighted = null;
    _focus.unfocus();
    widget.onPicked(suggestion);
  }

  /// Whether there is anything worth dropping a list down for: places, or a
  /// word on how the looking is going once enough has been typed.
  bool get _hasList =>
      _focus.hasFocus &&
      (_status.suggestions.isNotEmpty ||
          widget.controller.text.trim().length >= 3);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final suggestions = _status.suggestions;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown when suggestions.isNotEmpty:
        setState(() {
          final current = _highlighted;
          _highlighted = current == null || current >= suggestions.length - 1
              ? 0
              : current + 1;
        });
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp when suggestions.isNotEmpty:
        setState(() {
          final current = _highlighted;
          _highlighted = current == null || current <= 0
              ? suggestions.length - 1
              : current - 1;
        });
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
        final pressed = event is KeyDownEvent;
        final index = _highlighted;
        if (index != null && index >= 0 && index < suggestions.length) {
          if (pressed) {
            _pick(suggestions[index]);
          }
          return KeyEventResult.handled;
        }
        final submit = widget.onSubmitted;
        if (submit == null || widget.controller.value.composing.isValid) {
          return KeyEventResult.ignored;
        }
        // Submitted here: a canvas around the field binds Enter for itself.
        if (pressed) {
          submit(widget.controller.text);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape when _hasList:
        _focus.unfocus();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  void _reveal(bool show) {
    if (show == _portal.isShowing) {
      return;
    }
    // Showing an overlay is a mutation, and what to show is only known while
    // the field is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || show == _portal.isShowing) {
        return;
      }
      show ? _portal.show() : _portal.hide();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MapSuggestionBox(
      controller: widget.controller,
      focusNode: _focus,
      builder: (context, status) {
        if (!identical(status.suggestions, _status.suggestions)) {
          _highlighted = null;
        }
        _status = status;
        _reveal(_hasList);
        return CompositedTransformTarget(
          key: _anchor,
          link: _link,
          child: OverlayPortal.targetsRootOverlay(
            controller: _portal,
            overlayChildBuilder: _buildList,
            child: _buildField(widget.palette),
          ),
        );
      },
    );
  }

  Widget _buildField(MapPalette palette) {
    return SizedBox(
      height: widget.height,
      // Editing keys stay with the field rather than reaching the page, the
      // canvas or the dashboard it sits in.
      child: TextEntryShortcuts(
        child: Focus(
          // Nearer than the field's own editing keys, so the arrows, Enter and
          // Escape drive the list while it is open.
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            autofocus: widget.autofocus,
            onSubmitted: (value) {
              if (_highlighted == null) {
                widget.onSubmitted?.call(value);
              }
            },
            style: TextStyle(fontSize: 13, color: palette.textPrimary),
            cursorColor: palette.accent,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: palette.hover,
              hoverColor: Colors.transparent,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 16,
                color: palette.textMuted,
              ),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 32, minHeight: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide.none,
              ),
              hintText: widget.hintText,
              hintStyle: TextStyle(fontSize: 13, color: palette.textMuted),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final status = _status;
    final query = widget.controller.text.trim();
    final hint = status.suggestions.isNotEmpty
        ? ''
        : status.busy
            ? LocaleKeys.map_searchingPlaces.tr()
            : query.length >= 3
                ? LocaleKeys.map_noPlacesFound.tr()
                : '';

    // A field near the bottom of the window opens its list upwards.
    var width = MapMetrics.searchWidth;
    var opensUp = false;
    var maxHeight = _maxListHeight;
    final box = _anchor.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      width = box.size.width;
      final window = MediaQuery.sizeOf(context);
      final top = box.localToGlobal(Offset.zero).dy;
      final below = window.height - top - box.size.height - _gap - _margin;
      final above = top - _gap - _margin;
      opensUp = below < _minListHeight && above > below;
      maxHeight =
          (opensUp ? above : below).clamp(_minListHeight, _maxListHeight);
    }

    // The overlay hands its child the window's own tight constraints; the
    // Align lets the list take only the room it needs.
    return Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: _link,
        targetAnchor: opensUp ? Alignment.topLeft : Alignment.bottomLeft,
        followerAnchor: opensUp ? Alignment.bottomLeft : Alignment.topLeft,
        offset: Offset(0, opensUp ? -_gap : _gap),
        // A row is chosen on pointer down; the field must not take that same
        // press for a tap outside it and close the list first.
        child: TextFieldTapRegion(
          child: MapSuggestionList(
            palette: widget.palette,
            suggestions: status.suggestions,
            onPicked: _pick,
            width: width,
            maxHeight: maxHeight,
            busy: status.busy,
            hint: hint,
            highlighted: _highlighted,
          ),
        ),
      ),
    );
  }
}
