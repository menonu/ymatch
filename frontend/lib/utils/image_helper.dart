import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Helper to build an image widget from a URL string.
/// Supports both standard HTTP(S) URLs and base64-encoded data URIs.
Widget buildImage(
  String? url, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  Widget? placeholder,
  Widget? errorWidget,
}) {
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

  if (url == null || url.isEmpty) {
    return defaultPlaceholder;
  }

  // Handle Base64 Data URI
  if (url.startsWith('data:image')) {
    try {
      final base64String = url.split(',').last;
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
    url,
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
