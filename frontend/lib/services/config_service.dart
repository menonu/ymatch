import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

class ConfigService {
  final bool enableAdminDashboard = true;

  // Compile-time API_BASE_URL override (set via --dart-define=API_BASE_URL=...)
  static const String _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  String get baseUrl {
    // If a compile-time API_BASE_URL is provided, use it (production deploy)
    if (_apiBaseUrl.isNotEmpty) {
      return _apiBaseUrl;
    }
    // Local development: use same host the page was loaded from
    if (kIsWeb) {
      final host = Uri.base.host;
      final scheme = Uri.base.scheme;
      return '$scheme://$host:3000';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://localhost:3000';
  }
}

final configServiceProvider = Provider((ref) => ConfigService());
