import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';
import '../models/models.dart';

// --- Search ---
final searchQueryProvider = StateProvider<String>((ref) => '');

final searchProvider = FutureProvider<List<SearchResult>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().isEmpty) return [];

  final client = ref.watch(apiClientProvider);
  final json = await client.get(
    '/api/v1/search?q=${Uri.encodeComponent(query.trim())}',
  );
  return (json as List)
      .map((e) => SearchResult()..mergeFromProto3Json(e))
      .toList();
});
