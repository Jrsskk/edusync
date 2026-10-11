import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'data/api_client.dart';
import 'data/local_store.dart';
import 'data/sync_service.dart';
import 'models/grade.dart';
import 'platform/material_file_actions.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    required this.api,
    required this.store,
    required this.user,
    required this.onOpenTab,
    super.key,
  });
  final ApiClient api;
  final LocalStore store;
  final Map<String, dynamic> user;
  final ValueChanged<int> onOpenTab;
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Map<String, List<dynamic>> _data = {};
  bool _loading = true, _cached = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<List<dynamic>> _collection(String endpoint, String key) async {
    try {
      final result = await widget.api.get(endpoint);
      final data = result is List ? result : <dynamic>[];
      await widget.store.cache(key, data);
      return data;
    } on ApiException catch (error) {
      if (!error.isNetworkFailure) rethrow;
      final cached = await widget.store.readCache(key);
      if (cached is List) {
        _cached = true;
        return cached;
      }
      rethrow;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _cached = false;
    });
    try {
      final result = await Future.wait([
        _collection('/classes', 'classes'),
        _collection('/quizzes', 'quizzes'),
        _collection('/assignments', 'assignments'),
        _collection('/announcements', 'announcements'),
      ]);
      if (mounted) {
        setState(
          () => _data = {
            'classes': result[0],
            'quizzes': result[1],
            'assignments': result[2],
            'announcements': result[3],
          },
        );
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _load,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        _WelcomeCard(name: widget.user['name']?.toString() ?? 'Student'),
        if (_cached) const _OfflineBanner(),
        if (_error != null) _ErrorCard(message: _error!, onRetry: _load),
        const SizedBox(height: 22),
        _SectionTitle(
          title: 'Your learning at a glance',
          action: 'Refresh',
          onTap: _load,
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(36),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.class_rounded,
                  count: '${_data['classes']?.length ?? 0}',
                  label: 'Classes',
                  color: teal,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  icon: Icons.quiz_outlined,
                  count: '${_data['quizzes']?.length ?? 0}',
                  label: 'Quizzes',
                  color: const Color(0xFF7662C4),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  icon: Icons.assignment_outlined,
                  count: '${_data['assignments']?.length ?? 0}',
                  label: 'Tasks',
                  color: const Color(0xFFE18A37),
                ),
              ),
            ],
          ),
        const SizedBox(height: 24),
        const _SectionTitle(title: 'Quick access'),
        const SizedBox(height: 12),
        _QuickTile(
          icon: Icons.book_outlined,
          title: 'Classes and subjects',
          subtitle: 'See your enrolled classes',
          onTap: () => widget.onOpenTab(1),
        ),
        const SizedBox(height: 10),
        _QuickTile(
          icon: Icons.menu_book_outlined,
          title: 'Learning activities',
          subtitle: 'Quizzes, assignments and materials',
          onTap: () => widget.onOpenTab(2),
        ),
        const SizedBox(height: 10),
        _QuickTile(
          icon: Icons.campaign_outlined,
          title: 'Announcements',
          subtitle: '${_data['announcements']?.length ?? 0} recent updates',
          onTap: () => widget.onOpenTab(4),
        ),
        const SizedBox(height: 24),
        const _SectionTitle(title: 'Upcoming quizzes'),
        const SizedBox(height: 10),
        if (!_loading && (_data['quizzes']?.isEmpty ?? true))
          const _EmptyCard(message: 'No quizzes are available right now.')
        else
          ...(_data['quizzes'] ?? []).take(3).map((raw) {
            final item = Map<String, dynamic>.from(raw as Map);
            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _ResourceTile(
                title: item['title']?.toString() ?? 'Quiz',
                subtitle: _subjectAndDate(item),
                icon: Icons.quiz_outlined,
                onTap: () => widget.onOpenTab(2),
              ),
            );
          }),
      ],
    ),
  );
}

class ClassesPage extends StatefulWidget {
  const ClassesPage({required this.api, required this.store, super.key});
  final ApiClient api;
  final LocalStore store;
  @override
  State<ClassesPage> createState() => _ClassesPageState();
}

class _ClassesPageState extends State<ClassesPage> {
  List<dynamic> _classes = [];
  bool _loading = true, _cached = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _cached = false;
    });
    try {
      final result = await widget.api.get('/classes');
      _classes = result is List ? result : [];
      await widget.store.cache('classes', _classes);
    } on ApiException catch (error) {
      if (error.isNetworkFailure) {
        final cached = await widget.store.readCache('classes');
        if (cached is List) {
          _classes = cached;
          _cached = true;
        } else {
          _error = error.message;
        }
      } else {
        _error = error.message;
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _join() async {
    final code = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join a class'),
        content: TextField(
          controller: code,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Class code'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, code.text.trim()),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    if (value == null || value.isEmpty) return;
    try {
      await widget.api.post('/classes/join', {'class_code': value});
      await _load();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _load,
    child: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _SectionTitle(
          title: 'Subjects and classes',
          action: 'Join class',
          onTap: _join,
        ),
        const SizedBox(height: 8),
        Text(
          'Your subjects are organized through the classes you are enrolled in.',
          style: TextStyle(color: Colors.blueGrey.shade600),
        ),
        if (_cached) const _OfflineBanner(),
        if (_error != null) _ErrorCard(message: _error!, onRetry: _load),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_classes.isEmpty)
          const _EmptyCard(
            message:
                'No classes yet. Join a class using a code from your teacher.',
          )
        else
          ..._classes.map((raw) {
            final item = Map<String, dynamic>.from(raw as Map);
            final subject = item['subject'] is Map
                ? Map<String, dynamic>.from(item['subject'] as Map)
                : <String, dynamic>{};
            final teacher = item['teacher'] is Map
                ? Map<String, dynamic>.from(item['teacher'] as Map)
                : <String, dynamic>{};
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const _IconTile(
                          icon: Icons.menu_book_rounded,
                          color: teal,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            subject['name']?.toString() ??
                                item['name']?.toString() ??
                                'Class',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                              color: navy,
                            ),
                          ),
                        ),
                        if (subject['code'] != null)
                          _Pill(text: subject['code'].toString()),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '${item['name'] ?? 'Class'} ${item['section'] ?? ''}'
                          .trim(),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Grade ${item['grade_level'] ?? subject['grade_level'] ?? '—'} · ${teacher['name'] ?? 'Teacher not listed'}',
                      style: TextStyle(
                        color: Colors.blueGrey.shade600,
                        fontSize: 13,
                      ),
                    ),
                    if (item['schedule'] != null || item['room'] != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        [item['schedule'], item['room']]
                            .where(
                              (value) =>
                                  value != null && value.toString().isNotEmpty,
                            )
                            .join(' · '),
                        style: TextStyle(
                          color: Colors.blueGrey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
      ],
    ),
  );
}

class LearningPage extends StatefulWidget {
  const LearningPage({
    required this.api,
    required this.store,
    required this.sync,
    required this.onChanged,
    super.key,
  });
  final ApiClient api;
  final LocalStore store;
  final SyncService sync;
  final Future<void> Function() onChanged;
  @override
  State<LearningPage> createState() => _LearningPageState();
}

class _LearningPageState extends State<LearningPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this)
    ..addListener(() => setState(() {}));
  static const _keys = ['quizzes', 'assignments', 'materials'];
  static const _endpoints = ['/quizzes', '/assignments', '/materials'];
  List<List<dynamic>> _resources = [[], [], []];
  final Set<int> _offlineQuizIds = {};
  int? _openingMaterialId;
  int? _downloadingMaterialId;
  StreamSubscription<void>? _syncSubscription;
  bool _loading = true, _cached = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _syncSubscription = widget.sync.changes.listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_syncSubscription?.cancel());
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _cached = false;
    });
    final loaded = <List<dynamic>>[];
    try {
      for (var index = 0; index < _keys.length; index++) {
        try {
          final result = await widget.api.get(_endpoints[index]);
          final values = result is List ? result : <dynamic>[];
          await widget.store.cache(_keys[index], values);
          loaded.add(values);
        } on ApiException catch (error) {
          if (!error.isNetworkFailure) rethrow;
          final cached = await widget.store.readCache(_keys[index]);
          _cached = true;
          if (cached is List) {
            loaded.add(cached);
          } else if (_keys[index] == 'quizzes') {
            loaded.add([]);
          } else {
            rethrow;
          }
        }
      }
      final downloaded = await widget.store.offlineQuizzes();
      final completedIds = (await widget.store.quizAttemptQueueItems())
          .map((attempt) => int.tryParse(attempt['entity_id'].toString()))
          .whereType<int>()
          .toSet();
      final quizzes = <int, Map<String, dynamic>>{};
      for (final raw in loaded[0]) {
        if (raw is Map) {
          final quiz = Map<String, dynamic>.from(raw);
          final id = int.tryParse(quiz['id'].toString());
          if (id != null && !completedIds.contains(id)) quizzes[id] = quiz;
        }
      }
      _offlineQuizIds
        ..clear()
        ..addAll(
          downloaded
              .map(
                (data) => int.tryParse((data['quiz'] as Map)['id'].toString()),
              )
              .whereType<int>(),
        );
      for (final data in downloaded) {
        final quiz = Map<String, dynamic>.from(data['quiz'] as Map);
        final id = int.tryParse(quiz['id'].toString());
        if (id != null && !completedIds.contains(id)) quizzes[id] = quiz;
      }
      loaded[0] = quizzes.values.toList();
      if (mounted) setState(() => _resources = loaded);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not load saved quizzes: $error');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download(Map<String, dynamic> item, String type) async {
    final id = int.tryParse(item['id']?.toString() ?? '');
    if (id == null) return;
    final downloadViewer = type == 'materials' && kIsWeb
        ? prepareMaterialViewer()
        : null;
    if (type == 'materials' && mounted) {
      setState(() => _downloadingMaterialId = id);
    }
    try {
      final response = await widget.api.get('/$type/$id/download');
      if (type == 'quizzes') {
        if (response is! Map) {
          throw const FormatException('The quiz download response is invalid.');
        }
        final quizData = Map<String, dynamic>.from(response);
        quizData['offline_assets'] = await _downloadQuizAssets(quizData);
        await widget.store.saveOfflineQuiz(id, quizData);
        if (mounted) setState(() => _offlineQuizIds.add(id));
      } else if (type == 'assignments') {
        await widget.store.cache('download.$type.$id', response);
      }
      String? fileRoute;
      Map<String, dynamic> downloadItem = item;
      if (type == 'materials') {
        if (response is! Map) {
          throw const FormatException(
            'The material download response is invalid.',
          );
        }
        final material = response['material'] is Map
            ? Map<String, dynamic>.from(response['material'] as Map)
            : <String, dynamic>{};
        downloadItem = {...item, ...material};
        final urls = [
          response['download_url'],
          material['download_url'],
          response['file_url'],
          material['file_url'],
          item['download_url'],
          item['file_url'],
        ];
        for (final candidate in urls) {
          final value = candidate?.toString().trim() ?? '';
          if (value.isNotEmpty) {
            fileRoute = value;
            break;
          }
        }
        if (fileRoute == null) {
          throw const ApiException(
            'The server did not provide a download URL for this material.',
          );
        }
        fileRoute = _withDownloadFlag(fileRoute);
      }
      if (type == 'assignments' &&
          response is Map &&
          response['attachment_url'] != null) {
        fileRoute = '/assignments/$id/attachment';
      }
      if (fileRoute != null) {
        if (type == 'materials' && kIsWeb) {
          final started = await downloadMaterialUrl(
            url: fileRoute,
            viewer: downloadViewer,
          );
          if (!started) {
            throw const ApiException(
              'The browser blocked the download. Allow pop-ups and try again.',
            );
          }
        } else {
          final file = await widget.api.downloadResponse(fileRoute);
          final name = _downloadFileName(downloadItem, file, type);
          if (type == 'materials') {
            final savedPath = await saveMaterialFile(
              bytes: file.bodyBytes,
              fileName: name,
              mimeType: _materialMimeType(downloadItem, file, name),
            );
            if (savedPath != null) {
              await widget.store.saveFile('$type.$id', savedPath, name);
            }
          } else {
            final directory = await getApplicationDocumentsDirectory();
            final saved = File(p.join(directory.path, name));
            await saved.writeAsBytes(file.bodyBytes, flush: true);
            await widget.store.saveFile('$type.$id', saved.path, name);
          }
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              type == 'quizzes'
                  ? 'Quiz saved successfully. Choose Take Quiz Offline when ready.'
                  : type == 'materials'
                  ? 'Material downloaded to this device.'
                  : 'Saved for offline access on this device.',
            ),
          ),
        );
      }
    } on ApiException catch (error) {
      closeMaterialViewer(downloadViewer);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      closeMaterialViewer(downloadViewer);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save this download: $error')),
        );
      }
    } finally {
      if (type == 'materials' && mounted) {
        setState(() => _downloadingMaterialId = null);
      }
    }
  }

  Future<void> _takeOffline(Map<String, dynamic> item) async {
    final id = int.tryParse(item['id']?.toString() ?? '');
    if (id == null) return;
    try {
      final data = await widget.store.offlineQuiz(id);
      if (data == null) {
        throw StateError('Download this quiz before taking it offline.');
      }
      final quiz = Map<String, dynamic>.from(data['quiz'] as Map);
      quiz['questions'] = data['questions'];
      quiz['offline_assets'] = data['offline_assets'];
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _QuizPage(
            quiz: quiz,
            store: widget.store,
            sync: widget.sync,
            onChanged: _quizChanged,
          ),
        ),
      );
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the saved quiz: $error')),
        );
      }
    }
  }

  Future<Map<String, String>> _downloadQuizAssets(
    Map<String, dynamic> data,
  ) async {
    final paths = <String>{};
    final questions = data['questions'];
    if (questions is! List) {
      throw const FormatException('The quiz download has no question list.');
    }
    for (final rawQuestion in questions) {
      if (rawQuestion is! Map) continue;
      final questionImage = rawQuestion['image_path']?.toString();
      if (questionImage != null && questionImage.isNotEmpty) {
        paths.add(questionImage);
      }
      final options = rawQuestion['options'];
      if (options is List) {
        for (final rawOption in options) {
          if (rawOption is! Map) continue;
          final optionImage = rawOption['image_path']?.toString();
          if (optionImage != null && optionImage.isNotEmpty) {
            paths.add(optionImage);
          }
        }
      }
    }
    final assets = <String, String>{};
    for (final path in paths) {
      if (path.startsWith('data:image/')) {
        final separator = path.indexOf(',');
        if (separator < 0 ||
            !path.substring(0, separator).contains(';base64')) {
          throw const FormatException('The quiz contains an invalid image.');
        }
        assets[path] = path.substring(separator + 1);
      } else {
        final image = await widget.api.downloadQuizAsset(path);
        assets[path] = base64Encode(image.bodyBytes);
      }
    }
    return assets;
  }

  String _downloadFileName(
    Map<String, dynamic> item,
    http.Response response,
    String type,
  ) {
    final disposition = response.headers['content-disposition'] ?? '';
    final match = RegExp(r'filename="?([^";]+)').firstMatch(disposition);
    final preferredName = type == 'materials'
        ? item['original_file_name']?.toString()
        : item['attachment_file_name']?.toString();
    final sourceName = match?.group(1) ?? preferredName ?? '';
    final cleanName = p
        .basename(sourceName)
        .replaceAll(RegExp(r'[^\w.\- ]'), '_');
    if (cleanName.contains('.') && !cleanName.endsWith('.')) {
      return cleanName;
    }
    final remotePath =
        item['file_path']?.toString() ??
        item['attachment_path']?.toString() ??
        '';
    final pathExtension = p.extension(remotePath).replaceFirst('.', '');
    final contentType = (response.headers['content-type'] ?? '')
        .split(';')
        .first
        .trim()
        .toLowerCase();
    const mimeExtensions = {
      'application/pdf': 'pdf',
      'application/msword': 'doc',
      'application/vnd.ms-powerpoint': 'ppt',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
          'docx',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation':
          'pptx',
      'image/jpeg': 'jpg',
      'image/png': 'png',
      'image/gif': 'gif',
      'image/bmp': 'bmp',
      'image/avif': 'avif',
      'image/svg+xml': 'svg',
      'image/webp': 'webp',
      'video/mp4': 'mp4',
      'video/x-m4v': 'm4v',
      'video/quicktime': 'mov',
      'video/ogg': 'ogv',
      'video/webm': 'webm',
    };
    final materialMime = item['file_type']?.toString().trim().toLowerCase();
    final materialExtension = materialMime == null
        ? null
        : mimeExtensions[materialMime];
    final extension = pathExtension.isNotEmpty
        ? pathExtension
        : mimeExtensions[contentType] ?? materialExtension ?? 'bin';
    final base =
        (sourceName.isNotEmpty
                ? p.basenameWithoutExtension(sourceName)
                : item['title']?.toString() ?? 'learning-file')
            .replaceAll(RegExp(r'[^\w\- ]'), '_');
    return '$base-${DateTime.now().millisecondsSinceEpoch}.$extension';
  }

  String _withDownloadFlag(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    if (uri.queryParameters['download'] == '1') return url;
    return uri
        .replace(queryParameters: {...uri.queryParameters, 'download': '1'})
        .toString();
  }

  String? _materialMimeType(
    Map<String, dynamic> material,
    http.Response? response,
    String fileName,
  ) {
    final headerMime = response?.headers['content-type']
        ?.split(';')
        .first
        .trim()
        .toLowerCase();
    if (headerMime != null &&
        headerMime.isNotEmpty &&
        headerMime != 'application/octet-stream') {
      return headerMime;
    }
    final apiMime = material['file_type']?.toString().trim().toLowerCase();
    if (apiMime != null &&
        apiMime.isNotEmpty &&
        apiMime != 'application/octet-stream') {
      return apiMime;
    }
    const extensionMimes = {
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'bmp': 'image/bmp',
      'webp': 'image/webp',
      'avif': 'image/avif',
      'mp4': 'video/mp4',
      'm4v': 'video/x-m4v',
      'mov': 'video/quicktime',
      'webm': 'video/webm',
      'ogv': 'video/ogg',
    };
    return extensionMimes[p
        .extension(fileName)
        .replaceFirst('.', '')
        .toLowerCase()];
  }

  Future<void> _openSavedFile(String path, {String? mimeType}) async {
    try {
      final opened = await openMaterialFile(path: path, mimeType: mimeType);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No compatible app is installed to open this file. You can still download it.',
            ),
          ),
        );
      }
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open this file: $error')),
        );
      }
    }
  }

  Future<void> _openMaterial(Map<String, dynamic> item) async {
    final id = int.tryParse(item['id']?.toString() ?? '');
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This material has an invalid ID.')),
      );
      return;
    }
    final viewer = prepareMaterialViewer();
    setState(() => _openingMaterialId = id);
    try {
      final savedFile = await widget.store.fileFor('materials.$id');
      final savedPath = savedFile?['file_path']?.toString();
      final cachedFile = !kIsWeb && savedPath != null ? File(savedPath) : null;
      if (cachedFile != null && await cachedFile.exists()) {
        await _openSavedFile(
          cachedFile.path,
          mimeType: _materialMimeType(item, null, cachedFile.path),
        );
        return;
      }

      var material = item;
      final access = await widget.api.get('/materials/$id/download');
      final accessData = access is Map
          ? Map<String, dynamic>.from(access)
          : <String, dynamic>{};
      if (accessData['material'] is Map) {
        material = {
          ...item,
          ...Map<String, dynamic>.from(accessData['material'] as Map),
        };
      }
      final fileUrl =
          material['file_url']?.toString().trim() ??
          accessData['file_url']?.toString().trim() ??
          item['file_url']?.toString().trim() ??
          accessData['view_url']?.toString().trim() ??
          '';
      if (fileUrl.isEmpty) {
        throw const ApiException(
          'The server did not provide a file URL. You can still use Download if the file is available.',
        );
      }

      final response = await widget.api.downloadResponse(fileUrl);
      final name = _downloadFileName(material, response, 'materials');
      final opened = await openMaterialBytes(
        bytes: response.bodyBytes,
        fileName: name,
        mimeType: _materialMimeType(material, response, name),
        viewer: viewer,
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No compatible app or viewer could open this file. Download is still available.',
            ),
          ),
        );
      }
    } on ApiException catch (error) {
      closeMaterialViewer(viewer);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not open this material: ${error.message} Download is still available.',
            ),
          ),
        );
      }
    } on Exception catch (error) {
      closeMaterialViewer(viewer);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not open this material: $error Download is still available.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _openingMaterialId = null);
    }
  }

  Future<Map<String, dynamic>?> _details(
    Map<String, dynamic> item,
    String type,
  ) async {
    final id = item['id'];
    try {
      final result = await widget.api.get('/$type/$id');
      await widget.store.cache('detail.$type.$id', result);
      return result is Map ? Map<String, dynamic>.from(result) : item;
    } on ApiException catch (error) {
      if (!error.isNetworkFailure) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error.message)));
        }
        return null;
      }
      if (type == 'quizzes') {
        final quizId = int.tryParse(id?.toString() ?? '');
        if (quizId != null) {
          final saved = await widget.store.offlineQuiz(quizId);
          if (saved != null) return saved;
        }
      }
      final downloaded = await widget.store.readCache('download.$type.$id');
      if (downloaded is Map) return Map<String, dynamic>.from(downloaded);
      final cached = await widget.store.readCache('detail.$type.$id');
      if (cached is Map) return Map<String, dynamic>.from(cached);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Connect to the internet or download this item first.',
            ),
          ),
        );
      }
      return null;
    }
  }

  Future<void> _open(Map<String, dynamic> item, String type) async {
    if (type == 'materials') {
      await _openMaterial(item);
      return;
    }
    final data = await _details(item, type);
    if (!mounted || data == null) return;
    if (type == 'quizzes') {
      final quiz = data['quiz'] is Map
          ? Map<String, dynamic>.from(data['quiz'] as Map)
          : data;
      quiz['questions'] = data['questions'] ?? quiz['questions'];
      if (quiz['questions'] is! List) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Download this quiz online before opening it offline.',
            ),
          ),
        );
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _QuizPage(
            quiz: quiz,
            store: widget.store,
            sync: widget.sync,
            onChanged: _quizChanged,
          ),
        ),
      );
    } else if (type == 'assignments') {
      final assignment = data['assignment'] is Map
          ? Map<String, dynamic>.from(data['assignment'] as Map)
          : data;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _AssignmentPage(
            assignment: assignment,
            store: widget.store,
            sync: widget.sync,
            onChanged: widget.onChanged,
          ),
        ),
      );
    }
  }

  Future<void> _quizChanged() async {
    await _load();
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (_cached) const _OfflineBanner(),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: TabBar(
            controller: _tabs,
            labelColor: navy,
            unselectedLabelColor: Colors.blueGrey,
            indicator: BoxDecoration(
              color: const Color(0xFFE8F3F2),
              borderRadius: BorderRadius.circular(11),
            ),
            tabs: const [
              Tab(text: 'Quizzes'),
              Tab(text: 'Assignments'),
              Tab(text: 'Materials'),
            ],
          ),
        ),
      ),
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      if (_error != null) _ErrorCard(message: _error!, onRetry: _load),
      Expanded(
        child: RefreshIndicator(onRefresh: _load, child: _resourceList()),
      ),
    ],
  );

  Widget _resourceList() {
    final index = _tabs.index;
    final type = _keys[index];
    final items = index < _resources.length ? _resources[index] : <dynamic>[];
    if (!_loading && items.isEmpty) {
      return ListView(
        children: [
          SizedBox(
            height: 260,
            child: Center(
              child: _EmptyCard(
                message: _error ?? 'Nothing here yet. Pull down to refresh.',
              ),
            ),
          ),
        ],
      );
    }
    if (type != 'materials') {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 26),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = Map<String, dynamic>.from(items[index] as Map);
          return Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: _LearningCard(
              item: item,
              type: type,
              isAvailableOffline:
                  type == 'quizzes' &&
                  _offlineQuizIds.contains(
                    int.tryParse(item['id']?.toString() ?? ''),
                  ),
              isOpening:
                  type == 'materials' &&
                  _openingMaterialId ==
                      int.tryParse(item['id']?.toString() ?? ''),
              isDownloading:
                  type == 'materials' &&
                  _downloadingMaterialId ==
                      int.tryParse(item['id']?.toString() ?? ''),
              onOpen: () => _open(item, type),
              onDownload: () => _download(item, type),
              onTakeOffline: () => _takeOffline(item),
            ),
          );
        },
      );
    }
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final raw in items) {
      final item = Map<String, dynamic>.from(raw as Map);
      final subject = item['subject'] is Map
          ? (item['subject'] as Map)['name']?.toString() ?? 'Other materials'
          : 'Other materials';
      groups.putIfAbsent(subject, () => []).add(item);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 26),
      children: [
        for (final group in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
            child: _SectionTitle(title: group.key),
          ),
          ...group.value.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _LearningCard(
                item: item,
                type: type,
                isAvailableOffline: false,
                isOpening:
                    _openingMaterialId ==
                    int.tryParse(item['id']?.toString() ?? ''),
                isDownloading:
                    _downloadingMaterialId ==
                    int.tryParse(item['id']?.toString() ?? ''),
                onOpen: () => _open(item, type),
                onDownload: () => _download(item, type),
                onTakeOffline: () {},
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _LearningCard extends StatelessWidget {
  const _LearningCard({
    required this.item,
    required this.type,
    required this.isAvailableOffline,
    required this.isOpening,
    required this.isDownloading,
    required this.onOpen,
    required this.onDownload,
    required this.onTakeOffline,
  });
  final Map<String, dynamic> item;
  final String type;
  final bool isAvailableOffline;
  final bool isOpening, isDownloading;
  final VoidCallback onOpen, onDownload;
  final VoidCallback onTakeOffline;
  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (type) {
      'quizzes' => (Icons.quiz_outlined, const Color(0xFF7662C4)),
      'assignments' => (Icons.assignment_outlined, const Color(0xFFE18A37)),
      _ => (Icons.description_outlined, teal),
    };
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onOpen,
            child: Row(
              children: [
                _IconTile(icon: icon, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['title']?.toString() ?? 'Learning item',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: navy,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _subjectAndDate(item),
                        style: TextStyle(
                          color: Colors.blueGrey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.blueGrey),
              ],
            ),
          ),
          if (item['instructions'] != null || item['description'] != null) ...[
            const SizedBox(height: 10),
            Text(
              (item['instructions'] ?? item['description']).toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 13),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: isOpening ? null : onOpen,
                  icon: isOpening
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.open_in_new, size: 17),
                  label: Text(isOpening ? 'Opening...' : 'Open'),
                ),
              ),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isDownloading
                      ? null
                      : isAvailableOffline
                      ? onTakeOffline
                      : onDownload,
                  icon: isDownloading
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          isAvailableOffline
                              ? Icons.offline_pin_outlined
                              : Icons.download_outlined,
                          size: 17,
                        ),
                  label: Text(
                    isDownloading
                        ? 'Downloading...'
                        : type == 'materials'
                        ? 'Download'
                        : isAvailableOffline
                        ? 'Take Quiz Offline'
                        : 'Download Offline',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuizPage extends StatefulWidget {
  const _QuizPage({
    required this.quiz,
    required this.store,
    required this.sync,
    required this.onChanged,
  });
  final Map<String, dynamic> quiz;
  final LocalStore store;
  final SyncService sync;
  final Future<void> Function() onChanged;
  @override
  State<_QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<_QuizPage> {
  final Map<String, dynamic> _answers = {};
  final Map<String, TextEditingController> _controllers = {};
  late final int _quizId = int.parse(widget.quiz['id'].toString());
  late final String _draftKey = 'draft.quiz.$_quizId';
  late DateTime _startedAt = DateTime.now().toUtc();
  bool _restored = false, _saving = false;
  List<dynamic> get _questions => widget.quiz['questions'] as List? ?? [];

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    final cached = await widget.store.readCache(_draftKey);
    if (cached is Map) {
      final answers = cached['answers'];
      if (answers is Map) _answers.addAll(Map<String, dynamic>.from(answers));
      final start = DateTime.tryParse(cached['started_at']?.toString() ?? '');
      if (start != null) _startedAt = start;
    }
    for (final raw in _questions) {
      final question = Map<String, dynamic>.from(raw as Map);
      final type = question['type']?.toString() ?? '';
      if (!_choiceType(type) &&
          type != 'matching' &&
          type != 'sequencing' &&
          type != 'drag_drop') {
        final id = '${question['id']}';
        _controllers[id] = TextEditingController(
          text: _answers[id]?.toString() ?? '',
        );
      }
    }
    if (mounted) setState(() => _restored = true);
  }

  bool _choiceType(String type) => const {
    'multiple_choice',
    'true_false',
    'image_based',
    'multiple_selection',
  }.contains(type);

  Future<void> _saveDraft() => widget.store.cache(_draftKey, {
    'answers': _answers,
    'started_at': _startedAt.toIso8601String(),
  });

  void _select(String question, int option, bool multiple) {
    if (multiple) {
      final selected = (_answers[question] as List? ?? [])
          .map((value) => value as int)
          .toSet();
      selected.contains(option)
          ? selected.remove(option)
          : selected.add(option);
      _answers[question] = selected.toList();
    } else {
      _answers[question] = [option];
    }
    setState(() {});
    unawaited(_saveDraft());
  }

  Widget _quizImage(dynamic value) {
    final path = value?.toString() ?? '';
    if (path.isEmpty) return const SizedBox.shrink();
    final assets = widget.quiz['offline_assets'];
    final encoded = assets is Map ? assets[path]?.toString() : null;
    final image = encoded == null
        ? Image.network(
            path,
            height: 180,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
          )
        : Image.memory(
            base64Decode(encoded),
            height: 180,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: image,
    );
  }

  List<Widget> _matchingFields(
    String questionKey,
    List<Map<String, dynamic>> choices,
  ) {
    final left = choices.where((option) => option['side'] == 'left').toList();
    final right = choices.where((option) => option['side'] == 'right').toList();
    final selections = Map<String, dynamic>.from(
      _answers[questionKey] as Map? ?? const {},
    );
    return left.map((option) {
      final leftId = '${option['id']}';
      final selected = int.tryParse(selections[leftId]?.toString() ?? '');
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: DropdownButtonFormField<int>(
          initialValue: right.any((candidate) => candidate['id'] == selected)
              ? selected
              : null,
          decoration: InputDecoration(
            labelText: option['option_text']?.toString() ?? 'Match',
          ),
          items: right
              .map(
                (candidate) => DropdownMenuItem<int>(
                  value: candidate['id'] as int,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _quizImage(candidate['image_path']),
                      Text(candidate['option_text']?.toString() ?? ''),
                    ],
                  ),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) {
              selections[leftId] = value;
              _answers[questionKey] = selections;
              unawaited(_saveDraft());
            }
          },
        ),
      );
    }).toList();
  }

  Widget _sequenceField(
    String questionKey,
    List<Map<String, dynamic>> choices,
  ) {
    final order = (_answers[questionKey] as List? ?? [])
        .map((value) => value as int)
        .toList();
    if (order.isEmpty) {
      order.addAll(choices.map((choice) => choice['id'] as int));
      _answers[questionKey] = order;
    }
    final options = {for (final choice in choices) choice['id'] as int: choice};
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: order.length,
      onReorderItem: (oldIndex, newIndex) {
        final moved = order.removeAt(oldIndex);
        order.insert(newIndex, moved);
        _answers[questionKey] = order;
        unawaited(_saveDraft());
        setState(() {});
      },
      itemBuilder: (context, index) {
        final option = options[order[index]];
        return ListTile(
          key: ValueKey(order[index]),
          leading: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.drag_handle_rounded),
              _quizImage(option?['image_path']),
            ],
          ),
          title: Text(option?['option_text']?.toString() ?? ''),
          contentPadding: EdgeInsets.zero,
        );
      },
    );
  }

  Future<void> _submit() async {
    final answers = _questions.map((raw) {
      final question = Map<String, dynamic>.from(raw as Map);
      final id = '${question['id']}';
      final type = question['type']?.toString() ?? '';
      if (type == 'matching') {
        return {
          'question_id': question['id'],
          'selected_options': _answers[id] ?? <String, int>{},
        };
      }
      if (type == 'sequencing' || type == 'drag_drop') {
        return {
          'question_id': question['id'],
          'selected_options': _answers[id] ?? <int>[],
        };
      }
      if (_choiceType(type)) {
        return {
          'question_id': question['id'],
          'selected_options': _answers[id] ?? <int>[],
        };
      }
      return {
        'question_id': question['id'],
        'answer_text': _controllers[id]?.text.trim() ?? '',
      };
    }).toList();
    setState(() => _saving = true);
    try {
      final submitted = DateTime.now().toUtc().toIso8601String();
      final queued = await widget.sync.queue(
        entityType: 'quiz_attempt',
        entityId: _quizId,
        payload: {
          'quiz_id': _quizId,
          'attempt_number': 1,
          'started_at': _startedAt.toIso8601String(),
          'completed_at': submitted,
          'submitted_at': submitted,
          'answers': answers,
        },
      );
      if (!queued) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'A submission for this quiz is already in your sync queue.',
              ),
            ),
          );
        }
        return;
      }
      await widget.store.removeCache(_draftKey);
      await widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Quiz saved to your sync queue.')),
        );
        Navigator.pop(context);
      }
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save quiz: $error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.quiz['title']?.toString() ?? 'Quiz')),
    body: !_restored
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.quiz['instructions']?.toString() ??
                          'Answer each question below.',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_questions.length} questions · ${widget.quiz['total_points'] ?? '—'} points',
                      style: TextStyle(color: Colors.blueGrey.shade600),
                    ),
                    const SizedBox(height: 8),
                    const _OfflineBanner(compact: true),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              ..._questions.asMap().entries.map((entry) {
                final question = Map<String, dynamic>.from(entry.value as Map);
                final key = '${question['id']}';
                final type = question['type']?.toString() ?? '';
                final choices = (question['options'] as List? ?? [])
                    .map((option) => Map<String, dynamic>.from(option as Map))
                    .toList();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'QUESTION ${entry.key + 1} · ${question['points'] ?? 1} pts',
                          style: const TextStyle(
                            color: teal,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          question['question_text']?.toString() ?? '',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                        _quizImage(question['image_path']),
                        if (type == 'multiple_selection')
                          ...choices.map((choice) {
                            final optionId = choice['id'] as int;
                            final selected = (_answers[key] as List? ?? [])
                                .contains(optionId);
                            return CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _quizImage(choice['image_path']),
                                  Text(
                                    choice['option_text']?.toString() ??
                                        'Choice',
                                  ),
                                ],
                              ),
                              value: selected,
                              onChanged: (_) => _select(key, optionId, true),
                            );
                          })
                        else if (_choiceType(type))
                          RadioGroup<int>(
                            groupValue: (_answers[key] as List? ?? []).isEmpty
                                ? null
                                : (_answers[key] as List).first as int,
                            onChanged: (value) {
                              if (value != null) {
                                _select(key, value, false);
                              }
                            },
                            child: Column(
                              children: choices
                                  .map(
                                    (choice) => RadioListTile<int>(
                                      contentPadding: EdgeInsets.zero,
                                      title: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _quizImage(choice['image_path']),
                                          Text(
                                            choice['option_text']?.toString() ??
                                                'Choice',
                                          ),
                                        ],
                                      ),
                                      value: choice['id'] as int,
                                    ),
                                  )
                                  .toList(),
                            ),
                          )
                        else if (type == 'matching') ...[
                          const SizedBox(height: 12),
                          ..._matchingFields(key, choices),
                        ] else if (type == 'sequencing' ||
                            type == 'drag_drop') ...[
                          const SizedBox(height: 12),
                          _sequenceField(key, choices),
                        ] else ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _controllers[key],
                            minLines: type == 'identification' ? 1 : 3,
                            maxLines: 5,
                            onChanged: (value) {
                              _answers[key] = value;
                              unawaited(_saveDraft());
                            },
                            decoration: InputDecoration(
                              labelText: type == 'identification'
                                  ? 'Your answer'
                                  : 'Your response',
                              alignLabelWithHint: true,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded),
                label: const Text('Submit quiz'),
              ),
              const SizedBox(height: 10),
              const Text(
                'Answers are saved on this device and synchronize when online.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.blueGrey, fontSize: 12),
              ),
            ],
          ),
  );
}

class _AssignmentPage extends StatefulWidget {
  const _AssignmentPage({
    required this.assignment,
    required this.store,
    required this.sync,
    required this.onChanged,
  });
  final Map<String, dynamic> assignment;
  final LocalStore store;
  final SyncService sync;
  final Future<void> Function() onChanged;
  @override
  State<_AssignmentPage> createState() => _AssignmentPageState();
}

class _AssignmentPageState extends State<_AssignmentPage> {
  late final TextEditingController _response = TextEditingController();
  Map<String, Object?>? _savedAttachment;
  bool _loading = true, _saving = false;
  int get _id => widget.assignment['id'] as int;
  String get _draftKey => 'draft.assignment.$_id';

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    final cached = await widget.store.readCache(_draftKey);
    if (cached is Map) {
      _response.text = cached['text_response']?.toString() ?? '';
    }
    _savedAttachment = await widget.store.fileFor('assignments.$_id');
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openAttachment() async {
    final path = _savedAttachment?['file_path'] as String?;
    if (path == null) return;
    try {
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.message)));
      }
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the downloaded file: $error')),
        );
      }
    }
  }

  Future<void> _saveDraft(String value) =>
      widget.store.cache(_draftKey, {'text_response': value});

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      final queued = await widget.sync.queue(
        entityType: 'assignment_submission',
        entityId: _id,
        payload: {
          'assignment_id': _id,
          'text_response': _response.text.trim(),
          'file_path': null,
          'status': 'submitted',
          'version': 1,
          'submitted_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
      if (!queued) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'A submission for this assignment is already in your sync queue.',
              ),
            ),
          );
        }
        return;
      }
      await widget.store.removeCache(_draftKey);
      await widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Assignment saved to your sync queue.')),
        );
        Navigator.pop(context);
      }
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save assignment: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _response.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.assignment['title']?.toString() ?? 'Assignment'),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(18),
            children: [
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.assignment['description']?.toString() ??
                          'No description provided.',
                    ),
                    if (widget.assignment['instructions'] != null) ...[
                      const SizedBox(height: 14),
                      const Text(
                        'Instructions',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: navy,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(widget.assignment['instructions'].toString()),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      'Due ${_formatDate(widget.assignment['deadline'] ?? widget.assignment['due_at'])}',
                      style: const TextStyle(
                        color: teal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (_savedAttachment != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _openAttachment,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text(
                    'Open offline attachment: ${_savedAttachment!['file_name']}',
                  ),
                ),
              ],
              const SizedBox(height: 14),
              const _OfflineBanner(compact: true),
              const SizedBox(height: 12),
              TextField(
                controller: _response,
                minLines: 7,
                maxLines: 12,
                onChanged: (value) => unawaited(_saveDraft(value)),
                decoration: const InputDecoration(
                  labelText: 'Your submission',
                  hintText: 'Write your response here…',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded),
                label: const Text('Submit assignment'),
              ),
              const SizedBox(height: 10),
              const Text(
                'Your draft is saved locally as you type. File uploads require an internet connection.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.blueGrey, fontSize: 12),
              ),
            ],
          ),
  );
}

class GradesPage extends StatefulWidget {
  const GradesPage({
    required this.api,
    required this.store,
    required this.sync,
    super.key,
  });
  final ApiClient api;
  final LocalStore store;
  final SyncService sync;
  @override
  State<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends State<GradesPage> {
  List<Grade> _grades = [];
  bool _loading = true, _cached = false;
  String? _error;
  StreamSubscription<void>? _syncSubscription;
  @override
  void initState() {
    super.initState();
    _syncSubscription = widget.sync.changes.listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_syncSubscription?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _cached = false;
    });
    var serverGrades = <Grade>[];
    var usingCache = false;
    String? loadError;
    try {
      final result = await widget.api.get('/grades');
      if (result is! List) {
        throw const FormatException(
          'The grades endpoint returned an unexpected response.',
        );
      }
      serverGrades = result.map(Grade.fromJson).toList();
      await widget.store.cache(
        'grades',
        serverGrades.map((grade) => grade.toJson()).toList(),
      );
    } on ApiException catch (error) {
      if (error.isNetworkFailure) {
        try {
          final cached = await widget.store.readCache('grades');
          if (cached is List) {
            serverGrades = cached.map(Grade.fromJson).toList();
            usingCache = true;
          } else {
            loadError = error.message;
          }
        } on Exception catch (cacheError) {
          loadError = 'Could not load cached grades: $cacheError';
        }
      } else {
        loadError = error.message;
      }
    } on Exception catch (error) {
      loadError = 'Could not load grades: $error';
    }
    try {
      final quizData = <int, Map<String, dynamic>>{};
      for (final data in await widget.store.offlineQuizzes()) {
        final quiz = Map<String, dynamic>.from(data['quiz'] as Map);
        final id = int.tryParse(quiz['id'].toString());
        if (id != null) quizData[id] = quiz;
      }
      final localGrades = <Grade>[];
      for (final attempt in await widget.store.quizAttemptQueueItems()) {
        final payload = jsonDecode(attempt['payload']! as String) as Map;
        final quizId = int.tryParse(
          payload['quiz_id']?.toString() ??
              attempt['entity_id']?.toString() ??
              '',
        );
        var quiz = quizId == null ? null : quizData[quizId];
        if (quiz == null && quizId != null) {
          final detail = await widget.store.readCache('detail.quizzes.$quizId');
          if (detail is Map) {
            final savedQuiz = detail['quiz'];
            if (savedQuiz is Map) {
              quiz = Map<String, dynamic>.from(savedQuiz);
            }
          }
        }
        final classData = quiz?['school_class'] ?? quiz?['schoolClass'];
        final className = classData is Map
            ? classData['display_name']?.toString() ??
                  classData['name']?.toString()
            : null;
        final subjectData =
            quiz?['subject'] ??
            (classData is Map ? classData['subject'] : null);
        final subjectName = subjectData is Map
            ? subjectData['name']?.toString()
            : subjectData?.toString();
        final title = quiz?['title']?.toString() ?? 'Quiz #$quizId';
        final classValue = className ?? 'Class not listed';
        final syncUuid = attempt['sync_uuid']! as String;
        final alreadyGraded = serverGrades.any(
          (grade) =>
              grade.type == 'quiz' &&
              (grade.syncUuid == syncUuid ||
                  (grade.syncUuid == null &&
                      grade.title == title &&
                      grade.className == classValue)),
        );
        if (alreadyGraded) continue;
        localGrades.add(
          Grade.fromJson({
            'type': 'quiz',
            'local_attempt': true,
            'id': syncUuid,
            'sync_uuid': syncUuid,
            'quiz_id': quizId,
            'title': title,
            'subject': subjectName,
            'class': classValue,
            'graded_at': payload['submitted_at'] ?? payload['completed_at'],
            'sync_state': attempt['state'],
          }),
        );
      }
      if (mounted) {
        setState(() {
          _grades = [...localGrades, ...serverGrades];
          _cached = usingCache;
          _error = loadError;
          _loading = false;
        });
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _grades = serverGrades;
          _cached = usingCache;
          _error =
              loadError ?? 'Could not load locally completed quizzes: $error';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _load,
    child: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const _SectionTitle(title: 'Quiz and assignment grades'),
        if (_cached) const _OfflineBanner(),
        if (_error != null) _ErrorCard(message: _error!, onRetry: _load),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(42),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_grades.isEmpty && _error == null)
          const _EmptyCard(
            message: 'No grades yet. Graded quizzes and assignments will appear here.',
          )
        else if (_grades.isNotEmpty)
          ..._groupedGrades.entries.expand((entry) {
            final separator = entry.key.indexOf('\u0000');
            final subject = entry.key.substring(0, separator);
            final className = entry.key.substring(separator + 1);
            return [
              Padding(
                padding: const EdgeInsets.only(top: 18, bottom: 2),
                child: Text(
                  '$subject · $className',
                  style: const TextStyle(
                    color: navy,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ...entry.value.map(_gradeCard),
            ];
          }),
      ],
    ),
  );

  Map<String, List<Grade>> get _groupedGrades {
    final groups = <String, List<Grade>>{};
    for (final grade in _grades) {
      final key =
          '${grade.subject ?? 'Subject not listed'}\u0000${grade.className ?? 'Class not listed'}';
      groups.putIfAbsent(key, () => []).add(grade);
    }
    return groups;
  }

  Widget _gradeCard(Grade grade) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconTile(
                icon: grade.type == 'quiz'
                    ? Icons.quiz_outlined
                    : Icons.assignment_turned_in_outlined,
                color: teal,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      grade.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: navy,
                      ),
                    ),
                    Text(
                      '${grade.type == 'quiz' ? 'Quiz' : 'Assignment'} · ${_formatDate(grade.gradedAt?.toIso8601String())}',
                      style: TextStyle(
                        color: Colors.blueGrey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (grade.localAttempt)
                Text(
                  grade.syncState == 'success' ? 'Submitted' : 'Completed',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: teal,
                  ),
                )
              else
                Text(
                  '${_formatGradeNumber(grade.score)}${grade.maxScore == null ? '' : ' / ${_formatGradeNumber(grade.maxScore)}'}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: teal,
                  ),
                ),
            ],
          ),
          if (grade.localAttempt) ...[
            const Divider(height: 24),
            Text(
              grade.syncState == 'success'
                  ? 'Synchronized · awaiting grade'
                  : 'Saved on this device · awaiting synchronization',
              style: TextStyle(color: Colors.blueGrey.shade700),
            ),
          ] else if (grade.percentage != null) ...[
            const SizedBox(height: 8),
            Text(
              '${grade.percentage!.toStringAsFixed(1)}%',
              style: TextStyle(color: Colors.blueGrey.shade700),
            ),
          ],
          if (grade.feedback != null && grade.feedback!.isNotEmpty) ...[
            const Divider(height: 24),
            const Text(
              'Teacher feedback',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(grade.feedback!),
          ],
        ],
      ),
    ),
  );

  String _formatGradeNumber(double? value) {
    if (value == null) return '—';
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }
}

class UpdatesPage extends StatefulWidget {
  const UpdatesPage({required this.api, required this.store, super.key});
  final ApiClient api;
  final LocalStore store;
  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  List<dynamic> _announcements = [], _notifications = [];
  bool _loading = true, _cached = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _tabs.addListener(() => setState(() {}));
    unawaited(_load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _fetch(
    String endpoint,
    String key,
    void Function(List<dynamic>) assign,
  ) async {
    try {
      final result = await widget.api.get(endpoint);
      final list = result is List ? result : <dynamic>[];
      assign(list);
      await widget.store.cache(key, list);
    } on ApiException catch (error) {
      if (!error.isNetworkFailure) rethrow;
      final cached = await widget.store.readCache(key);
      if (cached is List) {
        assign(cached);
        _cached = true;
      } else {
        rethrow;
      }
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _cached = false;
    });
    try {
      await _fetch(
        '/announcements',
        'announcements',
        (value) => _announcements = value,
      );
      await _fetch(
        '/notifications',
        'notifications',
        (value) => _notifications = value,
      );
    } on ApiException catch (error) {
      _error = error.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _readAll() async {
    try {
      await widget.api.post('/notifications/read-all', {});
      await _load();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _announcement(Map<String, dynamic> item) async {
    final id = item['id'];
    var detail = item;
    try {
      final result = await widget.api.get('/announcements/$id');
      if (result is Map) detail = Map<String, dynamic>.from(result);
      await widget.store.cache('announcement.$id', detail);
    } on ApiException catch (error) {
      if (!error.isNetworkFailure) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error.message)));
        }
        return;
      }
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(detail['title']?.toString() ?? 'Announcement'),
        content: SingleChildScrollView(
          child: Text(
            detail['content']?.toString() ?? detail['body']?.toString() ?? '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: TabBar(
                controller: _tabs,
                tabs: const [
                  Tab(text: 'Announcements'),
                  Tab(text: 'Notifications'),
                ],
              ),
            ),
            if (_tabs.index == 1)
              TextButton(onPressed: _readAll, child: const Text('Read all')),
          ],
        ),
      ),
      if (_cached) const _OfflineBanner(compact: true),
      if (_error != null) _ErrorCard(message: _error!, onRetry: _load),
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: TabBarView(
          controller: _tabs,
          children: [
            _UpdatesList(
              items: _announcements,
              loading: _loading,
              empty: 'No announcements have been published.',
              icon: Icons.campaign_outlined,
              title: (item) => item['title']?.toString() ?? 'Announcement',
              subtitle: (item) =>
                  '${(item['author'] as Map?)?['name'] ?? 'EduSync'} · ${_formatDate(item['published_at'])}',
              onTap: _announcement,
            ),
            _UpdatesList(
              items: _notifications,
              loading: _loading,
              empty: 'You’re all caught up. New notifications will show here.',
              icon: Icons.notifications_none,
              title: (item) {
                final data = item['data'] as Map? ?? const {};
                return data['title']?.toString() ??
                    data['message']?.toString() ??
                    item['type']?.toString() ??
                    'Notification';
              },
              subtitle: (item) => _formatDate(item['created_at']),
              onTap: (item) async {
                final id = item['id'];
                if (id != null && item['read_at'] == null) {
                  try {
                    await widget.api.post('/notifications/$id/read', {});
                    await _load();
                  } on ApiException catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(error.message)));
                    }
                  }
                }
              },
            ),
          ],
        ),
      ),
    ],
  );
}

class _UpdatesList extends StatelessWidget {
  const _UpdatesList({
    required this.items,
    required this.loading,
    required this.empty,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final List<dynamic> items;
  final bool loading;
  final String empty;
  final IconData icon;
  final String Function(Map<String, dynamic>) title, subtitle;
  final Future<void> Function(Map<String, dynamic>) onTap;
  @override
  Widget build(BuildContext context) {
    if (loading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _EmptyCard(message: empty),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 22),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = Map<String, dynamic>.from(items[index] as Map);
        return _Card(
          child: InkWell(
            onTap: () => unawaited(onTap(item)),
            child: Row(
              children: [
                _IconTile(icon: icon, color: teal),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title(item),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: navy,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle(item),
                        style: TextStyle(
                          color: Colors.blueGrey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (item['read_at'] == null && item.containsKey('read_at'))
                  const CircleAvatar(radius: 4, backgroundColor: teal),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [navy, Color(0xFF1D5260)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'YOUR STUDENT SPACE',
                style: TextStyle(
                  color: Color(0xFFA6DAD2),
                  letterSpacing: 1.1,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                'Hello, ${name.split(' ').first}!',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Keep moving forward, one lesson at a time.',
                style: TextStyle(color: Colors.white70, height: 1.35),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        const Icon(
          Icons.auto_stories_rounded,
          size: 46,
          color: Color(0xFFB1E6DD),
        ),
      ],
    ),
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.count,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String count, label;
  final Color color;
  @override
  Widget build(BuildContext context) => _Card(
    padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(height: 12),
        Text(
          count,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: navy,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
        ),
      ],
    ),
  );
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => _Card(
    child: InkWell(
      onTap: onTap,
      child: Row(
        children: [
          _IconTile(icon: icon, color: teal),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: navy,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.blueGrey.shade600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward_ios_rounded,
            size: 15,
            color: Colors.blueGrey,
          ),
        ],
      ),
    ),
  );
}

class _ResourceTile extends StatelessWidget {
  const _ResourceTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
  final String title, subtitle;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => _Card(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    child: InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: teal),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.blueGrey.shade600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.action, this.onTap});
  final String title;
  final String? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: navy,
          ),
        ),
      ),
      if (action != null) TextButton(onPressed: onTap, child: Text(action!)),
    ],
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: padding, child: child),
  );
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.color});
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.11),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Icon(icon, color: color, size: 21),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFE7F5F3),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: teal,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => _Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          const Icon(Icons.inbox_outlined, color: Colors.blueGrey, size: 30),
          const SizedBox(height: 9),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.blueGrey.shade600),
          ),
        ],
      ),
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: _Card(
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Padding(
    padding: compact
        ? const EdgeInsets.only(bottom: 8)
        : const EdgeInsets.only(top: 10, bottom: 2),
    child: Row(
      children: [
        const Icon(Icons.cloud_off_outlined, color: teal, size: 16),
        const SizedBox(width: 6),
        Text(
          'Offline access · changes sync when connected',
          style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 12),
        ),
      ],
    ),
  );
}

String _subjectAndDate(Map<String, dynamic> item) {
  final subject = item['subject'] is Map
      ? (item['subject'] as Map)['name']?.toString()
      : null;
  final date = _formatDate(
    item['deadline'] ?? item['due_at'] ?? item['starts_at'],
  );
  return [
    subject,
    if (date != '—') date,
  ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
}

String _formatDate(Object? value) {
  if (value == null || value.toString().isEmpty) return '—';
  final date = DateTime.tryParse(value.toString())?.toLocal();
  if (date == null) return value.toString();
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
