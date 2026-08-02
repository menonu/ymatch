import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';
import '../models/models.dart';
import 'auth_provider.dart';
import 'mutation_controller.dart';

// --- Chat ---

/// Messages for a match. Auto-disposes when no longer watched (e.g. chat
/// screen popped). Invalidated by [ChatController.sendMessage] and by the
/// screen's 3s poll timer.
final messagesProvider = FutureProvider.family.autoDispose<List<Message>, int>((
  ref,
  matchId,
) async {
  final client = ref.watch(apiClientProvider);
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  // #491: membership gate via caller user_id.
  final json = await client.get(
    '/api/v1/matches/$matchId/messages?user_id=${user.id}',
  );
  return (json as List).map((e) => Message()..mergeFromProto3Json(e)).toList();
});

/// Owns chat send mutation used by [ChatScreen].
///
/// #245: centralizes `SendMessageRequest` body construction (proto type),
/// `messagesProvider` invalidation, and loading/error state so the screen
/// can `ref.listen` for SnackBars. Polling stays on the screen.
///
/// #498: failures rethrow so callers detect outcome from the [Future];
/// concurrent sends use [ConcurrentMutationMixin] so they cannot clobber
/// each other's success/error on the shared slot.
class ChatController extends StateNotifier<AsyncValue<void>>
    with ConcurrentMutationMixin {
  final ApiClient client;
  final Ref ref;

  ChatController(this.client, this.ref) : super(const AsyncValue.data(null));

  Future<void> sendMessage(int matchId, int senderId, String content) {
    return runMutation(() async {
      final payload = SendMessageRequest()
        ..matchId = matchId
        ..senderId = senderId
        ..content = content;
      await client.post(
        '/api/v1/matches/$matchId/messages',
        payload.toProto3Json() as Map<String, dynamic>,
      );
      ref.invalidate(messagesProvider(matchId));
    });
  }
}

final chatControllerProvider =
    StateNotifierProvider<ChatController, AsyncValue<void>>((ref) {
      return ChatController(ref.watch(apiClientProvider), ref);
    });
