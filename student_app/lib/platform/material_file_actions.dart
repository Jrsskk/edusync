import 'dart:typed_data';

import 'material_file_actions_stub.dart'
    if (dart.library.io) 'material_file_actions_io.dart'
    if (dart.library.html) 'material_file_actions_web.dart' as platform;

export 'material_viewer_handle.dart';
import 'material_viewer_handle.dart';

MaterialViewerHandle? prepareMaterialViewer() =>
    platform.prepareMaterialViewer();

Future<bool> downloadMaterialUrl({
  required String url,
  required MaterialViewerHandle? viewer,
}) => platform.downloadMaterialUrl(url: url, viewer: viewer);

void closeMaterialViewer(MaterialViewerHandle? viewer) =>
    platform.closeMaterialViewer(viewer);

Future<String?> saveMaterialFile({
  required Uint8List bytes,
  required String fileName,
  required String? mimeType,
}) => platform.saveMaterialFile(
  bytes: bytes,
  fileName: fileName,
  mimeType: mimeType,
);

Future<bool> openMaterialFile({
  required String path,
  required String? mimeType,
}) => platform.openMaterialFile(path: path, mimeType: mimeType);

Future<bool> openMaterialBytes({
  required Uint8List bytes,
  required String fileName,
  required String? mimeType,
  required MaterialViewerHandle? viewer,
}) => platform.openMaterialBytes(
  bytes: bytes,
  fileName: fileName,
  mimeType: mimeType,
  viewer: viewer,
);
