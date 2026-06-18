import "package:flutter_test/flutter_test.dart";
import "package:hydracam/services/auth0_service.dart";
import "package:hydracam/services/user_service.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("UserService restores HydraCam GUID after Auth0 restore", () async {
    String? requestedEmail;
    final service = UserService.forTesting(
      authService: _FakeAuthService(
        restoreResult: true,
        restoredEmail: "restored@example.com",
        restoredProfilePicture: "https://example.com/restored.png",
      ),
      getUserGuidByEmail: (email) async {
        requestedEmail = email;
        return "hydracam-user-guid";
      },
    );

    final restored = await service.restoreStoredSession();

    expect(restored, isTrue);
    expect(requestedEmail, "restored@example.com");
    expect(service.isLoggedIn, isTrue);
    expect(service.email, "restored@example.com");
    expect(service.profilePicture, "https://example.com/restored.png");
    expect(service.guid, "hydracam-user-guid");
  });

  test("UserService restore clears state when Auth0 restore fails", () async {
    var lookupCalls = 0;
    final service = UserService.forTesting(
      authService: _FakeAuthService(restoreResult: false),
      getUserGuidByEmail: (_) async {
        lookupCalls += 1;
        return "unexpected-guid";
      },
    );

    final restored = await service.restoreStoredSession();

    expect(restored, isFalse);
    expect(lookupCalls, 0);
    expect(service.isLoggedIn, isFalse);
    expect(service.email, isNull);
    expect(service.profilePicture, isNull);
    expect(service.guid, isNull);
  });

  test("UserService restore rejects blank restored email", () async {
    var lookupCalls = 0;
    final service = UserService.forTesting(
      authService: _FakeAuthService(
        restoreResult: true,
        restoredEmail: "   ",
        restoredProfilePicture: "https://example.com/blank.png",
      ),
      getUserGuidByEmail: (_) async {
        lookupCalls += 1;
        return "unexpected-guid";
      },
    );

    final restored = await service.restoreStoredSession();

    expect(restored, isFalse);
    expect(lookupCalls, 0);
    expect(service.isLoggedIn, isFalse);
    expect(service.email, isNull);
    expect(service.profilePicture, isNull);
    expect(service.guid, isNull);
  });

  test("UserService login rejects blank Auth0 email", () async {
    var lookupCalls = 0;
    final service = UserService.forTesting(
      authService: _FakeAuthService(
        restoreResult: false,
        loginEmail: "   ",
        loginProfilePicture: "https://example.com/blank-login.png",
      ),
      getUserGuidByEmail: (_) async {
        lookupCalls += 1;
        return "unexpected-guid";
      },
    );

    await service.login();

    expect(lookupCalls, 0);
    expect(service.isLoggedIn, isFalse);
    expect(service.email, isNull);
    expect(service.profilePicture, isNull);
    expect(service.guid, isNull);
  });

  test("UserService login rejects blank backend GUID", () async {
    final service = UserService.forTesting(
      authService: _FakeAuthService(
        restoreResult: false,
        loginEmail: "user@example.com",
        loginProfilePicture: "https://example.com/user.png",
      ),
      getUserGuidByEmail: (_) async => "   ",
    );

    await service.login();

    expect(service.isLoggedIn, isFalse);
    expect(service.email, isNull);
    expect(service.profilePicture, isNull);
    expect(service.guid, isNull);
  });

  test("UserService restore rejects blank backend GUID", () async {
    final service = UserService.forTesting(
      authService: _FakeAuthService(
        restoreResult: true,
        restoredEmail: "restored@example.com",
        restoredProfilePicture: "https://example.com/restored.png",
      ),
      getUserGuidByEmail: (_) async => "   ",
    );

    final restored = await service.restoreStoredSession();

    expect(restored, isFalse);
    expect(service.isLoggedIn, isFalse);
    expect(service.email, isNull);
    expect(service.profilePicture, isNull);
    expect(service.guid, isNull);
  });

  test("UserService login clears stale GUID when switched account is unmapped",
      () async {
    final authService = _FakeAuthService(
      restoreResult: false,
      loginEmail: "first@example.com",
      loginProfilePicture: "https://example.com/first.png",
    );
    final service = UserService.forTesting(
      authService: authService,
      getUserGuidByEmail: (email) async {
        if (email == "first@example.com") {
          return "first-guid";
        }
        return null;
      },
    );

    await service.login();

    expect(service.isLoggedIn, isTrue);
    expect(service.email, "first@example.com");
    expect(service.guid, "first-guid");

    authService
      ..loginEmail = "missing@example.com"
      ..loginProfilePicture = "https://example.com/missing.png";

    await service.login();

    expect(service.isLoggedIn, isFalse);
    expect(service.email, isNull);
    expect(service.profilePicture, isNull);
    expect(service.guid, isNull);
  });

  test("UserService login clears stale user when Auth0 login fails", () async {
    final authService = _FakeAuthService(
      restoreResult: false,
      loginEmail: "first@example.com",
      loginProfilePicture: "https://example.com/first.png",
    );
    final service = UserService.forTesting(
      authService: authService,
      getUserGuidByEmail: (email) async {
        if (email == "first@example.com") {
          return "first-guid";
        }
        return null;
      },
    );

    await service.login();

    expect(service.isLoggedIn, isTrue);
    expect(service.email, "first@example.com");
    expect(service.guid, "first-guid");

    authService.loginError = Exception("Auth0 session failed");

    await expectLater(service.login(), throwsException);

    expect(service.isLoggedIn, isFalse);
    expect(service.email, isNull);
    expect(service.profilePicture, isNull);
    expect(service.guid, isNull);
  });
}

class _FakeAuthService extends AuthService {
  final bool restoreResult;
  final String? restoredEmail;
  final String? restoredProfilePicture;
  String? loginEmail;
  String? loginProfilePicture;
  Object? loginError;

  _FakeAuthService({
    required this.restoreResult,
    this.restoredEmail,
    this.restoredProfilePicture,
    this.loginEmail,
    this.loginProfilePicture,
  });

  @override
  Future<void> login() async {
    final error = loginError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<bool> restoreStoredSession() async => restoreResult;

  @override
  String? get email => loginEmail ?? restoredEmail;

  @override
  String? get profilePicture => loginProfilePicture ?? restoredProfilePicture;
}
