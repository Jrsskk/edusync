import 'dart:js_interop';
import 'dart:typed_data';

import 'material_viewer_handle.dart';

import 'package:web/web.dart' as web;

class _WebViewerHandle extends MaterialViewerHandle {
  const _WebViewerHandle(this.window);

  final web.Window? window;
}

MaterialViewerHandle? prepareMaterialViewer() =>
    _WebViewerHandle(web.window.open('about:blank', '_blank'));

Future<bool> downloadMaterialUrl({
  required String url,
  required MaterialViewerHandle? viewer,
}) async => _navigate(url, viewer);

void closeMaterialViewer(MaterialViewerHandle? viewer) {
  final handle = viewer;
  if (handle is _WebViewerHandle) handle.window?.close();
}

Future<String?> saveMaterialFile({
  required Uint8List bytes,
  required String fileName,
  required String? mimeType,
}) async {
  final url = _createObjectUrl(bytes, mimeType);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  Future<void>.delayed(const Duration(minutes: 1), () {
    web.URL.revokeObjectURL(url);
  });
  return null;
}

Future<bool> openMaterialFile({
  required String path,
  required String? mimeType,
}) async {
  return web.window.open(path, '_blank') != null;
}

Future<bool> openMaterialBytes({
  required Uint8List bytes,
  required String fileName,
  required String? mimeType,
  required MaterialViewerHandle? viewer,
}) async {
  final url = _createObjectUrl(bytes, mimeType);
  final handle = viewer;
  if (handle is _WebViewerHandle && handle.window != null) {
    handle.window!.location.href = url;
  } else {
    if (web.window.open(url, '_blank') == null) return false;
  }
  Future<void>.delayed(const Duration(minutes: 1), () {
    web.URL.revokeObjectURL(url);
  });
  return true;
}

String _createObjectUrl(Uint8List bytes, String? mimeType) {
  final parts = <JSUint8Array>[bytes.toJS].toJS;
  final blob = web.Blob(
    parts,
    web.BlobPropertyBag(type: mimeType ?? 'application/octet-stream'),
  );
  return web.URL.createObjectURL(blob);
}

bool _navigate(String url, MaterialViewerHandle? viewer) {
  final handle = viewer;
  if (handle is _WebViewerHandle && handle.window != null) {
    handle.window!.location.href = url;
    return true;
  }
  return web.window.open(url, '_blank') != null;
}
