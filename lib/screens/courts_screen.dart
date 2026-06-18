import "package:flutter/material.dart";
import "../services/hydracam_api_service.dart";
import "../widgets/hydracam_surface.dart";
import "sessions_screen.dart";

class CourtsScreen extends StatelessWidget {
  final String sportsCenterGuid;

  CourtsScreen({super.key, required this.sportsCenterGuid});

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
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: courts.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final court = courts[index];
              return HydraCamSurface(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.sports_tennis_outlined),
                  title: Text(court["name"]?.toString() ?? "Unnamed court"),
                  subtitle: Text(court["location"] ?? "No location"),
                  trailing: const HydraCamBadge(
                    icon: Icons.event_note_outlined,
                    label: "Sessions",
                    tone: HydraCamStatusTone.neutral,
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          SessionsScreen(courtGuid: court["guid"]),
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
