import 'dart:typed_data';

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
  throw UnsupportedError('File downloads are not supported on this platform.');
}

Future<bool> openMaterialFile({
  required String path,
  required String? mimeType,
}) async {
  throw UnsupportedError('Opening local files is not supported on this platform.');
}

Future<bool> openMaterialBytes({
  required Uint8List bytes,
  required String fileName,
  required String? mimeType,
  required MaterialViewerHandle? viewer,
}) async {
  throw UnsupportedError('Opening files is not supported on this platform.');
}
