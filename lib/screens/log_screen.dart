import 'package:flutter/material.dart';
import '../services/log_service.dart';

/// A screen to display application logs.
class LogScreen extends StatelessWidget {
  const LogScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final logs = LogService.instance.logs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Application Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              LogService.instance.clearLogs();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Logs cleared')),
              );
            },
          ),
        ],
      ),
      body: logs.isEmpty
          ? const Center(
        child: Text(
          'No logs available.',
          style: TextStyle(fontSize: 18, color: Colors.grey),
        ),
      )
          : ListView.builder(
        itemCount: logs.length,
        itemBuilder: (context, index) {
          final log = logs[index];
          return Card(
            margin: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    log['message'] ?? 'No message',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Timestamp: ${log['timestamp']?.toString() ?? 'N/A'}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  if (log['function'] != null)
                    Text(
                      'Function: ${log['function']}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  if (log['file'] != null)
                    Text(
                      'File: ${log['file']}',
                      style: const TextStyle(color: Colors.grey),
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
