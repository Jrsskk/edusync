import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';

import 'api_client.dart';
import 'local_store.dart';

class SyncService {
  SyncService(this.api, this.store);

  final ApiClient api;
  final LocalStore store;
  final String deviceId = const Uuid().v4();
  final StreamController<void> _changes = StreamController<void>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _running = false;
  bool _syncRequested = false;
  bool _started = false;
  int _generation = 0;

  Stream<void> get changes => _changes.stream;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        unawaited(syncPending());
      }
    });
    final current = await Connectivity().checkConnectivity();
    if (current.any((result) => result != ConnectivityResult.none)) {
      unawaited(syncPending());
    }
  }

  Future<void> dispose() async {
    await stop();
    await _changes.close();
  }

  Future<void> stop() async {
    _generation++;
    _started = false;
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<bool> queue({
    required String entityType,
    required int entityId,
    required Map<String, dynamic> payload,
  }) async {
    final inserted = await store.enqueue(
      syncUuid: const Uuid().v4(),
      entityType: entityType,
      entityId: entityId,
      payload: payload,
    );
    if (inserted) _changes.add(null);
    unawaited(syncPending());
    return inserted;
  }

  Future<void> syncPending() async {
    if (_running) {
      _syncRequested = true;
      return;
    }
    _running = true;
    final generation = _generation;
    try {
      do {
        _syncRequested = false;
        final items = await store.queuedItems();
        for (final item in items) {
          if (generation != _generation) break;
          final id = item['id']! as int;
          await store.setQueueState(id, 'syncing');
          _changes.add(null);
          try {
            final syncUuid = item['sync_uuid']! as String;
            final payload =
                jsonDecode(item['payload']! as String) as Map<String, dynamic>;
            final response = await api.post('/sync', {
              'sync_uuid': syncUuid,
              'entity_type': item['entity_type'],
              'entity_id': item['entity_id'],
              'action': 'create',
              'device_id': deviceId,
              'payload': payload,
            });
            if (generation != _generation) break;
            if (response is! Map ||
                response['sync_uuid'] != syncUuid ||
                response['status'] != 'synced') {
              throw const ApiException(
                'The server did not confirm this submission as synchronized.',
                statusCode: 200,
              );
            }
            await store.setQueueState(id, 'success');
            _changes.add(null);
          } on ApiException catch (error) {
            if (generation != _generation) break;
            await store.setQueueState(id, 'failed', error: error.message);
            _changes.add(null);
            if (error.statusCode == null || error.statusCode == 401) break;
          } catch (error) {
            if (generation != _generation) break;
            await store.setQueueState(id, 'failed', error: error.toString());
            _changes.add(null);
          }
        }
      } while (_syncRequested && generation == _generation);
    } finally {
      _running = false;
      if (_syncRequested && _started) {
        unawaited(syncPending());
      }
    }
  }
}
