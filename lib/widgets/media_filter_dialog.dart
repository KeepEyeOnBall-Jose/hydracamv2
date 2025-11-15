import "package:flutter/material.dart";
import "package:intl/intl.dart";

/// Class to hold media filter options.
class MediaFilters {
  final bool isPhoto;
  final DateTime? startDate;
  final DateTime? endDate;
  final Duration? minDuration; // For videos

  MediaFilters({
    required this.isPhoto,
    this.startDate,
    this.endDate,
    this.minDuration,
  });
}

/// A dialog widget to select media filters.
class MediaFilterDialog extends StatefulWidget {
  const MediaFilterDialog({super.key});

  @override
  MediaFilterDialogState createState() => MediaFilterDialogState();
}

class MediaFilterDialogState extends State<MediaFilterDialog> {
  bool isPhoto = true;
  DateTime? startDate;
  DateTime? endDate;
  int? minDurationMinutes;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Select Media Filters"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Media Type
            Row(
              children: [
                const Text("Media Type:"),
                const SizedBox(width: 10),
                DropdownButton<bool>(
                  value: isPhoto,
                  items: const [
                    DropdownMenuItem(value: true, child: Text("Photos")),
                    DropdownMenuItem(value: false, child: Text("Videos")),
                  ],
                  onChanged: (value) {
                    setState(() {
                      isPhoto = value!;
                    });
                  },
                ),
              ],
            ),
            // Date Range
            const SizedBox(height: 10),
            const Text("Date Range:"),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    title: Text(
                      startDate != null
                          ? 'From: ${DateFormat('yyyy-MM-dd').format(startDate!)}'
                          : "From: Any",
                    ),
                    onTap: _pickStartDate,
                  ),
                ),
                Expanded(
                  child: ListTile(
                    title: Text(
                      endDate != null
                          ? 'To: ${DateFormat('yyyy-MM-dd').format(endDate!)}'
                          : "To: Any",
                    ),
                    onTap: _pickEndDate,
                  ),
                ),
              ],
            ),
            // Minimum Duration (for videos)
            if (!isPhoto)
              Column(
                children: [
                  const SizedBox(height: 10),
                  const Text("Minimum Duration (minutes):"),
                  TextField(
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: "e.g., 1",
                    ),
                    onChanged: (value) {
                      setState(() {
                        minDurationMinutes = int.tryParse(value);
                      });
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context), // Cancel
          child: const Text("Cancel"),
        ),
        TextButton(
          onPressed: () {
            // Return the filters
            final MediaFilters filters = MediaFilters(
              isPhoto: isPhoto,
              startDate: startDate,
              endDate: endDate,
              minDuration: !isPhoto && minDurationMinutes != null
                  ? Duration(minutes: minDurationMinutes!)
                  : null,
            );
            Navigator.pop(context, filters);
          },
          child: const Text("Apply"),
        ),
      ],
    );
  }

  Future<void> _pickStartDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: startDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        startDate = picked;
      });
    }
  }

  Future<void> _pickEndDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: endDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        endDate = picked;
      });
    }
  }
}
