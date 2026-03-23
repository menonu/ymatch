import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config_service.dart';

class BackendUnavailableException implements Exception {
  final String message;
  BackendUnavailableException([this.message = 'Backend service unavailable']);
  @override
  String toString() => message;
}

class ApiClient {
  final ConfigService config;
  final http.Client _client;

  ApiClient(this.config, {http.Client? client})
    : _client = client ?? http.Client();

  Future<dynamic> get(String endpoint) async {
    final uri = Uri.parse('${config.baseUrl}$endpoint');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } on BackendUnavailableException {
      rethrow;
    } on SocketException {
      throw BackendUnavailableException();
    } on HttpException {
      throw BackendUnavailableException();
    } on http.ClientException {
      throw BackendUnavailableException();
    } catch (e) {
      if (_isConnectionError(e)) throw BackendUnavailableException();
      rethrow;
    }
  }

  Future<dynamic> post(String endpoint, Map<String, dynamic> body) async {
    final uri = Uri.parse('${config.baseUrl}$endpoint');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } on BackendUnavailableException {
      rethrow;
    } on SocketException {
      throw BackendUnavailableException();
    } on HttpException {
      throw BackendUnavailableException();
    } on http.ClientException {
      throw BackendUnavailableException();
    } catch (e) {
      if (_isConnectionError(e)) throw BackendUnavailableException();
      rethrow;
    }
  }

  Future<dynamic> put(String endpoint, Map<String, dynamic> body) async {
    final uri = Uri.parse('${config.baseUrl}$endpoint');
    try {
      final response = await _client.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } on BackendUnavailableException {
      rethrow;
    } on SocketException {
      throw BackendUnavailableException();
    } on HttpException {
      throw BackendUnavailableException();
    } on http.ClientException {
      throw BackendUnavailableException();
    } catch (e) {
      if (_isConnectionError(e)) throw BackendUnavailableException();
      rethrow;
    }
  }

  Future<dynamic> delete(String endpoint) async {
    final uri = Uri.parse('${config.baseUrl}$endpoint');
    try {
      final response = await _client.delete(uri).timeout(const Duration(seconds: 10));
      return _handleResponse(response);
    } on BackendUnavailableException {
      rethrow;
    } on SocketException {
      throw BackendUnavailableException();
    } on HttpException {
      throw BackendUnavailableException();
    } on http.ClientException {
      throw BackendUnavailableException();
    } catch (e) {
      if (_isConnectionError(e)) throw BackendUnavailableException();
      rethrow;
    }
  }

  bool _isConnectionError(Object e) {
    final msg = e.toString();
    return msg.contains('TimeoutException') ||
        msg.contains('Connection refused') ||
        msg.contains('Failed host lookup') ||
        msg.contains('Network is unreachable') ||
        msg.contains('XMLHttpRequest error');
  }

  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.trim().isEmpty) {
        return {}; // Return empty map for 200 OK responses with no body
      }
      return jsonDecode(response.body);
    } else if (response.statusCode == 503 || response.statusCode == 502) {
      throw BackendUnavailableException(
        'Backend service unavailable (${response.statusCode})',
      );
    } else {
      throw Exception('API Error: ${response.statusCode} ${response.body}');
    }
  }
}

final apiClientProvider = Provider((ref) {
  final config = ref.watch(configServiceProvider);
  return ApiClient(config);
});
