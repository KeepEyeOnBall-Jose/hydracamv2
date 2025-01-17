import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'log_service.dart';
import 'auth0_m2m_service.dart';

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
    final token = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6Ik9EZzFNa015UVRneU1UazVRVGsxUXpnMlFqTTRSakkyUkRZNU16ZzBNa0U1T1VOQk1qQTJNUSJ9.eyJpc3MiOiJodHRwczovL2tlZXBleWVvbmJhbGwuZXUuYXV0aDAuY29tLyIsInN1YiI6IlpFbU9FU1RsN2dSa1Z2NVFaaXAyMXVZdkNqbkdhZ3kxQGNsaWVudHMiLCJhdWQiOiJodHRwczovL2h5ZHJhY2FtL2FwaSIsImlhdCI6MTczNzExMDY1MCwiZXhwIjoxNzM3MTk3MDUwLCJzY29wZSI6ImNyZWF0ZTpzZXNzaW9ucyBlbmQ6c2Vzc2lvbnMgdXBsb2FkOm1lZGlhIHJlYWQ6c3BvcnRzY2VudGVycyByZWFkOmNvdXJ0cyByZWFkOnVzZXJzIiwiZ3R5IjoiY2xpZW50LWNyZWRlbnRpYWxzIiwiYXpwIjoiWkVtT0VTVGw3Z1JrVnY1UVppcDIxdVl2Q2puR2FneTEiLCJwZXJtaXNzaW9ucyI6WyJjcmVhdGU6c2Vzc2lvbnMiLCJlbmQ6c2Vzc2lvbnMiLCJ1cGxvYWQ6bWVkaWEiLCJyZWFkOnNwb3J0c2NlbnRlcnMiLCJyZWFkOmNvdXJ0cyIsInJlYWQ6dXNlcnMiXX0.lhvXDaayYjE1-jbkgJTPfdquz1h9MdOOs_035EKNA6LTKJA0OWkVB_-PX65BPdgQe3H-Obq_x1kfSks1GZ8_bg7gVRSmvg7oZedxpdFxUByVmjmVPQqLKEJszGb2vWcmSs_YnCcIfDSwSmZlC7huHUcSABwGGFHtadl3p-wGSMkfOc4HLP9JV_0OePLUAY1okDmDoohlmQ8aVCYxX91c3SPHEbLA9xstd311sPcc5Km4m5LkC-EJ3mf_Wb2PWz6MHXkY-Q0PAwxOhI_LdfznwWyE-OPIU3jqQ7uzqOBDhszJvmJNNBN4DT_CXR0p4QvIhVWxeg_OxWfPtGr4VjN3HA";
    //await M2MAuthService().getToken();
    if (token == null) {
      throw Exception("Failed to retrieve M2M token");
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Generic GET request with headers and parsing
  Future<dynamic> _get(String endpoint) async {
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse('$_baseUrl/$endpoint'.replaceAll(' ', ''));
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);

        // Debug: Print response details
        print('Debug: Response from $endpoint: $decoded');

        if (decoded is List) {
          // Return list directly if response is a JSON array
          return decoded;
        } else if (decoded is Map) {
          // Return map if response is a JSON object
          return decoded;
        } else {
          // Log unexpected structure
          LogService.instance.registerLog('Unexpected JSON structure: $decoded');
          return null;
        }
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

    if (response is List) {
      // Parse the list of sports centers
      final parsedList = List<Map<String, dynamic>>.from(response);
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
  /// Create a new capture session
  Future<Map<String, dynamic>?> createSession(String sessionId,
      {String? courtGuid, String? userGuid}) async {
    try {
      // Construct the endpoint with optional query parameters
      String endpoint = 'sessions/create';
      if (courtGuid != null || userGuid != null) {
        final queryParameters = <String, String>{};
        if (courtGuid != null) queryParameters['courtGuid'] = courtGuid;
        if (userGuid != null) queryParameters['userGuid'] = userGuid;

        endpoint += '?${Uri(queryParameters: queryParameters).query}';
      }

      // Prepare the request body
      final body = {
        'SessionId': sessionId,
        'StartTime': DateTime.now().toIso8601String(),
      };

      // Debug: Print request details
      print('Debug: Sending POST request to endpoint: $_baseUrl/$endpoint');
      final headers = await _getHeaders();
      print('Debug: Request headers: $headers');
      print('Debug: Request body: $body');

      // Make the POST request
      final uri = Uri.parse('$_baseUrl/$endpoint');
      final response = await http.post(uri, headers: headers, body: jsonEncode(body));

      // Debug: Print response details
      print('Debug: Response Status Code: ${response.statusCode}');
      print('Debug: Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        print('Debug: Session created successfully.');
        print('Debug: Response Data: $responseData');
        LogService.instance.registerLog('Session created successfully: $responseData');
        return responseData;
      } else {
        print('Debug: Failed to create session. Status Code: ${response.statusCode}');
        LogService.instance.registerLog('Failed to create session: ${response.body}');
        return null;
      }
    } catch (e) {
      // Debug: Catch and print errors
      print('Debug: Error occurred during createSession: $e');
      LogService.instance.registerLog('Error creating session: $e');
      return null;
    }
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
