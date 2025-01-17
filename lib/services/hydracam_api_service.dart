import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'log_service.dart';
import 'auth0_m2m_service.dart'; // Servicio para obtener el token M2M

/// Singleton class to manage API communication for HydraCam
class HydraCamApiService {
  // Singleton instance
  static final HydraCamApiService _instance = HydraCamApiService._internal();
  factory HydraCamApiService() => _instance;

  HydraCamApiService._internal();

  // Base URL for the API
  final String _baseUrl = 'https://hydracam.azurewebsites.net/api';

  /// Obtiene las cabeceras comunes, incluyendo Authorization: Bearer <token>
  Future<Map<String, String>> _getHeaders() async {
    final token = await M2MAuthService().getToken();
    if (token == null) {
      throw Exception("Failed to retrieve M2M token");
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Realiza un GET genérico con headers y parsing
  Future<Map<String, dynamic>?> _get(String endpoint) async {
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse('$_baseUrl / $endpoint'.replaceAll(' ', '')); // Limpia espacios si hay
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        LogService.instance.registerLog('GET $endpoint failed: ${response.body}');
        return null;
      }
    } catch (e) {
      LogService.instance.registerLog('Error on GET $endpoint: $e');
      return null;
    }
  }

  /// Realiza un POST genérico con headers y parsing
  Future<Map<String, dynamic>?> _post(String endpoint, Map<String, dynamic> body) async {
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse('$_baseUrl / $endpoint'.replaceAll(' ', ''));
      final response = await http.post(uri, headers: headers, body: jsonEncode(body));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        LogService.instance.registerLog('POST $endpoint failed: ${response.body}');
        return null;
      }
    } catch (e) {
      LogService.instance.registerLog('Error on POST $endpoint: $e');
      return null;
    }
  }

  /// Fetch courts, optionally filtered by Sports Center GUID
  Future<List<Map<String, dynamic>>?> fetchCourts({String? sportsCenterGuid}) async {
    final endpoint = sportsCenterGuid != null
        ? 'courts?sportsCenterGuid=$sportsCenterGuid'
        : 'courts';
    final response = await _get(endpoint);

    if (response != null && response['\$values'] != null) {
      final parsedList = List<Map<String, dynamic>>.from(response['\$values']);
      LogService.instance.registerLog('Parsed list (courts): $parsedList');
      return parsedList;
    } else {
      LogService.instance.registerLog('Unexpected structure (courts): $response');
      return null;
    }
  }

  /// Fetch sports centers
  Future<List<Map<String, dynamic>>?> fetchSportsCenters() async {
    final response = await _get('sportscenters');

    if (response != null && response['\$values'] != null) {
      final parsedList = List<Map<String, dynamic>>.from(response['\$values']);
      LogService.instance.registerLog('Parsed list (sportscenters): $parsedList');
      return parsedList;
    } else {
      LogService.instance.registerLog('Unexpected structure (sportscenters): $response');
      return null;
    }
  }

  /// Fetch sessions for a court
  Future<List<Map<String, dynamic>>?> fetchSessions(String courtGuid) async {
    final response = await _get('sessions?courtGuid=$courtGuid');

    if (response != null && response['\$values'] != null) {
      final parsedList = List<Map<String, dynamic>>.from(response['\$values']);
      LogService.instance.registerLog('Parsed list (sessions): $parsedList');
      return parsedList;
    } else {
      LogService.instance.registerLog('Unexpected structure (sessions): $response');
      return null;
    }
  }

  /// Notify server that device is ready to transmit
  Future<bool> notifyReadyToTransmit(String deviceId, String sessionGuid) async {
    try {
      final response = await _post(
        'device/ReadyToTransmit',
        {
          'DeviceId': deviceId,
          'SessionGuid': sessionGuid,
        },
      );

      if (response != null) {
        LogService.instance.registerLog('Notified API that the device is ready to transmit');
        return true;
      } else {
        LogService.instance.registerLog('Failed to notify server: No response');
        return false;
      }
    } catch (e) {
      LogService.instance.registerLog('Error notifying server: $e');
      return false;
    }
  }


  /// Create a new capture session
  Future<Map<String, dynamic>?> createSession(String sessionId,
      {String? courtGuid, String? userGuid}) async {
    final body = {
      'SessionId': sessionId,
      'StartTime': DateTime.now().toIso8601String(),
    };
    if (courtGuid != null) body['CourtGuid'] = courtGuid;
    if (userGuid != null) body['UserGuid'] = userGuid;

    return await _post('sessions/create', body);
  }

  /// End a session
  Future<bool> endSession(String sessionGuid) async {
    final response = await _post('sessions/end', {'sessionGuid': sessionGuid});
    return response != null;
  }

  /// Upload media
  Future<bool> uploadMedia(
      String sessionGuid,
      File file,
      bool isPhoto,
      String slaveDeviceId,
      DateTime captureDate,
      DateTime receivedDate,
      Function(double)? onProgress,
      ) async {
    try {

      final headers = await _getHeaders();
      final uri = Uri.parse(
          '$_baseUrl/sessions/upload-media?sessionGuid=$sessionGuid&isPhoto=$isPhoto');

      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(headers);

      // Add fields
      request.fields['slaveDeviceId'] = slaveDeviceId;
      request.fields['captureDate'] = captureDate.toIso8601String();
      request.fields['receivedDate'] = receivedDate.toIso8601String();

      final fileLength = await file.length();
      int uploadedBytes = 0;

      request.files.add(
        http.MultipartFile(
          'files',
          file.openRead().transform(
            StreamTransformer<List<int>, List<int>>.fromHandlers(
              handleData: (chunk, sink) {
                uploadedBytes += chunk.length;
                onProgress?.call(uploadedBytes / fileLength);
                sink.add(chunk);
              },
            ),
          ),
          fileLength,
          filename: file.path.split('/').last,
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        LogService.instance.registerLog('Media uploaded successfully');
        return true;
      } else {
        LogService.instance.registerLog('Failed to upload media: ${response.body}');
        return false;
      }
    } catch (e) {
      LogService.instance.registerLog('Error uploading media: $e');
      return false;
    }
  }

  /// Get user GUID by email
  Future<String?> getUserGuidByEmail(String email) async {
    final response = await _get('users/get-by-email?email=$email');
    return response?['guid'];
  }
}
