import 'package:flutter/material.dart';
import '../services/log_service.dart';

/// A screen to display application logs.
class LogScreen extends StatefulWidget {
  const LogScreen({Key? key}) : super(key: key);

  @override
  _LogScreenState createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  // Fetch logs dynamically from the service
  List<Map<String, dynamic>> get logs => LogService.instance.logs;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Application Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              setState(() {
                LogService.instance.clearLogs(); // Clear logs and trigger a rebuild
              });
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
