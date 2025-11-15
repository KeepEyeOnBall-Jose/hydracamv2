
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Platform Setup Tests', () {
    test('iOS Podfile should exist and be valid', () {
      final podfile = File('ios/Podfile');
      expect(podfile.existsSync(), isTrue, reason: 'ios/Podfile does not exist. Please run "flutter create ." to regenerate it.');
      
      final content = podfile.readAsStringSync();
      expect(content, isNotEmpty, reason: 'ios/Podfile is empty.');
    });
  });
}
