import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:student_app/data/api_client.dart';
import 'package:student_app/data/local_store.dart';
import 'package:student_app/data/sync_service.dart';

void main() {
  test(
    'queues created during a sync are sent before synchronization stops',
    () async {
      const existingUuid = 'a1f67e86-e148-47d0-af3a-a87af2ae04cb';
      final store = _MemoryStore()
        ..add(
          id: 1,
          syncUuid: existingUuid,
          entityId: 10,
          payload: {'quiz_id': 10, 'answers': []},
        );
      final firstRequestStarted = Completer<void>();
      final finishFirstRequest = Completer<void>();
      final api = _TestApiClient((body) async {
        final syncUuid = body['sync_uuid'] as String;
        if (syncUuid == existingUuid) {
          firstRequestStarted.complete();
          await finishFirstRequest.future;
        }
        return {'sync_uuid': syncUuid, 'status': 'synced'};
      });
      final sync = SyncService(api, store);

      final initialSync = sync.syncPending();
      await firstRequestStarted.future;
      final inserted = await sync.queue(
        entityType: 'quiz_attempt',
        entityId: 11,
        payload: {'quiz_id': 11, 'answers': []},
      );
      finishFirstRequest.complete();
      await initialSync;

      expect(inserted, isTrue);
      expect(api.requests, hasLength(2));
      expect(store.states.values, everyElement('success'));
      await sync.dispose();
    },
  );

  test(
    'keeps a queue item failed until the server confirms its sync UUID',
    () async {
      const syncUuid = '961aa6fd-08cc-4bfe-8e40-4f138117a172';
      final store = _MemoryStore()
        ..add(
          id: 1,
          syncUuid: syncUuid,
          entityId: 12,
          payload: {'quiz_id': 12, 'answers': []},
        );
      final sync = SyncService(
        _TestApiClient(
          (_) async => {
            'sync_uuid': 'c6bb8d5f-a98e-4564-9de9-8cd48cac44d1',
            'status': 'synced',
          },
        ),
        store,
      );

      await sync.syncPending();

      expect(store.states[1], 'failed');
      expect(
        store.errors[1],
        'The server did not confirm this submission as synchronized.',
      );
      await sync.dispose();
    },
  );
}

class _TestApiClient extends ApiClient {
  _TestApiClient(this.respond)
    : super(baseUrl: 'http://192.168.1.10:8000/api/v1');

  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) respond;
  final requests = <Map<String, dynamic>>[];

  @override
  Future<dynamic> post(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    expect(path, '/sync');
    requests.add(body);
    return respond(body);
  }
}

class _MemoryStore extends LocalStore {
  final _items = <Map<String, Object?>>[];
  final states = <int, String>{};
  final errors = <int, String?>{};
  int _nextId = 1;

  void add({
    required int id,
    required String syncUuid,
    required int entityId,
    required Map<String, dynamic> payload,
  }) {
    _items.add({
      'id': id,
      'sync_uuid': syncUuid,
      'entity_type': 'quiz_attempt',
      'entity_id': entityId,
      'payload': jsonEncode(payload),
      'state': 'pending',
    });
    states[id] = 'pending';
    _nextId = id + 1;
  }

  @override
  Future<bool> enqueue({
    required String syncUuid,
    required String entityType,
    required int entityId,
    required Map<String, dynamic> payload,
  }) async {
    add(id: _nextId, syncUuid: syncUuid, entityId: entityId, payload: payload);
    _items.last['entity_type'] = entityType;
    return true;
  }

  @override
  Future<List<Map<String, Object?>>> queuedItems() async => _items
      .where((item) => states[item['id']] != 'success')
      .map((item) => {...item, 'state': states[item['id']]})
      .toList();

  @override
  Future<void> setQueueState(int id, String state, {String? error}) async {
    states[id] = state;
    errors[id] = error;
  }
}
