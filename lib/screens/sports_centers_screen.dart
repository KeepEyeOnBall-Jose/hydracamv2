import "package:flutter/material.dart";
import "../widgets/hydracam_surface.dart";
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
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: sportsCenters.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final sportsCenter = sportsCenters[index];
              return HydraCamSurface(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.location_city_outlined),
                  title: Text(sportsCenter["name"]?.toString() ?? "Unnamed"),
                  subtitle: Text(sportsCenter["city"] ?? "Unknown location"),
                  trailing: HydraCamBadge(
                    icon: Icons.sports_tennis_outlined,
                    label: "Courts: ${sportsCenter['numberOfCourts']}",
                    tone: HydraCamStatusTone.neutral,
                  ),
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
