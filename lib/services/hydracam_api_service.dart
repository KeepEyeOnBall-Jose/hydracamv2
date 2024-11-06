import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io';

/// Singleton class to manage API communication for HydraCam
class HydraCamApiService {
  // Singleton instance
  static final HydraCamApiService _instance = HydraCamApiService._internal();
  factory HydraCamApiService() => _instance;

  HydraCamApiService._internal();

  // Base URL for the API
  final String _baseUrl = 'https://keobmotherboardweb.azurewebsites.net/api/hydracam';

  /// Create a new capture session
  Future<Map<String, dynamic>?> createSession(String sessionId, {String? courtGuid}) async {
    try {
      final uri = Uri.parse(
          courtGuid == null
              ? '$_baseUrl/CreateSession'
              : '$_baseUrl/CreateSession?courtGuid=$courtGuid'
      );

      final response = await http.post(
        uri,
        headers: <String, String>{
          'Content-Type': 'application/json',
        },
        body: jsonEncode(<String, String>{
          'SessionId': sessionId,
          'StartTime': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('Failed to create session: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error creating session: $e');
      return null;
    }
  }

  /// Upload a media file to the server
  Future<bool> uploadMedia(String sessionGuid, File file, bool isPhoto) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/UploadMedia?sessionGuid=$sessionGuid&isPhoto=$isPhoto'),
      );

      request.files.add(await http.MultipartFile.fromPath('files', file.path));
      var response = await request.send();

      if (response.statusCode == 200) {
        print('Media uploaded successfully');
        return true;
      } else {
        print('Failed to upload media: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('Error uploading media: $e');
      return false;
    }
  }

  /// Check the status of uploaded media
  Future<void> checkUploadStatus() async {
    // Implement this if you have a way to query the status of media uploads
  }
}
