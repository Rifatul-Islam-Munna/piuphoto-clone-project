import 'package:flutter/services.dart';
import 'package:mobileapp/core/platform/otg_file_picker.dart';

/// The photo selection for one USB shooting session. The selected mode is
/// fixed when the session starts; both modes keep listening for new shots.
enum LiveCameraUploadMode { newShotsOnly, existingAndNew }

class LiveCameraSession {
  const LiveCameraSession({
    required this.id,
    required this.cameraId,
    required this.name,
    required this.physicalShutter,
    required this.message,
    required this.baselineCount,
    this.uploadMode = LiveCameraUploadMode.newShotsOnly,
    this.usesPhotoCatalog = false,
  });

  final String id;
  final String cameraId;
  final String name;
  final String physicalShutter;
  final String message;
  final int baselineCount;
  final LiveCameraUploadMode uploadMode;

  /// This describes the actual reader, including automatic recovery after PTP.
  final bool usesPhotoCatalog;

  factory LiveCameraSession.fromMap(
    Map<Object?, Object?> data, {
    bool usesPhotoCatalog = false,
  }) {
    final id = data['sessionId']?.toString() ?? '';
    if (id.isEmpty) {
      throw PlatformException(code: 'LIVE_CAMERA_INVALID_SESSION');
    }
    return LiveCameraSession(
      id: id,
      cameraId: data['cameraId']?.toString() ?? '',
      name: data['name']?.toString() ?? 'USB camera',
      physicalShutter: data['physicalShutter'] == 'supported'
          ? 'supported'
          : 'unknown',
      message:
          data['message']?.toString() ?? 'Take a test photo on the camera.',
      baselineCount: int.tryParse('${data['baselineCount']}') ?? 0,
      usesPhotoCatalog: usesPhotoCatalog,
      uploadMode: data['uploadMode'] == LiveCameraUploadMode.existingAndNew.name
          ? LiveCameraUploadMode.existingAndNew
          : LiveCameraUploadMode.newShotsOnly,
    );
  }
}

class LiveCameraEvent {
  const LiveCameraEvent({
    required this.sessionId,
    required this.type,
    this.message = '',
    this.code,
  });

  final String sessionId;
  final String type;
  final String message;
  final String? code;

  factory LiveCameraEvent.fromMap(Map<Object?, Object?> data) =>
      LiveCameraEvent(
        sessionId: data['sessionId']?.toString() ?? '',
        type: data['type']?.toString() ?? '',
        message: data['message']?.toString() ?? '',
        code: data['code']?.toString(),
      );
}

abstract interface class LiveCameraTransport {
  Stream<LiveCameraEvent> eventsForSession(String sessionId);
  Future<LiveCameraSession> start(String sessionId);
  Future<void> stop(String sessionId);
  Future<List<ConnectedCameraImage>> pending(String sessionId);
  Future<OtgPickedFile> download(String sessionId, String imageId);
  Future<void> acknowledge(String sessionId, List<String> imageIds);
}
