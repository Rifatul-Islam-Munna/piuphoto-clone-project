import 'package:mobileapp/core/platform/ptp_tether_codec.dart';

/// The passive Sony SDIO/PTP subset. No capture, delete or host-priority
/// commands are defined here; the native/Dart safety allowlists still apply.
abstract final class SonyCameraProtocol {
  static const queueProperty = 0xd215;
  static const destinationProperty = 0xd222;
  static const priorityProperty = 0xd25a;
  static const cameraAndHostDestination = 17;
  static const cameraPriority = 0;
  static const pcPriority = 1;
  static const ramHandle = 0xffffc001;
  static const connect = 0x9201;
  static const extensionInfo = 0x9202;
  static const readProperties = 0x9209;
  static const writeProperty = 0x9205;

  static const capabilityQueries = <List<int>>[
    [0x12c, 1],
    [0xc8],
  ];
  static const requiredProperties = [
    queueProperty,
    destinationProperty,
    priorityProperty,
  ];

  static bool supportsVersion(int version) =>
      const {2, 3, 0xc8, 0x12c}.contains(version);
  static bool isV3(int version) => version == 3 || version == 0x12c;
  static bool hasRequiredProperties(Map<int, PtpProperty> properties) =>
      requiredProperties.every((code) => properties[code]?.intValue != null);
  static bool isQueueIdle(int count) => count == 0 || count == 0x8000;
  static bool isQueueReady(int count) => count > 0x8000;
}
