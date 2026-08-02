import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Concurrent-safe mutation runner for singleton controllers that expose a
/// single shared `AsyncValue<void>` loading/error slot (#498).
///
/// Each [runMutation] call gets a generation id. Only the latest generation
/// may write [state], so overlapping mutations cannot clobber each other's
/// success/error. Every failure is rethrown so callers detect outcome from
/// the returned [Future] (not by racing the shared slot).
mixin ConcurrentMutationMixin on StateNotifier<AsyncValue<void>> {
  int _generation = 0;

  /// Run [body], updating [state] only if this call is still the latest.
  ///
  /// On success: sets [AsyncData] when still current, returns the result.
  /// On failure: sets [AsyncError] when still current, then rethrows.
  Future<T> runMutation<T>(Future<T> Function() body) async {
    final gen = ++_generation;
    state = const AsyncValue.loading();
    try {
      final result = await body();
      if (gen == _generation) {
        state = const AsyncValue.data(null);
      }
      return result;
    } catch (e, st) {
      if (gen == _generation) {
        state = AsyncValue.error(e, st);
      }
      rethrow;
    }
  }
}
