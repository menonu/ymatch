import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';
import '../models/models.dart';
import 'mutation_controller.dart';

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
/// SnackBar logic at each call site.
///
/// #498: failures rethrow so callers detect outcome from the [Future];
/// concurrent mutations use [ConcurrentMutationMixin] so they cannot
/// clobber each other's success/error on the shared slot.
class MatchController extends StateNotifier<AsyncValue<void>>
    with ConcurrentMutationMixin {
  final ApiClient client;
  final Ref ref;

  MatchController(this.client, this.ref) : super(const AsyncValue.data(null));

  void _invalidateMatchLists(int userId) {
    ref.invalidate(matchesProvider(userId));
    ref.invalidate(notificationCountsProvider(userId));
  }

  Future<void> submitOffer(int userId, int matchId, List<OfferItem> items) {
    return runMutation(() async {
      final payload = OfferTradeRequest()
        ..userId = userId
        ..items.addAll(items);
      await client.post(
        '/api/v1/matches/$matchId/offer',
        payload.toProto3Json() as Map<String, dynamic>,
      );
      _invalidateMatchLists(userId);
    });
  }

  Future<void> updateStatus(int userId, int matchId, String status) {
    return runMutation(() async {
      final payload = UpdateMatchStatusRequest()
        ..status = status
        ..userId = userId;
      await client.post(
        '/api/v1/matches/$matchId/status',
        payload.toProto3Json() as Map<String, dynamic>,
      );
      _invalidateMatchLists(userId);
    });
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
  }) {
    return runMutation(() async {
      final payload = ApplyInventoryRequest()
        ..userId = userId
        ..skipHaveDecrement = skipHaveDecrement;
      await client.post(
        '/api/v1/matches/$matchId/apply-inventory',
        payload.toProto3Json() as Map<String, dynamic>,
      );
      _invalidateMatchLists(userId);
    });
  }
}

final matchControllerProvider =
    StateNotifierProvider<MatchController, AsyncValue<void>>((ref) {
      return MatchController(ref.watch(apiClientProvider), ref);
    });
