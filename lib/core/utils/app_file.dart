import 'dart:typed_data';

class AppFile {
  final String name;
  final int size;
  final String mimeType;
  final String? path;
  final Uint8List? bytes;

  AppFile({
    required this.name,
    required this.size,
    required this.mimeType,
    this.path,
    this.bytes,
  });
}