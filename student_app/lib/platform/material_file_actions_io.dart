import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'material_viewer_handle.dart';

MaterialViewerHandle? prepareMaterialViewer() => null;

Future<bool> downloadMaterialUrl({
  required String url,
  required MaterialViewerHandle? viewer,
}) async => false;

void closeMaterialViewer(MaterialViewerHandle? viewer) {}

Future<String?> saveMaterialFile({
  required Uint8List bytes,
  required String fileName,
  required String? mimeType,
}) async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File(p.join(directory.path, fileName));
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<bool> openMaterialFile({
  required String path,
  required String? mimeType,
}) async {
  final result = await OpenFilex.open(path, type: mimeType);
  return result.type == ResultType.done;
}

Future<bool> openMaterialBytes({
  required Uint8List bytes,
  required String fileName,
  required String? mimeType,
  required MaterialViewerHandle? viewer,
}) async {
  final directory = await getTemporaryDirectory();
  final file = File(p.join(directory.path, fileName));
  await file.writeAsBytes(bytes, flush: true);
  return openMaterialFile(path: file.path, mimeType: mimeType);
}
