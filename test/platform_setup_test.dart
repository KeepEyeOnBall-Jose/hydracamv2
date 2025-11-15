
import "dart:io";
import "package:flutter_test/flutter_test.dart";

void main() {
  group("Platform Setup Tests", () {
    test("iOS Podfile should exist and be valid", () {
      final podfile = File("ios/Podfile");
      expect(podfile.existsSync(), isTrue, reason: 'ios/Podfile does not exist. Please run "flutter create ." to regenerate it.');
      
      final content = podfile.readAsStringSync();
      expect(content, isNotEmpty, reason: "ios/Podfile is empty.");
    });

    test("Android build.gradle should exist", () {
      final buildGradle = File("android/build.gradle");
      expect(buildGradle.existsSync(), isTrue, reason: 'android/build.gradle does not exist. Please run "flutter create ." to regenerate it.');
    });

    test("Web index.html should exist", () {
      final indexHtml = File("web/index.html");
      expect(indexHtml.existsSync(), isTrue, reason: 'web/index.html does not exist. Please run "flutter create ." to regenerate it.');
    });
  });
}
