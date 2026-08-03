import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';
import '../models/models.dart';

// --- Search ---

/// Immediate text in the search box (drives home-screen chrome + local filter).
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Debounce window for API search (#498). Empty query applies immediately so
/// clear feels instant; non-empty waits for a short pause after typing.
const searchDebounceDuration = Duration(milliseconds: 250);

/// Debounced mirror of [searchQueryProvider] used by [searchProvider].
///
/// Keeps the keystroke-driven UI query separate from the network query so
/// every character does not hit `/api/v1/search`.
final debouncedSearchQueryProvider =
    StateNotifierProvider<DebouncedSearchQuery, String>((ref) {
      final notifier = DebouncedSearchQuery(
        initial: ref.read(searchQueryProvider),
        duration: searchDebounceDuration,
      );
      ref.listen<String>(searchQueryProvider, (_, next) {
        notifier.schedule(next);
      });
      return notifier;
    });

/// Holds a string that updates after [duration] of quiet time (or immediately
/// when cleared).
class DebouncedSearchQuery extends StateNotifier<String> {
  DebouncedSearchQuery({required String initial, required this.duration})
    : super(initial);

  final Duration duration;
  Timer? _timer;

  void schedule(String value) {
    _timer?.cancel();
    if (value.isEmpty) {
      // Immediate clear — no need to wait after the user hits ×.
      state = '';
      return;
    }
    _timer = Timer(duration, () {
      state = value;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final searchProvider = FutureProvider<List<SearchResult>>((ref) async {
  // Watch the debounced query so rapid typing does not spam the API (#498).
  final query = ref.watch(debouncedSearchQueryProvider);
  if (query.trim().isEmpty) return [];

  final client = ref.watch(apiClientProvider);
  final json = await client.get(
    '/api/v1/search?q=${Uri.encodeComponent(query.trim())}',
  );
  return (json as List)
      .map((e) => SearchResult()..mergeFromProto3Json(e))
      .toList();
});
