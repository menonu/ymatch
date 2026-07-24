import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';
import '../models/models.dart';

// --- Matches ---
final matchesProvider = FutureProvider.family<List<TradeMatch>, int>((
  ref,
  userId,
) async {
  final client = ref.watch(apiClientProvider);
  final json = await client.get('/api/v1/matches/user/$userId');
  return (json as List)
      .map((e) => TradeMatch()..mergeFromProto3Json(e))
      .toList();
});

final notificationCountsProvider =
    FutureProvider.family<NotificationCounts, int>((ref, userId) async {
      final client = ref.watch(apiClientProvider);
      final json = await client.get('/api/v1/matches/user/$userId/counts');
      return NotificationCounts()..mergeFromProto3Json(json);
    });

/// Owns the three match-lifecycle mutations used by the trades UI.
///
/// #241: centralizes request body construction (proto types),
/// `matchesProvider` + `notificationCountsProvider` invalidation, and
/// loading/error state so screens can `ref.listen` instead of duplicating
/// try/catch + SnackBar + invalidate at each call site.
class MatchController extends StateNotifier<AsyncValue<void>> {
  final ApiClient client;
  final Ref ref;

  MatchController(this.client, this.ref) : super(const AsyncValue.data(null));

  void _invalidateMatchLists(int userId) {
    ref.invalidate(matchesProvider(userId));
    ref.invalidate(notificationCountsProvider(userId));
  }

  Future<void> submitOffer(
    int userId,
    int matchId,
    List<OfferItem> items,
  ) async {
    state = const AsyncValue.loading();
    try {
      final payload = OfferTradeRequest()
        ..userId = userId
        ..items.addAll(items);
      await client.post(
        '/api/v1/matches/$matchId/offer',
        payload.toProto3Json() as Map<String, dynamic>,
      );
      _invalidateMatchLists(userId);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> updateStatus(int userId, int matchId, String status) async {
    state = const AsyncValue.loading();
    try {
      final payload = UpdateMatchStatusRequest()
        ..status = status
        ..userId = userId;
      await client.post(
        '/api/v1/matches/$matchId/status',
        payload.toProto3Json() as Map<String, dynamic>,
      );
      _invalidateMatchLists(userId);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Apply completed-trade inventory for [userId] on [matchId].
  ///
  /// When [skipHaveDecrement] is false (default, #429), the giver's HAVE
  /// is decremented along with TRADE. When true, only TRADE is decremented
  /// (legacy opt-out).
  Future<void> applyInventory(
    int userId,
    int matchId, {
    bool skipHaveDecrement = false,
  }) async {
    state = const AsyncValue.loading();
    try {
      final payload = ApplyInventoryRequest()
        ..userId = userId
        ..skipHaveDecrement = skipHaveDecrement;
      await client.post(
        '/api/v1/matches/$matchId/apply-inventory',
        payload.toProto3Json() as Map<String, dynamic>,
      );
      _invalidateMatchLists(userId);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final matchControllerProvider =
    StateNotifierProvider<MatchController, AsyncValue<void>>((ref) {
      return MatchController(ref.watch(apiClientProvider), ref);
    });
