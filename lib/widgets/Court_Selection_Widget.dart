import 'package:flutter/material.dart';

class CourtSelectionWidget extends StatefulWidget {
  final Map<String, List<Map<String, String>>> groupedCourts; // Grouped by Sports Center
  final Function(String, String) onCourtSelected; // Callback to select court

  CourtSelectionWidget({required this.groupedCourts, required this.onCourtSelected});

  @override
  _CourtSelectionWidgetState createState() => _CourtSelectionWidgetState();
}

class _CourtSelectionWidgetState extends State<CourtSelectionWidget> {
  String? selectedSportsCenter;
  String? selectedCourtName;
  String? selectedCourtGuid;
  TextEditingController searchController = TextEditingController();

  List<Map<String, String>> getFilteredCourts() {
    if (selectedSportsCenter == null) return [];
    String searchText = searchController.text.toLowerCase();
    return widget.groupedCourts[selectedSportsCenter]!
        .where((court) => court['name']!.toLowerCase().contains(searchText))
        .toList();
  }

  void _selectCourt(String? courtName) {
    setState(() {
      selectedCourtName = courtName;
      selectedCourtGuid = courtName != null
          ? getFilteredCourts().firstWhere(
            (court) => court['name'] == courtName,
        orElse: () => {"guid": ""}, // Cambiado null por cadena vacía
      )['guid']
          : null;
    });

    if (selectedCourtName != null && selectedCourtGuid != null) {
      widget.onCourtSelected(selectedCourtName!, selectedCourtGuid!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DropdownButton<String>(
          hint: Text("Select a Sports Center"),
          value: selectedSportsCenter,
          isExpanded: true,
          items: widget.groupedCourts.keys.map((scName) {
            return DropdownMenuItem<String>(
              value: scName,
              child: Text(scName),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              selectedSportsCenter = value;
              selectedCourtName = null;
              selectedCourtGuid = null;
            });
          },
        ),
        if (selectedSportsCenter != null)
          Column(
            children: [
              TextField(
                controller: searchController,
                decoration: InputDecoration(
                  labelText: "Search Courts",
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) {
                  setState(() {}); // Refresh filtered list
                },
              ),
              DropdownButton<String>(
                hint: Text("Select a Court"),
                value: selectedCourtName,
                isExpanded: true,
                items: getFilteredCourts().map((court) {
                  return DropdownMenuItem<String>(
                    value: court['name'],
                    child: Text(court['name']!),
                  );
                }).toList(),
                onChanged: (value) {
                  _selectCourt(value);
                },
              ),
            ],
          ),
        if (selectedCourtName != null)
          Text("Selected Court: $selectedCourtName (GUID: $selectedCourtGuid)"),
      ],
    );
  }
}
