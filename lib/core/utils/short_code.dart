// lib/core/utils/short_code.dart
import 'dart:math';

/// Unambiguous alphabet: excludes O/0, I/l/1 to avoid user confusion
const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const _codeLength = 7; // 32^7 = ~34 billion combinations; collision-safe

class ShortCodeGenerator {
  static final Random _rng = Random.secure();

  /// Generates a random short code like "A4X9K2M"
  static String generate() {
    return List.generate(
      _codeLength,
      (_) => _alphabet[_rng.nextInt(_alphabet.length)],
    ).join();
  }

  /// Normalizes user input: uppercase, strip ambiguous chars
  static String normalize(String input) {
    return input
        .toUpperCase()
        .replaceAll('O', '0') // user typed O, means 0 — but 0 not in alpha
        .replaceAll('0', '') // 0 invalid; we remove since our alpha has no 0
        .replaceAll('I', '')
        .replaceAll('L', '')
        .replaceAll('1', '')
        .trim();
  }

  /// Returns true if the code matches our alphabet and length
  static bool isValid(String code) {
    if (code.length != _codeLength) return false;
    return code.split('').every((c) => _alphabet.contains(c));
  }
}