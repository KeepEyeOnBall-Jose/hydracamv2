# Baseline Blockers

- `flutter doctor -v` hung before producing output while Flutter 3.29.3 probed `/Applications/Android Studio -old, otter-.app/Contents/jbr/Contents/Home/bin/java -version`.
- `flutter build apk --debug` also hung before reaching Gradle for the same Android Studio JBR probe.
- The clean git branch does not track `android/gradlew`, `android/gradlew.bat`, or `android/gradle/wrapper/gradle-wrapper.jar`; the dirty main checkout has local wrapper files, but they are not in git.
- `pod --version` hung in this worktree and was killed before producing output.
- JDK 17 was installed with Homebrew as `openjdk@17` and Flutter was configured with `jdk-dir=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home`.
