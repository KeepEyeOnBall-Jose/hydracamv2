import 'package:flutter/material.dart';
import '../services/user_service.dart';

/// Login Screen to manage authentication and display the current login state.
class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  bool _isUserDetailsLoading = false;  // Added for user details loading
  String? _errorMessage;
  Map<String, dynamic>? _userDetails; // To store user details fetched from the API

  final UserService _userService = UserService();

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _userService.login();
      await _fetchUserDetails();  // Fetch user details after login
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to log in. Please try again.';
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
        _errorMessage = 'Failed to log out. Please try again.';
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
        print("will fetch user details");
        final userDetails = await _userService.fetchUserDetails(_userService.guid!);
        setState(() {
          _userDetails = userDetails;
        });
      } catch (e) {
        setState(() {
          _errorMessage = 'Failed to fetch user details. Please try again.';
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
        title: const Text('User Authentication'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: _isLoading
              ? const CircularProgressIndicator()  // Show loading while logging in
              : _userService.isLoggedIn
              ? _isUserDetailsLoading  // Show loading while fetching user details
              ? const CircularProgressIndicator()
              : _buildLoggedInView()
              : _buildLoggedOutView(),
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
          'Welcome! Please log in to continue.',
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _login,
          child: const Text('Login'),
        ),
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
              : null, // Show default icon if no profile picture
          child: profilePictureUrl == null
              ? const Icon(Icons.person, size: 50, color: Colors.white)
              : null,
          backgroundColor: Colors.grey.shade300,
        ),
        const SizedBox(height: 20),
        Text(
          _userService.email ?? 'Unknown User',
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
          child: const Text('Logout'),
        ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 10),
        _userDetails == null
            ? const Text('Loading user details...')
            : _buildUserDetailsView(),  // Display user details once loaded
      ],
    );
  }

  Widget _buildUserDetailsView() {
    if (_userDetails == null) return Container();

    final gender = _userDetails!['gender'] ?? 'Unknown';
    final country = _userDetails!['country'] ?? 'Unknown';
    final sports = _userDetails!['sports'] ?? 'None';
    final fullName = _userDetails!['fullName'] ?? 'Unknown';
    final email = _userDetails!['email'] ?? 'Unknown';

    return Column(
      children: [
        const SizedBox(height: 20),
        Text(
          'Full Name: $fullName',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 10),
        Text(
          'Email: $email',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 10),
        Text(
          'Country: $country',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 10),
        Text(
          'Gender: $gender',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 10),
        Text(
          'Sports: $sports',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}
