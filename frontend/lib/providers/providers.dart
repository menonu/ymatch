/// Barrel re-export of domain providers (#495).
///
/// Screens and tests keep importing `package:frontend/providers/providers.dart`
/// (or relative `providers/providers.dart`); implementation lives in one file
/// per domain under this directory.
library;

export 'member_models.dart';
export 'system_provider.dart';
export 'auth_provider.dart';
export 'events_provider.dart';
export 'merch_provider.dart';
export 'groups_provider.dart';
export 'inventory_provider.dart';
export 'admin_provider.dart';
export 'match_provider.dart';
export 'chat_provider.dart';
export 'search_provider.dart';
