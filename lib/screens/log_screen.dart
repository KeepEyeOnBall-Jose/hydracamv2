import "package:flutter/material.dart";
import "../services/log_service.dart";

/// A screen to display application logs, stored from any part of the app.
class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  LogScreenState createState() => LogScreenState();
}

class LogScreenState extends State<LogScreen> {
  // Fetch logs dynamically from the service
  List<Map<String, dynamic>> get logs => LogService.instance.logs;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Application Logs"),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              setState(() {
                LogService.instance
                    .clearLogs(); // Clear logs and trigger a rebuild
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Logs cleared")),
              );
            },
          ),
        ],
      ),
      body: logs.isEmpty
          ? Center(
              child: Text(
                "No logs available.",
                style: TextStyle(
                    fontSize: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            )
          : ListView.builder(
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[index];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          log["message"] ?? "No message",
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Timestamp: ${log['timestamp']?.toString() ?? 'N/A'}',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                        ),
                        if (log["function"] != null)
                          Text(
                            'Function: ${log['function']}',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                          ),
                        if (log["file"] != null)
                          Text(
                            'File: ${log['file']}',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
