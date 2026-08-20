import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';

/// Catches a failure inside something an extension drew.
///
/// ⚠️ A compiled-in extension that throws in `build` takes the whole frame
/// down — the app goes red, not the block. This puts the failure back where it
/// belongs and names who caused it, so a bad extension costs one card rather
/// than the window.
class ExtensionBoundary extends StatefulWidget {
  const ExtensionBoundary({
    super.key,
    required this.extensionId,
    required this.child,
    this.label = '',
  });

  final String extensionId;
  final String label;
  final Widget child;

  @override
  State<ExtensionBoundary> createState() => _ExtensionBoundaryState();
}

class _ExtensionBoundaryState extends State<ExtensionBoundary> {
  FlutterErrorDetails? _failure;

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    if (failure != null) {
      return _ExtensionFailure(
        extensionId: widget.extensionId,
        label: widget.label,
        message: failure.exceptionAsString(),
        onRetry: () => setState(() => _failure = null),
      );
    }

    // ⚠️ `ErrorWidget.builder` is global, so it is swapped only for the length
    // of this subtree's build and always put back.
    return _CatchingBuilder(
      onError: (details) {
        Log.warn(
          'Extension ${widget.extensionId} failed to draw: '
          '${details.exceptionAsString()}',
        );
        // Never setState during build.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _failure = details);
          }
        });
      },
      child: widget.child,
    );
  }
}

class _CatchingBuilder extends StatelessWidget {
  const _CatchingBuilder({required this.onError, required this.child});

  final ValueChanged<FlutterErrorDetails> onError;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final previous = ErrorWidget.builder;
    ErrorWidget.builder = (details) {
      onError(details);
      return const SizedBox.shrink();
    };
    try {
      return child;
    } finally {
      ErrorWidget.builder = previous;
    }
  }
}

class _ExtensionFailure extends StatelessWidget {
  const _ExtensionFailure({
    required this.extensionId,
    required this.label,
    required this.message,
    required this.onRetry,
  });

  final String extensionId;
  final String label;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.extension_off_rounded,
            size: 18,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.isEmpty
                      ? '$extensionId could not draw this.'
                      : '$extensionId could not draw $label.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.error),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
