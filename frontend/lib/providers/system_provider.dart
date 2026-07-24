import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';

// --- System ---
final backendSystemStatusProvider = FutureProvider<Map<String, dynamic>>((
  ref,
) async {
  final client = ref.watch(apiClientProvider);
  try {
    final response = await client.get('/api/v1/system/status');
    return response as Map<String, dynamic>;
  } catch (e) {
    return {'backend_version': 'error', 'resources': null};
  }
});

// Checks if backend is reachable. Can be invalidated to recheck.
final backendHealthProvider = FutureProvider.autoDispose<bool>((ref) async {
  final client = ref.watch(apiClientProvider);
  try {
    await client.get('/api/v1/events');
    return true;
  } on BackendUnavailableException {
    return false;
  } catch (_) {
    // Other errors (e.g. 401) still mean backend is reachable
    return true;
  }
});
