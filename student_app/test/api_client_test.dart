import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:student_app/data/api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(storageChannel, (_) async => null);

  test('socket failures explain that sign-in cannot reach EduSync', () async {
    final client = MockClient((_) async {
      throw const SocketException('No route to host');
    });
    final api = ApiClient(
      client: client,
      baseUrl: 'http://10.0.2.2:8000/api/v1',
    );

    await expectLater(
      api.post('/login', {
        'email': 'student@example.test',
        'password': 'secret',
      }),
      throwsA(
        isA<ApiException>()
            .having((error) => error.isNetworkFailure, 'isNetworkFailure', true)
            .having(
              (error) => error.message,
              'message',
              'Unable to connect to EduSync. Check your connection and try again.',
            ),
      ),
    );
  });

  test('API exceptions distinguish network failures from HTTP errors', () {
    expect(const ApiException('offline').isNetworkFailure, isTrue);
    expect(
      const ApiException('unauthorized', statusCode: 401).isNetworkFailure,
      isFalse,
    );
  });

  test('login requests use the Laravel API route and field names', () async {
    final client = MockClient((request) async {
      expect(request.url, Uri.parse('https://api.edusync.test/api/v1/login'));
      expect(request.method, 'POST');
      expect(request.headers['content-type'], 'application/json');
      expect(
        request.body,
        '{"email":"student@example.test","password":"secret","device_name":"EduSync Student Android"}',
      );
      return http.Response('{"success":true,"data":{"token":"test"}}', 200);
    });
    final api = ApiClient(
      client: client,
      baseUrl: 'https://api.edusync.test/api/v1',
    );

    await api.post('/login', {
      'email': 'student@example.test',
      'password': 'secret',
      'device_name': 'EduSync Student Android',
    });
  });

  test('Sanctum tokens are sent as authorization headers', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          storageChannel,
          (call) async => call.method == 'read' ? 'test-token-value' : null,
        );
    final client = MockClient((request) async {
      final authorization = request.headers['authorization']!;
      expect(authorization.startsWith('Bear'), isTrue);
      expect(authorization.endsWith('test-token-value'), isTrue);
      expect(authorization.split(' '), hasLength(2));
      return http.Response('{"success":true,"data":{}}', 200);
    });
    final api = ApiClient(
      client: client,
      baseUrl: 'https://api.edusync.test/api/v1',
    );

    try {
      await api.get('/me');
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(storageChannel, (_) async => null);
    }
  });

  test(
    'HTTP errors show authentication, route, validation, and server details',
    () async {
      final cases = [
        (
          status: 401,
          body: '{"message":"Unauthenticated."}',
          message: 'Your session has expired. Please sign in again.',
        ),
        (
          status: 404,
          body: '{"message":"Not Found"}',
          message: 'The EduSync API endpoint was not found. Check the configured backend URL.',
        ),
        (
          status: 422,
          body: '{"message":"The given data was invalid.","errors":{"email":["The provided credentials are incorrect."]}}',
          message: 'The email or password is incorrect.',
        ),
        (
          status: 500,
          body: '{"message":"Server Error"}',
          message:
              'EduSync encountered a server error. Please try again later.',
        ),
      ];

      for (final testCase in cases) {
        final client = MockClient(
          (_) async => http.Response(
            testCase.body,
            testCase.status,
            headers: {'content-type': 'application/json'},
          ),
        );
        final api = ApiClient(
          client: client,
          baseUrl: 'https://api.edusync.test/api/v1',
        );

        await expectLater(
          api.post('/login', {
            'email': 'student@example.test',
            'password': 'secret',
          }),
          throwsA(
            isA<ApiException>()
                .having(
                  (error) => error.statusCode,
                  'statusCode',
                  testCase.status,
                )
                .having(
                  (error) => error.isNetworkFailure,
                  'isNetworkFailure',
                  false,
                )
                .having((error) => error.message, 'message', testCase.message),
          ),
        );
      }
    },
  );

  test('POST requests accept a longer timeout when needed', () async {
    final client = MockClient((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return http.Response('{}', 200);
    });
    final api = ApiClient(
      client: client,
      baseUrl: 'https://api.edusync.test/api/v1',
    );

    await expectLater(
      api.post('/login', {
        'email': 'student@example.test',
        'password': 'secret',
      }, timeout: const Duration(milliseconds: 1)),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          'The server took too long to respond. Please try again.',
        ),
      ),
    );
  });

  test('downloads use an API-provided absolute file URL unchanged', () async {
    final fileUrl = Uri.parse(
      'https://files.edusync.test/api/v1/materials/31/file?download=1',
    );
    final client = MockClient((request) async {
      expect(request.url, fileUrl);
      expect(request.headers.containsKey('authorization'), isFalse);
      return http.Response(
        'pdf-content',
        200,
        headers: {'content-type': 'application/pdf'},
      );
    });
    final api = ApiClient(
      client: client,
      baseUrl: 'https://api.edusync.test/api/v1',
    );

    final response = await api.downloadResponse(fileUrl.toString());

    expect(response.body, 'pdf-content');
    expect(response.headers['content-type'], 'application/pdf');
  });

  test(
    'download errors preserve Laravel messages for unavailable files',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          '{"message":"The material file could not be found."}',
          404,
          headers: {'content-type': 'application/json'},
        ),
      );
      final api = ApiClient(
        client: client,
        baseUrl: 'https://api.edusync.test/api/v1',
      );

      await expectLater(
        api.downloadResponse('https://files.edusync.test/materials/31/file'),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 404)
              .having(
                (error) => error.message,
                'message',
                'The material file could not be found.',
              ),
        ),
      );
    },
  );
}
