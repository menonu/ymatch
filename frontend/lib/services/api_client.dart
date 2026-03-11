import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config_service.dart';

class ApiClient {
  final ConfigService config;
  final http.Client _client;

  ApiClient(this.config, {http.Client? client})
    : _client = client ?? http.Client();

  Future<dynamic> get(String endpoint) async {
    final uri = Uri.parse('${config.baseUrl}$endpoint');
    final response = await _client.get(uri);
    return _handleResponse(response);
  }

  Future<dynamic> post(String endpoint, Map<String, dynamic> body) async {
    final uri = Uri.parse('${config.baseUrl}$endpoint');
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _handleResponse(response);
  }

  Future<dynamic> delete(String endpoint) async {
    final uri = Uri.parse('${config.baseUrl}$endpoint');
    final response = await _client.delete(uri);
    return _handleResponse(response);
  }

  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.trim().isEmpty) {
        return {}; // Return empty map for 200 OK responses with no body
      }
      return jsonDecode(response.body);
    } else {
      throw Exception('API Error: ${response.statusCode} ${response.body}');
    }
  }
}

final apiClientProvider = Provider((ref) {
  final config = ref.watch(configServiceProvider);
  return ApiClient(config);
});
