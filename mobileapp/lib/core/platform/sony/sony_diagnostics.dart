import 'package:mobileapp/core/platform/sony/sony_camera_profiles.dart';

/// Per-session diagnostic state. Do not retain camera serials or image data.
class SonyDiagnostics {
  SonyDiagnostics({
    required this.profile,
    required this.firmware,
    required this.productId,
  });

  final SonyCameraProfile profile;
  final String firmware;
  final int productId;
  String stage = 'identify';
  int? protocolVersion;
  bool parameterlessProperties = false;

  Map<String, Object> toMap() => {
    'sonyStage': stage,
    'sonyProfile': profile.modelId,
    'sonyFirmware': firmware.isEmpty ? 'unknown' : firmware,
    'sonyUsbProductId': '0x${productId.toRadixString(16).padLeft(4, '0')}',
    'sonyProtocolVersion': ?protocolVersion,
    'sonyPropertyQuery': parameterlessProperties
        ? 'parameterless'
        : 'negotiated',
  };
}
