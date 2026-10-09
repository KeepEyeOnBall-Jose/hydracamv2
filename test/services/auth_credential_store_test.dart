import "dart:convert";
import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/auth0_service.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage();
  const store = SecureAuthCredentialStore();

  test("reads legacy keys then replaces the complete credential envelope",
      () async {
    FlutterSecureStorage.setMockInitialValues({
      "auth0_access_token": "old-test-access",
      "auth0_id_token": "old-test-id",
      "auth0_refresh_token": "old-test-refresh",
      "auth0_access_token_expires_at": "2026-10-09T10:00:00Z",
      "capture-draft": "retained",
    });
    expect((await store.load())?.refreshToken, "old-test-refresh");
    await store.save(AuthCredentials(
      accessToken: "new-test-access",
      idToken: "new-test-id",
      refreshToken: "rotated-test-refresh",
      accessTokenExpiresAt: DateTime.utc(2026, 10, 9, 11),
    ));
    final keys = await storage.readAll();
    expect(
        keys.keys, unorderedEquals(["auth0_credentials_v1", "capture-draft"]));
    expect((await store.load())?.refreshToken, "rotated-test-refresh");
    await store.clear();
    expect(await store.load(), isNull);
    expect(await storage.read(key: "capture-draft"), "retained");
  });

  test("committed envelope wins over interrupted legacy cleanup", () async {
    FlutterSecureStorage.setMockInitialValues({
      "auth0_access_token": "old-test-access",
      "auth0_refresh_token": "old-test-refresh",
      "auth0_credentials_v1": jsonEncode({
        "accessToken": "new-test-access",
        "refreshToken": "rotated-test-refresh",
      }),
    });
    expect((await store.load())?.refreshToken, "rotated-test-refresh");
  });
}
