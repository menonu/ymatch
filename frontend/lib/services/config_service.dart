import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

class ConfigService {
  // Use localhost for Android emulator (10.0.2.2), otherwise localhost.
  // Note: For physical device, you'd need the LAN IP.
  final bool enableAdminDashboard = true;

  String get baseUrl {
    if (kIsWeb) return 'http://localhost:3000';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://localhost:3000';
  }
}

final configServiceProvider = Provider((ref) => ConfigService());
