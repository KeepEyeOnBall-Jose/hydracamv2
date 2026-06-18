import "package:flutter/material.dart";

class CourtSelectionWidget extends StatefulWidget {
  final Map<String, List<Map<String, String>>>
      groupedCourts; // Grouped by Sports Center
  final Function(String, String) onCourtSelected; // Callback to select court

  const CourtSelectionWidget(
      {super.key, required this.groupedCourts, required this.onCourtSelected});

  @override
  CourtSelectionWidgetState createState() => CourtSelectionWidgetState();
}

class CourtSelectionWidgetState extends State<CourtSelectionWidget> {
  String? selectedSportsCenter;
  String? selectedCourtName;
  String? selectedCourtGuid;
  TextEditingController searchController = TextEditingController();

  List<Map<String, String>> getFilteredCourts() {
    if (selectedSportsCenter == null) return [];
    final String searchText = searchController.text.toLowerCase();
    return widget.groupedCourts[selectedSportsCenter]!
        .where((court) => court["name"]!.toLowerCase().contains(searchText))
        .toList();
  }

  String? _guidForCourtName(String courtName) {
    for (final court in getFilteredCourts()) {
      if (court["name"] == courtName) {
        final guid = court["guid"];
        return guid?.isNotEmpty == true ? guid : null;
      }
    }
    return null;
  }

  void _selectCourt(String? courtName) {
    final courtGuid = courtName != null ? _guidForCourtName(courtName) : null;
    setState(() {
      selectedCourtName = courtGuid != null ? courtName : null;
      selectedCourtGuid = courtGuid;
    });

    if (selectedCourtName != null && selectedCourtGuid != null) {
      widget.onCourtSelected(selectedCourtName!, selectedCourtGuid!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredCourts = getFilteredCourts();
    final visibleSelectedCourtName = filteredCourts.any(
      (court) => court["name"] == selectedCourtName,
    )
        ? selectedCourtName
        : null;

    return ExpansionTile(
      title: Text(
        selectedCourtName != null
            ? "Selected Court: $selectedCourtName"
            : "Select a Court",
        style: const TextStyle(fontSize: 16),
      ),
      children: [
        Column(
          children: [
            DropdownButton<String>(
              hint: const Text("Select a Sports Center"),
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
                    decoration: const InputDecoration(
                      labelText: "Search Courts",
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) {
                      setState(() {}); // Refresh filtered list
                    },
                  ),
                  DropdownButton<String>(
                    hint: const Text("Select a Court"),
                    value: visibleSelectedCourtName,
                    isExpanded: true,
                    items: filteredCourts.map((court) {
                      return DropdownMenuItem<String>(
                        value: court["name"],
                        child: Text(court["name"]!),
                      );
                    }).toList(),
                    onChanged: (value) {
                      _selectCourt(value);
                    },
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
