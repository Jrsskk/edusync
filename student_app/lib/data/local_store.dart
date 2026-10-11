import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class LocalStore {
  Database? _database;
  final _secureStorage = const FlutterSecureStorage();
  int? _studentId;

  Future<void> activateStudent(int studentId) async {
    if (_studentId == studentId && (kIsWeb || _database != null)) return;
    await _database?.close();
    _database = null;
    _studentId = studentId;
    await _secureStorage.write(
      key: 'local_student_id',
      value: studentId.toString(),
    );
    if (!kIsWeb) await database;
  }

  Future<bool> restoreLastStudent() async {
    final storedId = await _secureStorage.read(key: 'local_student_id');
    final studentId = int.tryParse(storedId ?? '');
    if (studentId == null) return false;
    await activateStudent(studentId);
    return true;
  }

  Future<Database> get database async {
    if (kIsWeb) {
      throw UnsupportedError('Browser storage uses local storage, not SQLite.');
    }
    if (_studentId == null) {
      throw StateError(
        'Activate a Student account before opening local storage.',
      );
    }
    if (_database != null) return _database!;
    final directory = await getApplicationDocumentsDirectory();
    _database = await openDatabase(
      p.join(directory.path, 'edusync_student_$_studentId.db'),
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE cached_data (
            cache_key TEXT PRIMARY KEY,
            json_data TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE offline_files (
            cache_key TEXT PRIMARY KEY,
            file_path TEXT NOT NULL,
            file_name TEXT NOT NULL,
            saved_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE offline_quizzes (
            quiz_id INTEGER PRIMARY KEY,
            json_data TEXT NOT NULL,
            downloaded_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE sync_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sync_uuid TEXT NOT NULL UNIQUE,
            entity_type TEXT NOT NULL,
            entity_id INTEGER NOT NULL,
            payload TEXT NOT NULL,
            state TEXT NOT NULL CHECK (state IN ('pending', 'syncing', 'success', 'failed')),
            error TEXT,
            created_at TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE offline_quizzes (
              quiz_id INTEGER PRIMARY KEY,
              json_data TEXT NOT NULL,
              downloaded_at TEXT NOT NULL
            )
          ''');
        }
      },
    );
    return _database!;
  }

  Future<void> cache(String key, dynamic value) async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      _checkStorageWrite(
        await preferences.setString(_webKey('cache.$key'), jsonEncode(value)),
      );
      _checkStorageWrite(
        await preferences.setString(
          _webKey('cache-time.$key'),
          DateTime.now().toUtc().toIso8601String(),
        ),
      );
      return;
    }
    final db = await database;
    await db.insert('cached_data', {
      'cache_key': key,
      'json_data': jsonEncode(value),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<dynamic> readCache(String key) async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      final value = preferences.getString(_webKey('cache.$key'));
      return value == null ? null : jsonDecode(value);
    }
    final db = await database;
    final rows = await db.query(
      'cached_data',
      where: 'cache_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['json_data']! as String);
  }

  Future<void> removeCache(String key) async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_webKey('cache.$key'));
      await preferences.remove(_webKey('cache-time.$key'));
      return;
    }
    final db = await database;
    await db.delete('cached_data', where: 'cache_key = ?', whereArgs: [key]);
  }

  Future<String?> cachedAt(String key) async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getString(_webKey('cache-time.$key'));
    }
    final db = await database;
    final rows = await db.query(
      'cached_data',
      columns: ['updated_at'],
      where: 'cache_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['updated_at']! as String;
  }

  Future<void> saveOfflineQuiz(int quizId, Map<String, dynamic> data) async {
    final validated = _validatedQuizData(quizId, data);
    final jsonData = jsonEncode(validated);
    final downloadedAt = DateTime.now().toUtc().toIso8601String();
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      _checkStorageWrite(
        await preferences.setString(
          _webKey('offline-quiz.$quizId'),
          jsonEncode({
            'quiz_id': quizId,
            'json_data': jsonData,
            'downloaded_at': downloadedAt,
          }),
        ),
      );
      if (await offlineQuiz(quizId) == null) {
        throw StateError('Quiz $quizId was not saved for offline access.');
      }
      return;
    }
    final db = await database;
    await db.insert('offline_quizzes', {
      'quiz_id': quizId,
      'json_data': jsonData,
      'downloaded_at': downloadedAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    final saved = await offlineQuiz(quizId);
    if (saved == null) {
      throw StateError('Quiz $quizId was not saved for offline access.');
    }
  }

  Future<Map<String, dynamic>?> offlineQuiz(int quizId) async {
    Map<String, dynamic>? savedData;
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      final value = preferences.getString(_webKey('offline-quiz.$quizId'));
      if (value != null) {
        final row = Map<String, dynamic>.from(jsonDecode(value) as Map);
        if (row['quiz_id'] != quizId) {
          throw FormatException('Saved quiz ID does not match $quizId.');
        }
        savedData = Map<String, dynamic>.from(
          jsonDecode(row['json_data'] as String) as Map,
        );
      }
    } else {
      final db = await database;
      final rows = await db.query(
        'offline_quizzes',
        columns: ['json_data'],
        where: 'quiz_id = ?',
        whereArgs: [quizId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        savedData = Map<String, dynamic>.from(
          jsonDecode(rows.first['json_data']! as String) as Map,
        );
      }
    }
    if (savedData != null) return _validatedQuizData(quizId, savedData);

    // Read downloads written by earlier app versions before the dedicated table existed.
    final previousDownload = await readCache('download.quizzes.$quizId');
    if (previousDownload is Map) {
      return _validatedQuizData(
        quizId,
        Map<String, dynamic>.from(previousDownload),
      );
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> offlineQuizzes() async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      final prefix = _webKey('offline-quiz.');
      return preferences.getKeys().where((key) => key.startsWith(prefix)).map((
        key,
      ) {
        final row = Map<String, dynamic>.from(
          jsonDecode(preferences.getString(key)!) as Map,
        );
        final quizId = row['quiz_id'] as int;
        return _validatedQuizData(
          quizId,
          Map<String, dynamic>.from(
            jsonDecode(row['json_data'] as String) as Map,
          ),
        );
      }).toList();
    }
    final db = await database;
    final rows = await db.query('offline_quizzes');
    return rows
        .map(
          (row) => _validatedQuizData(
            row['quiz_id']! as int,
            Map<String, dynamic>.from(
              jsonDecode(row['json_data']! as String) as Map,
            ),
          ),
        )
        .toList();
  }

  Map<String, dynamic> _validatedQuizData(
    int expectedQuizId,
    Map<String, dynamic> data,
  ) {
    final quiz = data['quiz'];
    final questions = data['questions'];
    final quizId = quiz is Map ? int.tryParse(quiz['id'].toString()) : null;
    final hasUsableQuestions =
        questions is List &&
        questions.isNotEmpty &&
        questions.every(
          (question) =>
              question is Map &&
              question['id'] != null &&
              question['options'] is List &&
              (question['options'] as List).every(
                (option) => option is Map && option['id'] != null,
              ),
        );
    if (quizId != expectedQuizId ||
        quiz is! Map ||
        quiz['title'] == null ||
        !hasUsableQuestions) {
      throw FormatException(
        'Saved quiz data is incomplete or has an unexpected quiz ID.',
      );
    }
    if (data.containsKey('offline_assets')) {
      final assets = data['offline_assets'];
      if (assets is! Map) {
        throw const FormatException('Saved quiz images are incomplete.');
      }
      for (final question in questions) {
        final imagePaths = <dynamic>[question['image_path']];
        final options = question['options'] as List;
        imagePaths.addAll(options.map((option) => option['image_path']));
        for (final imagePath in imagePaths.where(
          (value) => value != null && value.toString().isNotEmpty,
        )) {
          final encoded = assets[imagePath.toString()];
          if (encoded is! String) {
            throw const FormatException('A quiz image was not saved locally.');
          }
          base64Decode(encoded);
        }
      }
    }
    return data;
  }

  Future<List<Map<String, Object?>>> quizAttemptQueueItems() async {
    final items = await queueHistory();
    return items
        .where((item) => item['entity_type'] == 'quiz_attempt')
        .toList();
  }

  Future<void> saveFile(String key, String path, String fileName) async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      _checkStorageWrite(
        await preferences.setString(
          _webKey('file.$key'),
          jsonEncode({
            'cache_key': key,
            'file_path': path,
            'file_name': fileName,
            'saved_at': DateTime.now().toUtc().toIso8601String(),
          }),
        ),
      );
      return;
    }
    final db = await database;
    await db.insert('offline_files', {
      'cache_key': key,
      'file_path': path,
      'file_name': fileName,
      'saved_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, Object?>?> fileFor(String key) async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      final value = preferences.getString(_webKey('file.$key'));
      if (value == null) return null;
      return Map<String, Object?>.from(jsonDecode(value) as Map);
    }
    final db = await database;
    final rows = await db.query(
      'offline_files',
      where: 'cache_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<bool> enqueue({
    required String syncUuid,
    required String entityType,
    required int entityId,
    required Map<String, dynamic> payload,
  }) async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      final queue = _readWebQueue(preferences);
      if (queue.any(
        (item) =>
            item['entity_type'] == entityType && item['entity_id'] == entityId,
      )) {
        return false;
      }
      final nextId =
          queue.fold<int>(
            0,
            (maximum, item) =>
                (item['id'] as int) > maximum ? item['id'] as int : maximum,
          ) +
          1;
      queue.add({
        'id': nextId,
        'sync_uuid': syncUuid,
        'entity_type': entityType,
        'entity_id': entityId,
        'payload': jsonEncode(payload),
        'state': 'pending',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      await _writeWebQueue(preferences, queue);
      return true;
    }
    final db = await database;
    return db.transaction((transaction) async {
      final existing = await transaction.query(
        'sync_queue',
        columns: ['id'],
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: [entityType, entityId],
        limit: 1,
      );
      if (existing.isNotEmpty) return false;
      await transaction.insert('sync_queue', {
        'sync_uuid': syncUuid,
        'entity_type': entityType,
        'entity_id': entityId,
        'payload': jsonEncode(payload),
        'state': 'pending',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      return true;
    });
  }

  Future<List<Map<String, Object?>>> queuedItems() async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      return _readWebQueue(preferences)
          .where(
            (item) =>
                const {'pending', 'failed', 'syncing'}.contains(item['state']),
          )
          .toList()
        ..sort(
          (left, right) => (left['created_at'] as String).compareTo(
            right['created_at'] as String,
          ),
        );
    }
    final db = await database;
    return db.query(
      'sync_queue',
      where: 'state IN (?, ?, ?)',
      whereArgs: ['pending', 'failed', 'syncing'],
      orderBy: 'created_at ASC',
    );
  }

  Future<List<Map<String, Object?>>> queueHistory() async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      final queue = _readWebQueue(preferences)
        ..sort(
          (left, right) => (right['created_at'] as String).compareTo(
            left['created_at'] as String,
          ),
        );
      return queue;
    }
    final db = await database;
    return db.query('sync_queue', orderBy: 'created_at DESC');
  }

  Future<void> setQueueState(int id, String state, {String? error}) async {
    if (!const {'pending', 'syncing', 'success', 'failed'}.contains(state)) {
      throw ArgumentError.value(state, 'state', 'Unsupported sync state.');
    }
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      final queue = _readWebQueue(preferences);
      final index = queue.indexWhere((item) => item['id'] == id);
      if (index < 0) {
        throw StateError('Queued submission $id no longer exists.');
      }
      queue[index]['state'] = state;
      queue[index]['error'] = error;
      await _writeWebQueue(preferences, queue);
      if (state == 'success') {
        await cache(
          'last-sync-at',
          DateTime.now().toUtc().toIso8601String(),
        );
      }
      return;
    }
    final db = await database;
    await db.update(
      'sync_queue',
      {'state': state, 'error': error},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (state == 'success') {
      await cache('last-sync-at', DateTime.now().toUtc().toIso8601String());
    }
  }

  Future<Map<String, int>> queueCounts() async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      final counts = {
        for (final state in ['pending', 'syncing', 'success', 'failed'])
          state: 0,
      };
      for (final item in _readWebQueue(preferences)) {
        final state = item['state'] as String;
        counts[state] = counts[state]! + 1;
      }
      return counts;
    }
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT state, COUNT(*) AS total FROM sync_queue GROUP BY state',
    );
    final counts = {
      for (final state in ['pending', 'syncing', 'success', 'failed']) state: 0,
    };
    for (final row in rows) {
      counts[row['state']! as String] = row['total']! as int;
    }
    return counts;
  }

  String _webKey(String key) {
    final studentId = _studentId;
    if (studentId == null) {
      throw StateError(
        'Activate a Student account before accessing local storage.',
      );
    }
    return 'edusync.student.$studentId.$key';
  }

  List<Map<String, dynamic>> _readWebQueue(SharedPreferences preferences) {
    final data = preferences.getString(_webKey('sync-queue'));
    if (data == null) return [];
    final decoded = jsonDecode(data);
    if (decoded is! List) {
      throw const FormatException('The saved sync queue is invalid.');
    }
    return decoded
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> _writeWebQueue(
    SharedPreferences preferences,
    List<Map<String, dynamic>> queue,
  ) async {
    _checkStorageWrite(
      await preferences.setString(_webKey('sync-queue'), jsonEncode(queue)),
    );
  }

  void _checkStorageWrite(bool saved) {
    if (!saved) {
      throw StateError('The browser could not persist EduSync offline data.');
    }
  }
}
