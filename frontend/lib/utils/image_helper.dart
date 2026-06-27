import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Resolve a potentially-relative image URL to an absolute URL.
/// - Absolute URLs (http/https) are returned as-is.
/// - Relative paths (e.g. "uploads/uuid.png") are resolved against the current origin.
String resolveImageUrl(String? url) {
  if (url == null || url.isEmpty) return '';

  // Handle Base64 Data URI
  if (url.startsWith('data:image')) return url;

  // Already an absolute URL
  if (url.startsWith('http://') || url.startsWith('https://')) return url;

  // Use compile-time API_BASE_URL if set (production behind reverse proxy)
  const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  if (apiBaseUrl.isNotEmpty) {
    return '$apiBaseUrl/$url';
  }

  // Local development: backend runs on :3000
  if (kIsWeb) {
    final scheme = Uri.base.scheme;
    final host = Uri.base.host;
    return '$scheme://$host:3000/$url';
  }

  return 'http://localhost:3000/$url';
}

/// Helper to build an image widget from a URL string.
/// Supports both standard HTTP(S) URLs and base64-encoded data URIs.
///
/// Defaults to [BoxFit.contain] so the *entire* uploaded image is visible —
/// non-square images are letterboxed with transparent padding rather than
/// center-cropped (#329). Pass an explicit `fit` to override (e.g. for a
/// hero image that should fill its frame).
Widget buildImage(
  String? url, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.contain,
  Widget? placeholder,
  Widget? errorWidget,
}) {
  final resolvedUrl = resolveImageUrl(url);
  final defaultPlaceholder =
      placeholder ??
      Container(
        width: width,
        height: height,
        color: Colors.grey[200],
        child: Icon(
          Icons.image_outlined,
          size: (width != null && width < 40) ? 20 : 32,
          color: Colors.grey[400],
        ),
      );

  final defaultError =
      errorWidget ??
      Container(
        width: width,
        height: height,
        color: Colors.grey[200],
        child: Icon(
          Icons.broken_image_outlined,
          size: (width != null && width < 40) ? 20 : 32,
          color: Colors.grey[400],
        ),
      );

  if (resolvedUrl.isEmpty) {
    return defaultPlaceholder;
  }

  // Handle Base64 Data URI
  if (resolvedUrl.startsWith('data:image')) {
    try {
      final base64String = resolvedUrl.split(',').last;
      final Uint8List bytes = base64Decode(base64String);
      return Image.memory(
        bytes,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => defaultError,
      );
    } catch (e) {
      return defaultError;
    }
  }

  // Handle standard HTTP URL
  return Image.network(
    resolvedUrl,
    width: width,
    height: height,
    fit: fit,
    loadingBuilder: (context, child, loadingProgress) {
      if (loadingProgress == null) return child;
      return defaultPlaceholder;
    },
    errorBuilder: (context, error, stackTrace) => defaultError,
  );
}
