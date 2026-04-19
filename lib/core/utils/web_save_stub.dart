// Stub compiled on mobile / desktop — does nothing.
// Import pattern:
//
//   import 'web_save_stub.dart'
//       if (dart.library.html) 'web_save_web.dart';

import 'dart:typed_data';

void webSaveBytes(Uint8List data, String fileName, String mimeType) {
  // No-op on non-web platforms.
}