import 'package:flutter/material.dart';
import '../services/hydracam_api_service.dart';
import 'sessions_screen.dart';

class CourtsScreen extends StatelessWidget {
  final String sportsCenterGuid;

  CourtsScreen({required this.sportsCenterGuid});

  final HydraCamApiService _apiService = HydraCamApiService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Courts")),
      body: FutureBuilder<List<Map<String, dynamic>>?>(
        future: _apiService.fetchCourts(sportsCenterGuid: sportsCenterGuid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError || snapshot.data == null) {
            return const Center(child: Text("Failed to load courts"));
          }

          final courts = snapshot.data!;
          return ListView.builder(
            itemCount: courts.length,
            itemBuilder: (context, index) {
              final court = courts[index];
              return Card(
                child: ListTile(
                  title: Text(court['Name']),
                  subtitle: Text(court['Location'] ?? 'No location'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          SessionsScreen(courtGuid: court['Guid']),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
