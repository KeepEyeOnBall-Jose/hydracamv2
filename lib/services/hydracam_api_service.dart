import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io';

import 'log_service.dart';

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
        LogService.instance.registerLog('Failed to create session: ${response.body}');
        return null;
      }
    } catch (e) {
      LogService.instance.registerLog('Error creating session: $e');
      return null;
    }
  }

  /// End current session TODO: Maybe should be automatic, just giving max time in the create func?
  Future<bool> endSession(String sessionGuid) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/EndSession?sessionGuid=$sessionGuid'),
        headers: <String, String>{
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        LogService.instance.registerLog('Session ended successfully');
        return true;
      } else {
        LogService.instance.registerLog('Failed to end session: ${response.body}');
        return false;
      }
    } catch (e) {
      LogService.instance.registerLog('Error ending session: $e');
      return false;
    }
  }

  /// Upload a media file to the server
  Future<bool> uploadMedia(
      String sessionGuid,
      File file,
      bool isPhoto,
      String slaveDeviceId,
      DateTime captureDate,
      DateTime receivedDate,
      ) async {
    try {
      LogService.instance.registerLog("Uploading from hydracam api service for session $sessionGuid. isPhoto = $isPhoto");

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/UploadMedia?sessionGuid=$sessionGuid&isPhoto=$isPhoto'),
      );

      // Add the file
      request.files.add(await http.MultipartFile.fromPath('files', file.path));

      // Add metadata as fields
      request.fields['slaveDeviceId'] = slaveDeviceId;
      request.fields['captureDate'] = captureDate.toIso8601String();
      request.fields['receivedDate'] = receivedDate.toIso8601String();

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse); // Convert to http.Response

      if (response.statusCode == 200) {
        LogService.instance.registerLog('Media uploaded successfully');
        return true;
      } else {
        LogService.instance.registerLog('Failed to upload media: ${response.statusCode}');
        LogService.instance.registerLog('Error details: ${response.body}');
        return false;
      }
    } catch (e) {
      LogService.instance.registerLog('Error uploading media: $e');
      return false;
    }
  }

  /// Check the status of uploaded media
  Future<void> checkUploadStatus() async {
    // Implement this if you have a way to query the status of media uploads
  }

  /// Notify server that device is ready to transmit
  Future<bool> notifyReadyToTransmit(String deviceId, String sessionGuid) async {
    try {
      final uri = Uri.parse('$_baseUrl/device/ReadyToTransmit');
      final response = await http.post(
        uri,
        headers: <String, String>{
          'Content-Type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'DeviceId': deviceId,
          'SessionGuid': sessionGuid,
        }),
      );

      if (response.statusCode == 200) {
        LogService.instance.registerLog('Dispositivo notificó al servidor que está listo para transmitir');
        return true;
      } else {
        LogService.instance.registerLog('Fallo al notificar al servidor: ${response.body}');
        return false;
      }
    } catch (e) {
      LogService.instance.registerLog('Error al notificar al servidor: $e');
      return false;
    }
  }

  /// Fetch a list of sports centers
  Future<List<Map<String, dynamic>>?> fetchSportsCenters() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/sportscenters'));

      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(response.body));
      } else {
        LogService.instance.registerLog('Failed to fetch sports centers: ${response.body}');
        return null;
      }
    } catch (e) {
      LogService.instance.registerLog('Error fetching sports centers: $e');
      return null;
    }
  }

  /// Fetch a list of courts, optionally filtered by Sports Center GUID
  Future<List<Map<String, dynamic>>?> fetchCourts({String? sportsCenterGuid}) async {
    try {
      final uri = Uri.parse(
          sportsCenterGuid == null ? '$_baseUrl/courts' : '$_baseUrl/courts?sportsCenterGuid=$sportsCenterGuid');

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(response.body));
      } else {
        LogService.instance.registerLog('Failed to fetch courts: ${response.body}');
        return null;
      }
    } catch (e) {
      LogService.instance.registerLog('Error fetching courts: $e');
      return null;
    }
  }

  /// Fetch a list of sessions for a specific court
  Future<List<Map<String, dynamic>>?> fetchSessions(String courtGuid) async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/sessions?courtGuid=$courtGuid'));

      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(response.body));
      } else {
        LogService.instance.registerLog('Failed to fetch sessions: ${response.body}');
        return null;
      }
    } catch (e) {
      LogService.instance.registerLog('Error fetching sessions: $e');
      return null;
    }
  }
}
