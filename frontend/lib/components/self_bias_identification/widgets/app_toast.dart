import 'package:flutter/material.dart';
import 'package:frontend/components/self_bias_identification/services/api_service.dart';

enum ToastType { success, warning, error, info }

/// Short, consistent feedback messages (SnackBars) for this component.
///
/// One at a time: a new toast replaces the one on screen. They live on the
/// app-level messenger, so a toast shown just before a screen closes is still
/// visible on the screen underneath.
class AppToast {
  static void success(BuildContext context, String message) =>
      _show(context, ToastType.success, message);

  static void warning(BuildContext context, String message) =>
      _show(context, ToastType.warning, message);

  static void error(BuildContext context, String message) =>
      _show(context, ToastType.error, message);

  static void info(BuildContext context, String message) =>
      _show(context, ToastType.info, message);

  /// Plain-language text for a failed request, instead of a raw exception.
  static String friendlyError(Object error) {
    if (error is ApiException) return error.message;
    final text = error.toString();
    if (text.contains('TimeoutException')) {
      return 'The server is taking too long to answer. Try again in a moment.';
    }
    const network = [
      'SocketException',
      'ClientException',
      'Connection refused',
      'Failed host lookup',
      'Connection closed',
    ];
    if (network.any(text.contains)) {
      return "Can't reach the server. Check your connection.";
    }
    return 'Something went wrong. Please try again.';
  }

  static Color colorFor(ToastType type) {
    switch (type) {
      case ToastType.success:
        return const Color(0xFF4ADE80);
      case ToastType.warning:
        return const Color(0xFFFFC857);
      case ToastType.error:
        return const Color(0xFFFF6B6B);
      case ToastType.info:
        return const Color(0xFFB2A8FF);
    }
  }

  static IconData _iconFor(ToastType type) {
    switch (type) {
      case ToastType.success:
        return Icons.check_circle_rounded;
      case ToastType.warning:
        return Icons.warning_amber_rounded;
      case ToastType.error:
        return Icons.error_rounded;
      case ToastType.info:
        return Icons.info_rounded;
    }
  }

  static void _show(BuildContext context, ToastType type, String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final color = colorFor(type);
    final wide = MediaQuery.sizeOf(context).width > 600;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF151B26),
          elevation: 0,
          // On a wide laptop window a full-width bar looks stretched.
          width: wide ? 520 : null,
          margin: wide ? null : const EdgeInsets.fromLTRB(16, 0, 16, 16),
          duration: Duration(seconds: type == ToastType.error ? 5 : 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: color.withValues(alpha: 0.45)),
          ),
          content: Row(
            children: [
              Icon(_iconFor(type), color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }
}
