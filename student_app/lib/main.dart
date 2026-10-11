import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app.dart';
import 'data/api_client.dart';
import 'data/local_store.dart';
import 'data/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  final store = LocalStore();
  final api = ApiClient();
  final sync = SyncService(api, store);
  runApp(EduSyncStudentApp(api: api, store: store, sync: sync));
}
