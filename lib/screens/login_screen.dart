import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/user_service.dart';

/// Login Screen to manage authentication and display the current login state.
class LoginScreen extends StatelessWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final userService = Provider.of<UserService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Authentication',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            if (userService.isLoggedIn)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Logged in as: ${userService.email}'),
                  const SizedBox(height: 8),
                  Text('User GUID: ${userService.guid}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () async {
                      await userService.logout();
                    },
                    child: const Text('Logout'),
                  ),
                ],
              )
            else
              ElevatedButton(
                onPressed: () async {
                  await userService.login();
                },
                child: const Text('Login'),
              ),
          ],
        ),
      ),
    );
  }
}
