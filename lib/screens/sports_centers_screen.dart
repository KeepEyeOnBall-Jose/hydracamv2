import "package:flutter/material.dart";
import "../services/hydracam_api_service.dart";
import "courts_screen.dart";

class SportsCentersScreen extends StatelessWidget {
  final HydraCamApiService _apiService = HydraCamApiService();

  SportsCentersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Sports Centers")),
      body: FutureBuilder<List<Map<String, dynamic>>?>(
        future: _apiService.fetchSportsCenters(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError || snapshot.data == null) {
            return const Center(child: Text("Failed to load sports centers"));
          }

          final sportsCenters = snapshot.data!;
          return ListView.builder(
            itemCount: sportsCenters.length,
            itemBuilder: (context, index) {
              final sportsCenter = sportsCenters[index];
              return Card(
                child: ListTile(
                  title: Text(sportsCenter["name"]),
                  subtitle: Text(sportsCenter["city"] ?? "Unknown location"),
                  trailing: Text("Courts: ${sportsCenter['numberOfCourts']}"),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          CourtsScreen(sportsCenterGuid: sportsCenter["guid"]),
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
