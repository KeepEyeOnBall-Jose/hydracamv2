import "package:flutter/material.dart";

import "../app_theme.dart";

class CourtSelection {
  const CourtSelection({
    required this.sportsCenterName,
    required this.courtName,
    required this.courtGuid,
  });

  final String sportsCenterName;
  final String courtName;
  final String courtGuid;

  @override
  bool operator ==(Object other) {
    return other is CourtSelection &&
        other.sportsCenterName == sportsCenterName &&
        other.courtName == courtName &&
        other.courtGuid == courtGuid;
  }

  @override
  int get hashCode => Object.hash(
        sportsCenterName,
        courtName,
        courtGuid,
      );
}

class CourtSelectionWidget extends StatefulWidget {
  final Map<String, List<Map<String, String>>> groupedCourts;
  final ValueChanged<CourtSelection?> onCourtSelected;

  const CourtSelectionWidget({
    super.key,
    required this.groupedCourts,
    required this.onCourtSelected,
  });

  @override
  CourtSelectionWidgetState createState() => CourtSelectionWidgetState();
}

class CourtSelectionWidgetState extends State<CourtSelectionWidget> {
  String? selectedSportsCenter;
  String? selectedCourtGuid;
  final TextEditingController searchController = TextEditingController();

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  List<Map<String, String>> get _centerCourts {
    final center = selectedSportsCenter;
    if (center == null) {
      return const [];
    }
    return widget.groupedCourts[center] ?? const [];
  }

  List<Map<String, String>> get _filteredCourts {
    final searchText = searchController.text.trim().toLowerCase();
    if (searchText.isEmpty) {
      return _centerCourts;
    }
    return _centerCourts
        .where(
          (court) => court["name"]?.toLowerCase().contains(searchText) ?? false,
        )
        .toList();
  }

  CourtSelection? get _selectedCourt {
    final center = selectedSportsCenter;
    final courtGuid = selectedCourtGuid;
    if (center == null || courtGuid == null) {
      return null;
    }
    for (final court in _centerCourts) {
      if (court["guid"] == courtGuid) {
        final courtName = court["name"];
        if (courtName == null || courtName.isEmpty) {
          return null;
        }
        return CourtSelection(
          sportsCenterName: center,
          courtName: courtName,
          courtGuid: courtGuid,
        );
      }
    }
    return null;
  }

  void _clearSelectedCourt({bool notify = true}) {
    selectedCourtGuid = null;
    if (notify) {
      widget.onCourtSelected(null);
    }
  }

  void _selectSportsCenter(String? value) {
    setState(() {
      selectedSportsCenter = value;
      searchController.clear();
      _clearSelectedCourt(notify: false);
    });
    widget.onCourtSelected(null);
  }

  void _selectCourt(Map<String, String> court) {
    final courtName = court["name"];
    final courtGuid = court["guid"];
    final center = selectedSportsCenter;
    if (center == null ||
        courtName == null ||
        courtName.isEmpty ||
        courtGuid == null ||
        courtGuid.isEmpty) {
      return;
    }

    final selection = CourtSelection(
      sportsCenterName: center,
      courtName: courtName,
      courtGuid: courtGuid,
    );

    setState(() {
      selectedCourtGuid = courtGuid;
    });
    widget.onCourtSelected(selection);
  }

  @override
  Widget build(BuildContext context) {
    final selection = _selectedCourt;
    final filteredCourts = _filteredCourts;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.location_on_outlined, color: AppTheme.textPrimary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Capture location",
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (selection != null)
              const Icon(Icons.check_circle, color: AppTheme.accent),
          ],
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          key: const ValueKey("sportsCenterDropdown"),
          initialValue: selectedSportsCenter,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: "Sports center",
            prefixIcon: Icon(Icons.business_outlined),
          ),
          items: widget.groupedCourts.keys
              .map(
                (center) => DropdownMenuItem<String>(
                  value: center,
                  child: Text(
                    center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: _selectSportsCenter,
        ),
        if (selectedSportsCenter != null) ...[
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey("courtSearchField"),
            controller: searchController,
            decoration: const InputDecoration(
              labelText: "Search courts",
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          if (filteredCourts.isEmpty)
            const Text(
              "No courts match this search.",
              style: AppTheme.caption,
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: filteredCourts.map((court) {
                final courtGuid = court["guid"] ?? "";
                final courtName = court["name"] ?? "Unnamed court";
                return ChoiceChip(
                  key: ValueKey("court-$courtGuid"),
                  label: Text(courtName),
                  selected: courtGuid == selectedCourtGuid,
                  onSelected: (_) => _selectCourt(court),
                );
              }).toList(),
            ),
        ],
        if (selection != null) ...[
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppTheme.accentSurface,
              border: Border.all(color: AppTheme.accent),
              borderRadius: AppTheme.smallRadius,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.check, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "${selection.sportsCenterName} · ${selection.courtName}",
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  TextButton.icon(
                    key: const ValueKey("clearCourtSelectionButton"),
                    onPressed: () {
                      setState(() {
                        _clearSelectedCourt(notify: false);
                      });
                      widget.onCourtSelected(null);
                    },
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text("Clear"),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
