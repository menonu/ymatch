import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../l10n/app_localizations.dart';

/// Result of [pickMerchImage]: the raw image bytes, the file name, and a
/// base64 data-URI preview URL.
class PickedImage {
  const PickedImage({
    required this.bytes,
    required this.name,
    required this.previewUrl,
  });

  final Uint8List bytes;
  final String name;
  final String previewUrl;
}

/// Opens a gallery/camera source dialog, picks a merch image resized to
/// 256×256 at quality 85, and returns it with a base64 data-URI preview.
/// Returns null if the user cancels source selection or image picking.
/// On a pick error, shows a `failedToPickImage` snackbar and returns null.
///
/// Shared by `AddMerchScreen` (item creation) and `EditMerchDialog`
/// (item editing, #205) so the two flows cannot drift apart.
Future<PickedImage?> pickMerchImage(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final source = await showDialog<ImageSource>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(l10n.selectImageSource),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, ImageSource.gallery),
          child: Row(
            children: [
              const Icon(Icons.photo_library),
              const SizedBox(width: 12),
              Text(l10n.gallery),
            ],
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, ImageSource.camera),
          child: Row(
            children: [
              const Icon(Icons.camera_alt),
              const SizedBox(width: 12),
              Text(l10n.camera),
            ],
          ),
        ),
      ],
    ),
  );
  if (source == null) return null;

  final ImagePicker picker = ImagePicker();
  try {
    final XFile? image = await picker.pickImage(
      source: source,
      maxWidth: 256,
      maxHeight: 256,
      imageQuality: 85,
    );
    if (image == null) return null;
    final bytes = await image.readAsBytes();
    return PickedImage(
      bytes: bytes,
      name: image.name,
      previewUrl: 'data:image/png;base64,${base64Encode(bytes)}',
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.failedToPickImage(e.toString()))),
      );
    }
    return null;
  }
}

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
