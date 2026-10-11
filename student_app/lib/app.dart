import 'dart:async';

import 'package:flutter/material.dart';

import 'data/api_client.dart';
import 'data/local_store.dart';
import 'data/sync_service.dart';
import 'student_pages.dart';

const navy = Color(0xFF102A43);
const teal = Color(0xFF0F8B8D);
const canvas = Color(0xFFF4F7FA);

class EduSyncStudentApp extends StatelessWidget {
  const EduSyncStudentApp({
    required this.api,
    required this.store,
    required this.sync,
    super.key,
  });

  final ApiClient api;
  final LocalStore store;
  final SyncService sync;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'EduSync Student',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: teal,
        primary: teal,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: canvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: navy,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF5F8FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: teal),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    ),
    home: _AppGate(api: api, store: store, sync: sync),
  );
}

class _AppGate extends StatefulWidget {
  const _AppGate({required this.api, required this.store, required this.sync});
  final ApiClient api;
  final LocalStore store;
  final SyncService sync;
  @override
  State<_AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<_AppGate> with WidgetsBindingObserver {
  Map<String, dynamic>? _user;
  bool _loading = true;
  String? _notice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.api.onUnauthorized = () async {
      await widget.sync.stop();
      if (mounted) {
        setState(() {
          _user = null;
          _notice = 'Your session expired. Sign in again to continue syncing.';
        });
      }
    };
    unawaited(_restore());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _user != null) {
      unawaited(widget.sync.syncPending());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _restore() async {
    if (await widget.api.getToken() != null) {
      try {
        final result = await widget.api.get('/me');
        _user = Map<String, dynamic>.from(result as Map);
        await widget.store.activateStudent(_user!['id'] as int);
        await widget.store.cache('profile', _user);
        await widget.sync.start();
      } on ApiException catch (error) {
        if (error.isNetworkFailure) {
          final hasOfflineUser = await widget.store.restoreLastStudent();
          if (hasOfflineUser) {
            final cached = await widget.store.readCache('profile');
            if (cached is Map) {
              _user = Map<String, dynamic>.from(cached);
              await widget.sync.start();
            }
          } else {
            _notice = error.message;
          }
        } else if (error.statusCode != 401) {
          _notice = error.message;
        }
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _authenticated(Map<String, dynamic> user) async {
    await widget.store.activateStudent(user['id'] as int);
    await widget.store.cache('profile', user);
    await widget.sync.start();
    if (mounted) {
      setState(() {
        _user = user;
        _notice = null;
      });
    }
    unawaited(widget.sync.syncPending());
  }

  Future<void> _signOut() async {
    await widget.sync.stop();
    try {
      await widget.api.post('/logout', {});
    } on ApiException {
      // Always clear the local session, even if the server cannot be reached.
    } finally {
      await widget.api.clearToken();
      if (mounted) {
        setState(() {
          _user = null;
          _notice = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_user == null) {
      return _AuthPage(
        api: widget.api,
        onAuthenticated: _authenticated,
        notice: _notice,
      );
    }
    return _StudentHome(
      api: widget.api,
      store: widget.store,
      sync: widget.sync,
      user: _user!,
      onSignOut: _signOut,
    );
  }
}

class _AuthPage extends StatefulWidget {
  const _AuthPage({
    required this.api,
    required this.onAuthenticated,
    this.notice,
  });
  final ApiClient api;
  final Future<void> Function(Map<String, dynamic>) onAuthenticated;
  final String? notice;
  @override
  State<_AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<_AuthPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _register = false, _busy = false;
  String? _error, _info;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      if (_register) {
        final result = await widget.api.post('/register', {
          'name': _name.text.trim(),
          'email': _email.text.trim(),
          'password': _password.text,
          'password_confirmation': _confirm.text,
        }) as Map;
        setState(() {
          _register = false;
          _info =
              result['message']?.toString() ??
              'Account created. Check your email to verify your address.';
          _password.clear();
          _confirm.clear();
        });
      } else {
        final result = Map<String, dynamic>.from(
          await widget.api.post('/login', {
            'email': _email.text.trim(),
            'password': _password.text,
            'device_name': 'EduSync Student Android',
          }, timeout: const Duration(seconds: 90)) as Map,
        );
        await widget.api.saveToken(result['token'] as String);
        await widget.onAuthenticated(
          Map<String, dynamic>.from(result['user'] as Map),
        );
      }
    } on ApiException catch (error) {
      setState(() => _error = _apiMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendVerification() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter your account email address first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.post('/email/verification-notification', {
        'email': email,
      });
      setState(
        () => _info = 'If the Student account exists and is unverified, a verification link has been sent.',
      );
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 66,
                  height: 66,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: navy,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _register ? 'Create your account' : 'Welcome back',
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800, color: navy),
                ),
                const SizedBox(height: 8),
                Text(
                  _register
                      ? 'Join EduSync to keep classes and learning in one place.'
                      : 'Sign in to your student learning space.',
                ),
                const SizedBox(height: 24),
                if (widget.notice != null)
                  _Banner(message: widget.notice!, tone: Colors.orange.shade50),
                if (_info != null)
                  _Banner(message: _info!, tone: const Color(0xFFE8F6F2)),
                if (_error != null)
                  _Banner(message: _error!, tone: const Color(0xFFFFEEEE)),
                Form(
                  key: _form,
                  child: Column(
                    children: [
                      if (_register) ...[
                        TextFormField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Full name',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (value) =>
                              value == null ||
                                  value.trim().split(RegExp(r'\s+')).length < 2
                              ? 'Enter your first and last name.'
                              : null,
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email address',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                        validator: (value) =>
                            value == null || !value.contains('@')
                            ? 'Enter a valid email.'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _password,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        validator: (value) => value == null || value.length < 8
                            ? 'Use at least 8 characters.'
                            : null,
                      ),
                      if (_register) ...[
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _confirm,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Confirm password',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          validator: (value) => value != _password.text
                              ? 'Passwords do not match.'
                              : null,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(_register ? 'Create account' : 'Sign in'),
                ),
                if (!_register)
                  TextButton(
                    onPressed: _busy ? null : _resendVerification,
                    child: const Text('Resend email verification'),
                  ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _register = !_register;
                          _error = null;
                          _info = null;
                        }),
                  child: Text(
                    _register
                        ? 'Already registered? Sign in'
                        : 'New to EduSync? Create an account',
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Student accounts only',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _StudentHome extends StatefulWidget {
  const _StudentHome({
    required this.api,
    required this.store,
    required this.sync,
    required this.user,
    required this.onSignOut,
  });
  final ApiClient api;
  final LocalStore store;
  final SyncService sync;
  final Map<String, dynamic> user;
  final Future<void> Function() onSignOut;
  @override
  State<_StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<_StudentHome> {
  int _selected = 0;
  int _queueCount = 0;
  StreamSubscription<void>? _syncSubscription;
  static const _titles = [
    'Overview',
    'Classes & Subjects',
    'Learning',
    'Grades',
    'Updates',
  ];

  @override
  void initState() {
    super.initState();
    _syncSubscription = widget.sync.changes.listen(
      (_) => unawaited(_countQueue()),
    );
    unawaited(_countQueue());
  }

  @override
  void dispose() {
    unawaited(_syncSubscription?.cancel());
    super.dispose();
  }

  Future<void> _countQueue() async {
    final counts = await widget.store.queueCounts();
    if (mounted) {
      setState(
        () => _queueCount =
            counts['pending']! + counts['syncing']! + counts['failed']!,
      );
    }
  }

  Future<void> _showQueue() async {
    var counts = await widget.store.queueCounts();
    var items = await widget.store.queueHistory();
    var lastSyncAt = await widget.store.readCache('last-sync-at') as String?;
    StreamSubscription<void>? queueSubscription;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          queueSubscription ??= widget.sync.changes.listen((_) async {
            final updatedCounts = await widget.store.queueCounts();
            final updatedItems = await widget.store.queueHistory();
            final updatedLastSync =
                await widget.store.readCache('last-sync-at') as String?;
            if (!sheetContext.mounted) return;
            setSheetState(() {
              counts = updatedCounts;
              items = updatedItems;
              lastSyncAt = updatedLastSync;
            });
          });
          Future<void> syncAndRefresh() async {
            await widget.sync.syncPending();
            final updatedCounts = await widget.store.queueCounts();
            final updatedItems = await widget.store.queueHistory();
            final updatedLastSync =
                await widget.store.readCache('last-sync-at') as String?;
            if (!sheetContext.mounted) return;
            setSheetState(() {
              counts = updatedCounts;
              items = updatedItems;
              lastSyncAt = updatedLastSync;
            });
            await _countQueue();
          }

          final lastSync = lastSyncAt == null
              ? 'Never'
              : DateTime.tryParse(lastSyncAt!)?.toLocal().toString() ??
                    lastSyncAt!;
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * 0.72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
                    child: Text(
                      'Data Synchronization',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(label: Text('Pending: ${counts['pending']}')),
                        Chip(label: Text('Syncing: ${counts['syncing']}')),
                        Chip(label: Text('Synced: ${counts['success']}')),
                        Chip(label: Text('Failed: ${counts['failed']}')),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: Text('Last synchronization: $lastSync'),
                  ),
                  const Divider(height: 22),
                  Expanded(
                    child: items.isEmpty
                        ? const Center(
                            child: Text('No submissions have been queued.'),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = items[index];
                              final state =
                                  item['state']?.toString() ?? 'pending';
                              final entity =
                                  item['entity_type'] == 'quiz_attempt'
                                  ? 'Quiz'
                                  : 'Assignment';
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  state == 'success'
                                      ? Icons.check_circle_outline
                                      : state == 'failed'
                                      ? Icons.error_outline
                                      : Icons.sync,
                                  color: state == 'success'
                                      ? teal
                                      : state == 'failed'
                                      ? Colors.redAccent
                                      : Colors.blueGrey,
                                ),
                                title: Text('$entity #${item['entity_id']}'),
                                subtitle: Text(
                                  item['error']?.toString() ??
                                      (state == 'success'
                                          ? 'Synchronized successfully'
                                          : state),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: state == 'failed'
                                    ? TextButton(
                                        onPressed: syncAndRefresh,
                                        child: const Text('Retry'),
                                      )
                                    : Text(
                                        state == 'success' ? 'Synced' : state,
                                      ),
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton.icon(
                      onPressed: syncAndRefresh,
                      icon: const Icon(Icons.sync_rounded),
                      label: const Text('Sync Now'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    await queueSubscription?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(
        api: widget.api,
        store: widget.store,
        user: widget.user,
        onOpenTab: (index) => setState(() => _selected = index),
      ),
      ClassesPage(api: widget.api, store: widget.store),
      LearningPage(
        api: widget.api,
        store: widget.store,
        sync: widget.sync,
        onChanged: _countQueue,
      ),
      GradesPage(api: widget.api, store: widget.store, sync: widget.sync),
      UpdatesPage(api: widget.api, store: widget.store),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _titles[_selected],
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Offline sync queue',
            onPressed: _showQueue,
            icon: Badge(
              isLabelVisible: _queueCount > 0,
              label: Text('$_queueCount'),
              child: const Icon(Icons.sync_rounded),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'signout') unawaited(widget.onSignOut());
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'signout', child: Text('Sign out')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CircleAvatar(
                backgroundColor: const Color(0xFFD9EFED),
                child: Text(
                  _initials(widget.user['name']?.toString() ?? 'S'),
                  style: const TextStyle(color: navy),
                ),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _selected, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selected,
        onDestinationSelected: (value) {
          setState(() => _selected = value);
          _countQueue();
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.class_outlined),
            selectedIcon: Icon(Icons.class_rounded),
            label: 'Classes',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book_rounded),
            label: 'Learning',
          ),
          NavigationDestination(
            icon: Icon(Icons.grade_outlined),
            selectedIcon: Icon(Icons.grade_rounded),
            label: 'Grades',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none),
            selectedIcon: Icon(Icons.notifications),
            label: 'Updates',
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.tone});
  final String message;
  final Color tone;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: tone,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(message),
  );
}

String _apiMessage(ApiException error) {
  final errors = error.errors;
  if (errors is Map) {
    for (final messages in errors.values) {
      if (messages is List && messages.isNotEmpty) {
        return messages.first.toString();
      }
    }
  }
  return error.message;
}

String _initials(String value) => value
    .trim()
    .split(RegExp(r'\s+'))
    .where((part) => part.isNotEmpty)
    .take(2)
    .map((part) => part[0].toUpperCase())
    .join();
