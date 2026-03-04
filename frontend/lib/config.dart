class AppConfig {
  static const bool enableAdminDashboard = bool.fromEnvironment('ENABLE_ADMIN_DASHBOARD', defaultValue: true);
}
