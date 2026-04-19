// Only compiled on Flutter Web (dart.library.html is available).
// Import via conditional import:
//
//   import 'web_save_stub.dart'
//       if (dart.library.html) 'web_save_web.dart';

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

/// Triggers a browser "Save As" dialog for [data].
void webSaveBytes(Uint8List data, String fileName, String mimeType) {
  final blob = html.Blob([data], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);

  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..style.display = 'none';

  html.document.body!.append(anchor);
  anchor.click();
  anchor.remove();

  Future.delayed(const Duration(seconds: 5), () {
    html.Url.revokeObjectUrl(url);
  });
}