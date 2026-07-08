import 'dart:math';

class UuidUtils {
  static final Random _random = Random.secure();

  /// Generates a valid version 4 UUID string.
  /// Format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
  static String generate() {
    String generateHex(int length) {
      const chars = '0123456789abcdef';
      return String.fromCharCodes(Iterable.generate(
          length, (_) => chars.codeUnitAt(_random.nextInt(chars.length))));
    }

    final s1 = generateHex(8);
    final s2 = generateHex(4);
    final s3 = '4${generateHex(3)}'; // Version 4
    
    // y must be one of 8, 9, a, or b
    const yChars = '89ab';
    final yChar = yChars[_random.nextInt(yChars.length)];
    final s4 = '$yChar${generateHex(3)}';
    
    final s5 = generateHex(12);

    return '$s1-$s2-$s3-$s4-$s5';
  }
}
