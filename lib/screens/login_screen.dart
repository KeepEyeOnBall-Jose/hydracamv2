import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:url_launcher/url_launcher.dart";
import "../services/log_service.dart";
import "../services/user_service.dart";

typedef StoreUrlLauncher = Future<bool> Function(Uri uri);
typedef AccountDeletionLauncher = StoreUrlLauncher;

/// Login Screen to manage authentication and display the current login state.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.privacyPolicyUrl =
        const String.fromEnvironment("HYDRACAM_PRIVACY_POLICY_URL"),
    this.supportUrl = const String.fromEnvironment("HYDRACAM_SUPPORT_URL"),
    this.accountDeletionUrl =
        const String.fromEnvironment("HYDRACAM_ACCOUNT_DELETION_URL"),
    this.storeUrlLauncher,
    this.accountDeletionLauncher,
  });

  final String privacyPolicyUrl;
  final String supportUrl;
  final String accountDeletionUrl;
  final StoreUrlLauncher? storeUrlLauncher;
  final AccountDeletionLauncher? accountDeletionLauncher;

  @override
  LoginScreenState createState() => LoginScreenState();
}

class LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  bool _isUserDetailsLoading = false; // Added for user details loading
  String? _errorMessage;
  Map<String, dynamic>?
      _userDetails; // To store user details fetched from the API

  final UserService _userService = UserService();

  Uri? _configuredUri(String configuredUrl) {
    final value = configuredUrl.trim();
    if (value.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        uri.scheme.toLowerCase() != "https") {
      return null;
    }

    return uri;
  }

  Uri? get _privacyPolicyUri => _configuredUri(widget.privacyPolicyUrl);

  Uri? get _supportUri => _configuredUri(widget.supportUrl);

  Uri? get _accountDeletionUri => _configuredUri(widget.accountDeletionUrl);

  String _accountDeletionRequestText() {
    return [
      "HydraCam account deletion request",
      "Login email: ${_userService.email ?? "unknown"}",
      "HydraCam GUID: ${_userService.guid ?? "unknown"}",
      "Request: delete my HydraCam account and associated backend data.",
    ].join("\n");
  }

  Future<void> _openExternalUrl(
    Uri uri, {
    required String openedMessage,
    required String failedMessage,
  }) async {
    final launcher = widget.storeUrlLauncher ??
        widget.accountDeletionLauncher ??
        (Uri targetUri) {
          return launchUrl(targetUri, mode: LaunchMode.externalApplication);
        };
    final launched = await launcher(uri);
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          launched ? openedMessage : failedMessage,
        ),
      ),
    );
  }

  Future<void> _openPrivacyPolicy() async {
    final privacyUri = _privacyPolicyUri;
    if (privacyUri == null) {
      await _showInformationDialog(
        title: "Privacy Policy",
        body:
            "HydraCam processes Auth0 login identity, device and session identifiers, captured photos, videos, microphone audio, selected gallery media, optional location/network context, and local diagnostics for app functionality, upload, and support. Publish HYDRACAM_PRIVACY_POLICY_URL before store upload so release builds open the full public policy.",
      );
      return;
    }

    await _openExternalUrl(
      privacyUri,
      openedMessage: "Privacy policy opened.",
      failedMessage: "Could not open privacy policy.",
    );
  }

  Future<void> _openSupportPage() async {
    final supportUri = _supportUri;
    if (supportUri == null) {
      await _showInformationDialog(
        title: "Support",
        body:
            "HydraCam support should cover setup on the same local network or hotspot, camera and microphone permissions, iOS Local Network permission, upload retries, duplicate beta installs, and account/data deletion requests. Publish HYDRACAM_SUPPORT_URL before store upload so release builds open the public support page.",
      );
      return;
    }

    await _openExternalUrl(
      supportUri,
      openedMessage: "Support page opened.",
      failedMessage: "Could not open support page.",
    );
  }

  Future<void> _showInformationDialog({
    required String title,
    required String body,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Text(body),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text("Close"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAccountDeletionDialog() async {
    final deletionUri = _accountDeletionUri;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Account Deletion"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deletionUri == null
                      ? "Send this request through the published HydraCam support or deletion URL. Include the login email and HydraCam GUID shown here so support can match the Auth0 and backend records."
                      : "Open the deletion page and include the login email and HydraCam GUID shown here so support can match the Auth0 and backend records.",
                ),
                const SizedBox(height: 16),
                SelectableText(_accountDeletionRequestText()),
                if (deletionUri != null) ...[
                  const SizedBox(height: 16),
                  SelectableText(deletionUri.toString()),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text("Close"),
            ),
            if (deletionUri != null)
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _openExternalUrl(
                    deletionUri,
                    openedMessage: "Account deletion page opened.",
                    failedMessage: "Could not open account deletion page.",
                  );
                },
                child: const Text("Open Deletion Page"),
              ),
            FilledButton(
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: _accountDeletionRequestText()),
                );
                Navigator.of(dialogContext).pop();
                if (!mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Account deletion request copied."),
                  ),
                );
              },
              child: const Text("Copy Request"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _userService.login();
      await _fetchUserDetails(); // Fetch user details after login
    } on UnsupportedError catch (e) {
      setState(() {
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Failed to log in. Please try again.";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _logout() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _userService.logout();
    } catch (e) {
      setState(() {
        _errorMessage = "Failed to log out. Please try again.";
      });
    } finally {
      setState(() {
        _isLoading = false;
        _userDetails = null; // Clear user details on logout
      });
    }
  }

  Future<void> _fetchUserDetails() async {
    if (_userService.guid != null) {
      setState(() {
        _isUserDetailsLoading = true; // Start loading user details
      });

      try {
        LogService.instance.registerLog("will fetch user details",
            function: "_loadUserDetails", file: "login_screen.dart");
        final userDetails =
            await _userService.fetchUserDetails(_userService.guid!);
        setState(() {
          _userDetails = userDetails;
        });
      } catch (e) {
        setState(() {
          _errorMessage = "Failed to fetch user details. Please try again.";
        });
      } finally {
        setState(() {
          _isUserDetailsLoading = false; // Stop loading user details
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("User Authentication"),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: _isLoading
                ? const CircularProgressIndicator()
                : _userService.isLoggedIn
                    ? _isUserDetailsLoading
                        ? const CircularProgressIndicator()
                        : _buildLoggedInView()
                    : _buildLoggedOutView(),
          ),
        ),
      ),
    );
  }

  Widget _buildLoggedOutView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 45,
          backgroundColor: Colors.grey.shade300,
          child: const Icon(
            Icons.person,
            size: 60,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          "Welcome! Please log in to continue.",
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _login,
          child: const Text("Login"),
        ),
        const SizedBox(height: 12),
        _buildStorePolicyActions(),
        if (_errorMessage != null) ...[
          const SizedBox(height: 20),
          Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildLoggedInView() {
    final profilePictureUrl = _userService.profilePicture;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 50,
          backgroundImage: profilePictureUrl != null
              ? NetworkImage(profilePictureUrl)
              : null,
          backgroundColor:
              Colors.grey.shade300, // Show default icon if no profile picture
          child: profilePictureUrl == null
              ? const Icon(Icons.person, size: 50, color: Colors.white)
              : null,
        ),
        const SizedBox(height: 20),
        Text(
          _userService.email ?? "Unknown User",
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          'GUID: ${_userService.guid ?? 'N/A'}',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _logout,
          child: const Text("Logout"),
        ),
        const SizedBox(height: 12),
        _buildStorePolicyActions(),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 10),
        _userDetails == null
            ? const Text("Loading user details...")
            : _buildUserDetailsView(), // Display user details once loaded
      ],
    );
  }

  Widget _buildUserDetailsView() {
    if (_userDetails == null) return Container();

    final gender = _userDetails!["gender"] ?? "Unknown";
    final country = _userDetails!["country"] ?? "Unknown";
    final sports = _userDetails!["sports"] ?? "None";
    final fullName = _userDetails!["fullName"] ?? "Unknown";
    final email = _userDetails!["email"] ?? "Unknown";

    return Column(
      children: [
        const SizedBox(height: 20),
        Text(
          "Full Name: $fullName",
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 10),
        Text(
          "Email: $email",
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 10),
        Text(
          "Country: $country",
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 10),
        Text(
          "Gender: $gender",
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 10),
        Text(
          "Sports: $sports",
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildStorePolicyActions() {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        TextButton.icon(
          onPressed: _openPrivacyPolicy,
          icon: const Icon(Icons.privacy_tip_outlined),
          label: const Text("Privacy Policy"),
        ),
        TextButton.icon(
          onPressed: _openSupportPage,
          icon: const Icon(Icons.help_outline),
          label: const Text("Support"),
        ),
        _buildAccountDeletionButton(),
      ],
    );
  }

  Widget _buildAccountDeletionButton() {
    return TextButton.icon(
      onPressed: _showAccountDeletionDialog,
      icon: const Icon(Icons.delete_outline),
      label: const Text("Request Account Deletion"),
    );
  }
}
