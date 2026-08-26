part of "../hydracam_api_service.dart";

/// Backend client for media upload: the legacy/bridge multipart upload path,
/// the media-timeline direct object-storage path, upload token acquisition,
/// and the local media signature/validation checks that gate every send.
class HydraCamMediaUploadClient {
  HydraCamMediaUploadClient(this._core);

  final HydraCamApiHttpCore _core;

  static const String _legacyUploadSuccessBody = "Media uploaded successfully.";
  static const Set<String> _photoIsoBaseMediaBrands = {
    "heic",
    "heix",
    "hevc",
    "hevx",
    "mif1",
    "msf1",
  };
  static const Set<String> _videoIsoBaseMediaBrands = {
    "3gp4",
    "avc1",
    "isom",
    "iso2",
    "M4A ",
    "M4V ",
    "mp41",
    "mp42",
    "qt  ",
  };

  Future<HydraCamDirectUploadStart?> startBridgeDirectUpload({
    required String sessionGuid,
    required String uploadToken,
    required String filename,
    required bool isPhoto,
    required String deviceId,
    DateTime? capturedAt,
    DateTime? receivedAt,
    int? sizeBytes,
    String? mimeType,
  }) async {
    final normalizedSessionGuid = _normalizedUploadSessionGuid(sessionGuid);
    final normalizedUploadToken = _optionalString(uploadToken);
    final normalizedFilename = _optionalString(filename);
    if (normalizedSessionGuid == null ||
        normalizedUploadToken == null ||
        normalizedFilename == null) {
      LogService.instance.registerLog(
          "Cannot start bridge direct upload: missing session, token, or filename.");
      return null;
    }

    final deviceIdForUpload = _optionalString(deviceId);
    final mimeTypeForUpload = _optionalString(mimeType);
    final endpoint =
        hydracamBridgeDirectUploadStartEndpoint(normalizedSessionGuid);
    final uri = _core._apiUri(
      endpoint,
      backendMode: HydraCamApiBackendMode.mediaTimelineBridge,
    );
    final body = <String, dynamic>{
      "filename": normalizedFilename,
      "kind": isPhoto ? "photo" : "video",
      if (deviceIdForUpload != null) "deviceId": deviceIdForUpload,
      if (capturedAt != null)
        "capturedAt": capturedAt.toUtc().toIso8601String(),
      if (receivedAt != null)
        "receivedAt": receivedAt.toUtc().toIso8601String(),
      if (sizeBytes != null) "size": sizeBytes,
      if (mimeTypeForUpload != null) "mimeType": mimeTypeForUpload,
    };

    for (var attempt = 1;; attempt += 1) {
      try {
        final response = await _core._httpClient.post(
          uri,
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $normalizedUploadToken",
          },
          body: jsonEncode(body),
        );

        if (response.statusCode != 200) {
          LogService.instance.registerLog(
              "Failed to start bridge direct upload: ${response.body}");
          return null;
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! Map) {
          LogService.instance.registerLog(
              "Failed to start bridge direct upload: unexpected response $decoded");
          return null;
        }
        return HydraCamDirectUploadStart.fromJson(_asStringKeyedMap(decoded));
      } catch (e) {
        if (_core._shouldRetryMediaTimelineBridgeRequest(
          backendMode: HydraCamApiBackendMode.mediaTimelineBridge,
          attempt: attempt,
          error: e,
        )) {
          LogService.instance.registerLog(
            "Retrying media-timeline bridge direct upload start after transient "
            "failure (attempt $attempt/${_core._mediaTimelineBridgeRetryMaxAttempts}): $e",
          );
          await _core._waitBeforeMediaTimelineBridgeRetry(attempt);
          continue;
        }
        LogService.instance
            .registerLog("Error starting bridge direct upload: $e");
        return null;
      }
    }
  }

  Future<bool> _uploadMediaViaMediaTimelineDirectStorage({
    required String sessionGuid,
    required String uploadToken,
    required File file,
    required bool isPhoto,
    required String slaveDeviceId,
    required DateTime captureDate,
    required DateTime receivedDate,
    required int fileLength,
    required Duration? effectiveVideoDuration,
    required Function(double)? onProgress,
    required Function(HydraCamUploadResult)? onUploadResult,
  }) async {
    try {
      final filename = file.path.split("/").last;
      final contentType = _uploadMediaContentType(file, isPhoto: isPhoto);
      final directStart = await startBridgeDirectUpload(
        sessionGuid: sessionGuid,
        uploadToken: uploadToken,
        filename: filename,
        isPhoto: isPhoto,
        deviceId: slaveDeviceId,
        capturedAt: captureDate,
        receivedAt: receivedDate,
        sizeBytes: fileLength,
        mimeType: contentType.toString(),
      );
      if (directStart == null ||
          directStart.preferredStorage != "object-storage") {
        return false;
      }

      final multipartStart = await _startMediaStorageMultipartUpload(
        path: directStart.mediaStorage.startPath,
        filename: filename,
        contentType: contentType.toString(),
        eventId: directStart.eventId,
      );
      if (multipartStart == null) {
        return false;
      }

      final uploadedPart = await _uploadMediaStorageMultipartPart(
        path: directStart.mediaStorage.uploadPartPath,
        multipartStart: multipartStart,
        file: file,
        fileLength: fileLength,
        onProgress: onProgress,
      );
      if (uploadedPart == null) {
        return false;
      }

      final storageComplete = await _completeMediaStorageMultipartUpload(
        path: directStart.mediaStorage.completeObjectPath,
        multipartStart: multipartStart,
        uploadedPart: uploadedPart,
        filename: filename,
        isPhoto: isPhoto,
      );
      if (storageComplete == null) {
        return false;
      }

      final bridgeComplete = await _completeBridgeDirectUpload(
        path: directStart.mediaStorage.completeBridgePath,
        uploadToken: uploadToken,
        sessionGuid: sessionGuid,
        fileId: storageComplete.fileId,
        locator: storageComplete.locator,
        filename: filename,
        isPhoto: isPhoto,
        slaveDeviceId: slaveDeviceId,
        captureDate: captureDate,
        receivedDate: receivedDate,
        fileLength: fileLength,
        effectiveVideoDuration: effectiveVideoDuration,
        mimeType: contentType.toString(),
      );
      if (bridgeComplete == null) {
        return false;
      }

      onUploadResult?.call(
        HydraCamUploadResult(
          eventId: bridgeComplete.eventId,
          sessionGuid: sessionGuid,
          files: [
            HydraCamUploadFileResult(
              fileId: bridgeComplete.fileId,
              filename: filename,
              kind: isPhoto ? "photo" : "video",
              eventId: bridgeComplete.eventId,
              sessionGuid: sessionGuid,
              storage: "object-storage",
            ),
          ],
        ),
      );
      LogService.instance
          .registerLog("Media uploaded through media-timeline object storage");
      return true;
    } catch (e) {
      LogService.instance
          .registerLog("Direct media-timeline object upload failed: $e");
      return false;
    }
  }

  Future<_MediaStorageMultipartStart?> _startMediaStorageMultipartUpload({
    required String path,
    required String filename,
    required String contentType,
    required String eventId,
  }) async {
    final response = await _core._postMediaTimelineJson(
      _core._mediaTimelineApiPathUri(path),
      {
        "filename": filename,
        "contentType": contentType,
        "eventId": eventId,
      },
    );
    if (response == null) {
      return null;
    }
    return _MediaStorageMultipartStart.fromJson(response);
  }

  Future<_MediaStorageUploadedPart?> _uploadMediaStorageMultipartPart({
    required String path,
    required _MediaStorageMultipartStart multipartStart,
    required File file,
    required int fileLength,
    required Function(double)? onProgress,
  }) async {
    final uri = _core._mediaTimelineApiPathUri(
      path,
      queryParameters: {
        "key": multipartStart.key,
        "uploadId": multipartStart.uploadId,
        "partNumber": "1",
      },
    );
    for (var attempt = 1;; attempt += 1) {
      try {
        var uploadedBytes = 0;
        final request = http.StreamedRequest("PUT", uri)
          ..headers["Content-Type"] = "application/octet-stream"
          ..contentLength = fileLength;
        final streamedResponseFuture = _core._httpClient.send(request);
        await request.sink.addStream(
          file.openRead().transform(
            StreamTransformer.fromHandlers(
              handleData: (chunk, sink) {
                uploadedBytes += chunk.length;
                onProgress?.call(uploadedBytes / fileLength);
                sink.add(chunk);
              },
            ),
          ),
        );
        await request.sink.close();
        final streamedResponse = await streamedResponseFuture;
        final response = await http.Response.fromStream(streamedResponse);
        if (response.statusCode != 200) {
          LogService.instance.registerLog(
              "Media storage part upload failed: ${response.body}");
          return null;
        }
        return _MediaStorageUploadedPart.fromJson(
          _asStringKeyedMap(jsonDecode(response.body)),
        );
      } catch (e) {
        if (_core._shouldRetryMediaTimelineBridgeRequest(
          backendMode: HydraCamApiBackendMode.mediaTimelineBridge,
          attempt: attempt,
          error: e,
        )) {
          LogService.instance.registerLog(
            "Retrying media-storage part upload after transient failure "
            "(attempt $attempt/${_core._mediaTimelineBridgeRetryMaxAttempts}): $e",
          );
          await _core._waitBeforeMediaTimelineBridgeRetry(attempt);
          continue;
        }
        LogService.instance.registerLog("Media storage part upload failed: $e");
        return null;
      }
    }
  }

  Future<_MediaStorageComplete?> _completeMediaStorageMultipartUpload({
    required String path,
    required _MediaStorageMultipartStart multipartStart,
    required _MediaStorageUploadedPart uploadedPart,
    required String filename,
    required bool isPhoto,
  }) async {
    final response = await _core._postMediaTimelineJson(
      _core._mediaTimelineApiPathUri(path),
      {
        "key": multipartStart.key,
        "uploadId": multipartStart.uploadId,
        "filename": filename,
        "kind": isPhoto ? "photo" : "video",
        "parts": [uploadedPart.toJson()],
      },
    );
    if (response == null) {
      return null;
    }
    return _MediaStorageComplete.fromJson(response);
  }

  Future<_HydraCamBridgeCompletedUpload?> _completeBridgeDirectUpload({
    required String path,
    required String uploadToken,
    required String sessionGuid,
    required String fileId,
    required String locator,
    required String filename,
    required bool isPhoto,
    required String slaveDeviceId,
    required DateTime captureDate,
    required DateTime receivedDate,
    required int fileLength,
    required Duration? effectiveVideoDuration,
    required String mimeType,
  }) async {
    final response = await _core._postMediaTimelineJson(
      _core._mediaTimelineApiPathUri(path),
      {
        "fileId": fileId,
        "locator": locator,
        "metadata": {
          "sessionGuid": sessionGuid,
          "deviceId": slaveDeviceId,
          "filename": filename,
          "kind": isPhoto ? "photo" : "video",
          "mimeType": mimeType,
          "sourceBytes": fileLength,
          "capturedAt": captureDate.toUtc().toIso8601String(),
          "receivedAt": receivedDate.toUtc().toIso8601String(),
          if (effectiveVideoDuration != null)
            "durationSeconds": effectiveVideoDuration.inMilliseconds / 1000,
        },
      },
      headers: {
        "Authorization": "Bearer $uploadToken",
      },
    );
    if (response == null) {
      return null;
    }
    return _HydraCamBridgeCompletedUpload.fromJson(response);
  }

  /// Upload media
  Future<bool> uploadMedia(
    String sessionGuid,
    File file,
    bool isPhoto,
    String slaveDeviceId,
    DateTime captureDate,
    DateTime receivedDate,
    Function(double)? onProgress, {
    DateTime? recordingEndDate,
    Duration? recordingDuration,
    String? mediaTimelineUploadToken,
    Function(String)? onFailureReason,
    Function(HydraCamUploadResult)? onUploadResult,
  }) async {
    try {
      final normalizedSessionGuid = _normalizedUploadSessionGuid(sessionGuid);
      if (normalizedSessionGuid == null) {
        final failureReason =
            "Upload session GUID is invalid: ${_invalidSessionGuidLabel(sessionGuid)}";
        return _failUpload(
          failureReason,
          onFailureReason: onFailureReason,
          mediaFailureReason: "Upload failed: $failureReason",
        );
      }

      if (!file.existsSync()) {
        return _failUpload(
          "Upload file does not exist: ${file.path}",
          onFailureReason: onFailureReason,
          mediaFailureReason:
              "Upload failed: file does not exist: ${file.path}",
        );
      }

      final fileLength = await file.length();
      if (fileLength == 0) {
        return _failUpload(
          "Upload file is empty: ${file.path}",
          onFailureReason: onFailureReason,
          mediaFailureReason: "Upload failed: file is empty: ${file.path}",
        );
      }

      final validationFailure = await _uploadMediaValidationFailure(
        file: file,
        isPhoto: isPhoto,
      );
      if (validationFailure != null) {
        return _failUpload(
          validationFailure,
          onFailureReason: onFailureReason,
          mediaFailureReason: "Upload failed: $validationFailure",
        );
      }

      final Duration? effectiveVideoDuration;
      if (isPhoto) {
        effectiveVideoDuration = null;
      } else {
        effectiveVideoDuration =
            recordingEndDate?.difference(captureDate) ?? recordingDuration;
        if (effectiveVideoDuration != null &&
            effectiveVideoDuration.isNegative) {
          final failureReason =
              "Upload video duration is invalid: recordingEndDate is before captureDate for ${file.path}";
          return _failUpload(
            failureReason,
            onFailureReason: onFailureReason,
            mediaFailureReason: "Upload failed: $failureReason",
          );
        }
      }

      final backendMode = _core._backendMode;
      if (backendMode == HydraCamApiBackendMode.mediaTimelineBridge &&
          _optionalString(mediaTimelineUploadToken) != null) {
        final directUploadSucceeded =
            await _uploadMediaViaMediaTimelineDirectStorage(
          sessionGuid: normalizedSessionGuid,
          uploadToken: mediaTimelineUploadToken!,
          file: file,
          isPhoto: isPhoto,
          slaveDeviceId: slaveDeviceId,
          captureDate: captureDate,
          receivedDate: receivedDate,
          fileLength: fileLength,
          effectiveVideoDuration: effectiveVideoDuration,
          onProgress: onProgress,
          onUploadResult: onUploadResult,
        );
        if (directUploadSucceeded) {
          return true;
        }
        LogService.instance.registerLog(
          "Falling back to media-timeline bridge compatibility upload.",
        );
      }

      final headers = backendMode == HydraCamApiBackendMode.legacyMobo
          ? await _core._getHeaders()
          : <String, String>{};
      final appMetadata = await _getUploadAppMetadata();
      final uri = _core._apiUri(
        hydracamApiEndpoint(
          _core._uploadMediaEndpoint,
          queryParameters: {
            HydraCamUploadMediaContract.querySessionGuid: normalizedSessionGuid,
            HydraCamUploadMediaContract.queryIsPhoto: isPhoto.toString(),
          },
        ),
        backendMode: backendMode,
      );

      Future<http.Response> sendUploadAttempt() async {
        final request = http.MultipartRequest(
          HydraCamUploadMediaContract.method,
          uri,
        )
          ..headers.addAll(headers)
          ..fields[HydraCamUploadMediaContract.fieldSlaveDeviceId] =
              slaveDeviceId
          ..fields[HydraCamUploadMediaContract.fieldCaptureDate] =
              captureDate.toUtc().toIso8601String()
          ..fields[HydraCamUploadMediaContract.fieldReceivedDate] =
              receivedDate.toUtc().toIso8601String()
          ..fields.addAll(appMetadata);

        if (!isPhoto) {
          if (recordingEndDate != null) {
            request.fields[HydraCamUploadMediaContract.fieldRecordingEndDate] =
                recordingEndDate.toUtc().toIso8601String();
          }
          if (effectiveVideoDuration != null) {
            request.fields[HydraCamUploadMediaContract.fieldDurationMs] =
                effectiveVideoDuration.inMilliseconds.toString();
          }
        }

        int uploadedBytes = 0;

        request.files.add(
          http.MultipartFile(
            HydraCamUploadMediaContract.fileField,
            file.openRead().transform(
              StreamTransformer.fromHandlers(
                handleData: (chunk, sink) {
                  uploadedBytes += chunk.length;
                  onProgress?.call(uploadedBytes / fileLength);
                  sink.add(chunk);
                },
              ),
            ),
            fileLength,
            filename: file.path.split("/").last,
            contentType: _uploadMediaContentType(file, isPhoto: isPhoto),
          ),
        );

        final streamedResponse = await _core._httpClient.send(request);
        return http.Response.fromStream(streamedResponse);
      }

      late final http.Response response;
      for (var attempt = 1;; attempt += 1) {
        try {
          response = await sendUploadAttempt();
          break;
        } catch (e) {
          if (_core._shouldRetryMediaTimelineBridgeRequest(
            backendMode: backendMode,
            attempt: attempt,
            error: e,
          )) {
            LogService.instance.registerLog(
              "Retrying media-timeline bridge upload after transient failure "
              "(attempt $attempt/${_core._mediaTimelineBridgeRetryMaxAttempts}): $e",
            );
            await _core._waitBeforeMediaTimelineBridgeRetry(attempt);
            continue;
          }
          return _failUpload(
            "Error uploading media: $e",
            onFailureReason: onFailureReason,
            mediaFailureReason: "Upload failed: $e",
          );
        }
      }

      if (response.statusCode ==
          HydraCamUploadMediaContract.successStatusCode) {
        if (_uploadResponseReportsFailure(response.body)) {
          final failureReason =
              "HTTP ${response.statusCode} backend response reported failure - ${_core._uploadFailureResponseBodySnippet(response.body)}";
          return _failUpload(
            "Failed to upload media: $failureReason",
            onFailureReason: onFailureReason,
            mediaFailureReason: "Upload failed: $failureReason",
          );
        }
        _notifyUploadResult(response.body, onUploadResult);
        LogService.instance.registerLog("Media uploaded successfully");
        return true;
      } else {
        final failureReason =
            "HTTP ${response.statusCode} - ${_core._uploadFailureResponseBodySnippet(response.body)}";
        return _failUpload(
          "Failed to upload media: $failureReason",
          onFailureReason: onFailureReason,
          mediaFailureReason: "Upload failed: $failureReason",
        );
      }
    } catch (e) {
      return _failUpload(
        "Error uploading media: $e",
        onFailureReason: onFailureReason,
        mediaFailureReason: "Upload failed: $e",
      );
    }
  }

  String? _normalizedUploadSessionGuid(String sessionGuid) {
    final normalizedSessionGuid = sessionGuid.trim();
    final lowerSessionGuid = normalizedSessionGuid.toLowerCase();
    if (normalizedSessionGuid.isEmpty ||
        lowerSessionGuid.startsWith("local-") ||
        lowerSessionGuid == "null" ||
        lowerSessionGuid == "undefined") {
      return null;
    }
    return normalizedSessionGuid;
  }

  String _invalidSessionGuidLabel(String sessionGuid) {
    final normalizedSessionGuid = sessionGuid.trim();
    return normalizedSessionGuid.isEmpty ? "<blank>" : normalizedSessionGuid;
  }

  bool _failUpload(
    String logMessage, {
    Function(String)? onFailureReason,
    String? mediaFailureReason,
  }) {
    LogService.instance.registerLog(logMessage);
    onFailureReason?.call(mediaFailureReason ?? logMessage);
    return false;
  }

  Future<String?> _uploadMediaValidationFailure({
    required File file,
    required bool isPhoto,
  }) async {
    final header = await _readFileHeader(file, 16);
    final isValidMedia = isPhoto
        ? _hasPhotoMediaSignature(header)
        : _hasVideoMediaSignature(header);
    if (isValidMedia) {
      return null;
    }

    final mediaType = isPhoto ? "photo" : "video";
    return "Upload file is not valid $mediaType media: ${file.path}";
  }

  MediaType _uploadMediaContentType(File file, {required bool isPhoto}) {
    if (!isPhoto) {
      return MediaType("video", "mp4");
    }

    final extension = file.path.split(".").last.toLowerCase();
    if (extension == "png") {
      return MediaType("image", "png");
    }
    if (extension == "heic" || extension == "heif") {
      return MediaType("image", "heic");
    }
    return MediaType("image", "jpeg");
  }

  Future<List<int>> _readFileHeader(File file, int byteCount) async {
    final randomAccessFile = await file.open();
    try {
      return await randomAccessFile.read(byteCount);
    } finally {
      await randomAccessFile.close();
    }
  }

  bool _hasPhotoMediaSignature(List<int> header) {
    return _hasJpegSignature(header) ||
        _hasPngSignature(header) ||
        _hasIsoBaseMediaSignature(header, _photoIsoBaseMediaBrands);
  }

  bool _hasVideoMediaSignature(List<int> header) {
    return _hasIsoBaseMediaSignature(header, _videoIsoBaseMediaBrands);
  }

  bool _hasJpegSignature(List<int> header) {
    return header.length >= 2 && header[0] == 0xff && header[1] == 0xd8;
  }

  bool _hasPngSignature(List<int> header) {
    const pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    if (header.length < pngSignature.length) {
      return false;
    }
    for (var index = 0; index < pngSignature.length; index += 1) {
      if (header[index] != pngSignature[index]) {
        return false;
      }
    }
    return true;
  }

  bool _hasIsoBaseMediaSignature(
    List<int> header,
    Set<String> supportedMajorBrands,
  ) {
    if (header.length < 12 ||
        header[4] != 0x66 ||
        header[5] != 0x74 ||
        header[6] != 0x79 ||
        header[7] != 0x70) {
      return false;
    }

    final majorBrand = String.fromCharCodes(header.sublist(8, 12));
    return supportedMajorBrands.contains(majorBrand);
  }

  bool _uploadResponseReportsFailure(String responseBody) {
    final trimmedBody = responseBody.trim();
    if (trimmedBody.isEmpty) {
      return false;
    }
    if (trimmedBody == _legacyUploadSuccessBody) {
      return false;
    }

    try {
      final decoded = jsonDecode(trimmedBody);
      if (decoded is! Map) {
        return true;
      }

      final decodedMap =
          decoded.map((key, value) => MapEntry(key.toString(), value));
      return _core._responseMapReportsFailure(decodedMap);
    } catch (e) {
      LogService.instance
          .registerLog("Malformed upload response body: $trimmedBody ($e)");
      return true;
    }
  }

  void _notifyUploadResult(
    String responseBody,
    Function(HydraCamUploadResult)? onUploadResult,
  ) {
    if (onUploadResult == null) {
      return;
    }

    final trimmedBody = responseBody.trim();
    if (trimmedBody.isEmpty || trimmedBody == _legacyUploadSuccessBody) {
      return;
    }

    try {
      final decoded = jsonDecode(trimmedBody);
      if (decoded is Map) {
        onUploadResult(
          HydraCamUploadResult.fromJson(_asStringKeyedMap(decoded)),
        );
      }
    } catch (e) {
      LogService.instance
          .registerLog("Upload identity metadata unavailable: $e");
    }
  }

  Future<Map<String, String>> _getUploadAppMetadata() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return {
        HydraCamUploadMediaContract.fieldAppVersion: packageInfo.version,
        HydraCamUploadMediaContract.fieldAppBuildNumber:
            packageInfo.buildNumber,
      };
    } catch (e) {
      LogService.instance
          .registerLog("App version metadata unavailable for upload: $e");
      return {};
    }
  }
}

class _MediaStorageMultipartStart {
  const _MediaStorageMultipartStart({
    required this.key,
    required this.uploadId,
    required this.locator,
  });

  final String key;
  final String uploadId;
  final String locator;

  factory _MediaStorageMultipartStart.fromJson(Map<String, dynamic> json) {
    return _MediaStorageMultipartStart(
      key: _requiredString(json["key"], "key"),
      uploadId: _requiredString(json["uploadId"], "uploadId"),
      locator: _requiredString(json["locator"], "locator"),
    );
  }
}

class _MediaStorageUploadedPart {
  const _MediaStorageUploadedPart({
    required this.partNumber,
    required this.eTag,
  });

  final int partNumber;
  final String eTag;

  Map<String, dynamic> toJson() {
    return {
      "PartNumber": partNumber,
      "ETag": eTag,
    };
  }

  factory _MediaStorageUploadedPart.fromJson(Map<String, dynamic> json) {
    final rawPartNumber = json["PartNumber"] ?? json["partNumber"];
    final partNumber = rawPartNumber is int
        ? rawPartNumber
        : int.tryParse(rawPartNumber?.toString() ?? "");
    if (partNumber == null || partNumber < 1) {
      throw const FormatException(
          "Upload part response is missing PartNumber.");
    }
    return _MediaStorageUploadedPart(
      partNumber: partNumber,
      eTag: _requiredString(json["ETag"] ?? json["etag"], "ETag"),
    );
  }
}

class _MediaStorageComplete {
  const _MediaStorageComplete({
    required this.locator,
    required this.fileId,
  });

  final String locator;
  final String fileId;

  factory _MediaStorageComplete.fromJson(Map<String, dynamic> json) {
    final registered = _asStringKeyedMap(json["registered"]);
    return _MediaStorageComplete(
      locator: _requiredString(json["locator"], "locator"),
      fileId: _requiredString(registered["fileId"], "registered.fileId"),
    );
  }
}

class _HydraCamBridgeCompletedUpload {
  const _HydraCamBridgeCompletedUpload({
    required this.eventId,
    required this.fileId,
  });

  final String eventId;
  final String fileId;

  factory _HydraCamBridgeCompletedUpload.fromJson(Map<String, dynamic> json) {
    return _HydraCamBridgeCompletedUpload(
      eventId: _requiredString(json["eventId"], "eventId"),
      fileId: _requiredString(json["fileId"], "fileId"),
    );
  }
}
