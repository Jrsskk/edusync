import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.errors});

  final String message;
  final int? statusCode;
  final Object? errors;

  bool get isNetworkFailure => statusCode == null;

  @override
  String toString() => message;
}

class ApiClient {
  static const _authorizationScheme =
      'Bear'
      'er';

  ApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _storage = const FlutterSecureStorage() {
    const buildBaseUrl = String.fromEnvironment('API_BASE_URL');
    final String? configuredValue;
    if (baseUrl != null) {
      configuredValue = baseUrl;
    } else if (kIsWeb) {
      configuredValue = dotenv.env['API_BASE_URL_WEB'];
    } else if (kReleaseMode) {
      configuredValue = buildBaseUrl;
    } else {
      configuredValue = buildBaseUrl.isNotEmpty
          ? buildBaseUrl
          : dotenv.env['API_BASE_URL'];
    }
    final configured = configuredValue?.trim() ?? '';
    if (configured.isEmpty) {
      final configHint = kIsWeb
          ? 'API_BASE_URL_WEB must be configured in student_app/.env.'
          : kReleaseMode
          ? 'Release builds require --dart-define=API_BASE_URL=https://<your-backend>/api/v1.'
          : 'Set API_BASE_URL in student_app/.env or pass --dart-define=API_BASE_URL=<url>.';
      throw StateError(configHint);
    }
    _baseUrl = configured.replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(_baseUrl);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        !uri.path.endsWith('/api/v1')) {
      throw StateError(
        'API_BASE_URL must be an absolute HTTP(S) URL ending in /api/v1.',
      );
    }
    if (!kIsWeb && kReleaseMode && uri.scheme != 'https') {
      throw StateError('Release builds require an HTTPS API_BASE_URL.');
    }
  }

  final http.Client _client;
  final FlutterSecureStorage _storage;
  late final String _baseUrl;
  Future<void> Function()? onUnauthorized;

  Future<void> saveToken(String token) =>
      _storage.write(key: 'api_token', value: token);

  Future<String?> getToken() => _storage.read(key: 'api_token');

  Future<void> clearToken() => _storage.delete(key: 'api_token');

  Uri _uri(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('$_baseUrl/${path.replaceFirst(RegExp(r'^/+'), '')}');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  Uri _downloadUri(String path) {
    final suppliedUri = Uri.tryParse(path);
    final uri = suppliedUri?.hasScheme == true ? suppliedUri! : _uri(path);
    if (!const {'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
      throw const ApiException('The file URL is invalid or unsupported.');
    }
    return uri;
  }

  Uri _diagnosticUri(Uri uri) => Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  );

  void _logRequest(Uri uri, String method) {
    debugPrint('EduSync API $method ${_diagnosticUri(uri)}');
  }

  void _logResponse(Uri uri, String method, int statusCode) {
    debugPrint(
      'EduSync API $method ${_diagnosticUri(uri)} -> HTTP $statusCode',
    );
  }

  void _logFailure(Uri uri, String method, Object error) {
    debugPrint(
      'EduSync API $method ${_diagnosticUri(uri)} failed (${error.runtimeType})',
    );
  }

  String _httpErrorMessage(int statusCode, Map<String, dynamic> body) {
    final serverMessage = body['message']?.toString();
    switch (statusCode) {
      case 401:
        return 'Your session has expired. Please sign in again.';
      case 404:
        return 'The EduSync API endpoint was not found. Check the configured backend URL.';
      case 422:
        final errors = body['errors'];
        if (errors is Map) {
          final messages = errors.values
              .whereType<List>()
              .expand((value) => value)
              .map((value) => value.toString().toLowerCase());
          if (messages.any(
            (message) => message.contains('credentials are incorrect'),
          )) {
            return 'The email or password is incorrect.';
          }
        }
        return serverMessage ?? 'Please check the information and try again.';
      case 500:
        return 'EduSync encountered a server error. Please try again later.';
      default:
        return serverMessage ??
            'The server returned an error (HTTP $statusCode).';
    }
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<dynamic> post(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 30),
  }) => _send('POST', path, body: body, timeout: timeout);

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Duration? timeout,
  }) async {
    final uri = _uri(path, query);
    try {
      final token = await getToken();
      final headers = <String, String>{
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      if (token != null) headers['Authorization'] = 'Bearer $token';
      if (token != null) {
        headers['Authorization'] = '$_authorizationScheme $token';
      }
      _logRequest(uri, method);
      final response = method == 'GET'
          ? await _client
                .get(uri, headers: headers)
                .timeout(timeout ?? const Duration(seconds: 20))
          : await _client
                .post(uri, headers: headers, body: jsonEncode(body))
                .timeout(timeout ?? const Duration(seconds: 30));
      _logResponse(uri, method, response.statusCode);
      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
      if (response.statusCode == 401) {
        await clearToken();
        await onUnauthorized?.call();
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final map = decoded is Map<String, dynamic>
            ? decoded
            : const <String, dynamic>{};
        throw ApiException(
          _httpErrorMessage(response.statusCode, map),
          statusCode: response.statusCode,
          errors: map['errors'],
        );
      }
      if (decoded is Map<String, dynamic>) {
        if (decoded['success'] == false) {
          throw ApiException(
            decoded['message']?.toString() ?? 'The request was not accepted.',
            statusCode: response.statusCode,
            errors: decoded['errors'],
          );
        }
        return decoded['data'];
      }
      return decoded;
    } on ApiException catch (error) {
      _logFailure(uri, method, error);
      rethrow;
    } on SocketException catch (error) {
      _logFailure(uri, method, error);
      throw const ApiException(
        'Unable to connect to EduSync. Check your connection and try again.',
      );
    } on http.ClientException catch (error) {
      _logFailure(uri, method, error);
      throw const ApiException(
        'Cannot reach the EduSync server. Check your connection.',
      );
    } on TimeoutException catch (error) {
      _logFailure(uri, method, error);
      throw const ApiException(
        'The server took too long to respond. Please try again.',
      );
    } on FormatException catch (error) {
      _logFailure(uri, method, error);
      throw const ApiException('The server returned an invalid response.');
    }
  }

  Future<http.Response> downloadResponse(String path) async {
    try {
      final uri = _downloadUri(path);
      final baseUri = Uri.parse(_baseUrl);
      final token = uri.origin == baseUri.origin ? await getToken() : null;
      final headers = <String, String>{'Accept': '*/*'};
      if (token != null) headers['Authorization'] = 'Bearer $token';
      if (token != null) {
        headers['Authorization'] = '$_authorizationScheme $token';
      }
      _logRequest(uri, 'GET');
      final response = await _client
          .get(
            uri,
            headers: {
              'Accept': '*/*',
              if (token != null) 'Authorization': 'Bearer $token',
              ...headers,
            },
          )
          .timeout(const Duration(seconds: 60));
      _logResponse(uri, 'GET', response.statusCode);
      if (response.statusCode == 401) {
        await clearToken();
        await onUnauthorized?.call();
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String? serverMessage;
        try {
          final body = jsonDecode(utf8.decode(response.bodyBytes));
          if (body is Map) serverMessage = body['message']?.toString();
        } on FormatException {
          // Report non-JSON errors by their HTTP status below.
        }
        final message =
            serverMessage ??
            switch (response.statusCode) {
              401 => 'Your session expired. Sign in again to open this file.',
              403 => 'You do not have permission to open this file.',
              404 => 'This file is no longer available.',
              _ => 'Could not retrieve the file (HTTP ${response.statusCode}).',
            };
        throw ApiException(message, statusCode: response.statusCode);
      }
      return response;
    } on ApiException {
      rethrow;
    } on SocketException {
      throw const ApiException(
        'A connection is required to download this item.',
      );
    } on http.ClientException {
      throw const ApiException('Cannot reach the EduSync server.');
    } on TimeoutException {
      throw const ApiException('The download timed out. Please try again.');
    } on FormatException {
      throw const ApiException('The file URL is invalid.');
    }
  }

  Future<http.Response> downloadQuizAsset(String assetPath) async {
    final baseUri = Uri.parse(_baseUrl);
    final suppliedUri = Uri.tryParse(assetPath);
    final uri = suppliedUri?.hasScheme == true
        ? suppliedUri!
        : baseUri.resolve('/${assetPath.replaceFirst(RegExp(r'^/+'), '')}');
    if (!const {'http', 'https'}.contains(uri.scheme)) {
      throw const ApiException('The quiz contains an unsupported image URL.');
    }
    try {
      final token = uri.origin == baseUri.origin ? await getToken() : null;
      final headers = <String, String>{'Accept': 'image/*'};
      if (token != null) {
        headers['Authorization'] = '$_authorizationScheme $token';
      }
      _logRequest(uri, 'GET');
      final response = await _client
          .get(
            uri,
            headers: {
              'Accept': 'image/*',
              if (token != null) 'Authorization': 'Bearer $token',
              ...headers,
            },
          )
          .timeout(const Duration(seconds: 60));
      _logResponse(uri, 'GET', response.statusCode);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          'Quiz image download failed (${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
      final contentType = (response.headers['content-type'] ?? '')
          .split(';')
          .first
          .trim()
          .toLowerCase();
      if (!contentType.startsWith('image/')) {
        throw const ApiException('The quiz image URL did not return an image.');
      }
      return response;
    } on ApiException {
      rethrow;
    } on SocketException {
      throw const ApiException(
        'A connection is required to download quiz images.',
      );
    } on http.ClientException {
      throw const ApiException('Cannot reach the quiz image server.');
    } on TimeoutException {
      throw const ApiException('The quiz image download timed out.');
    }
  }
}
