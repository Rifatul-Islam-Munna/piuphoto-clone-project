/// Sony-only timing profiles, not a list of hardware-certified cameras.
///
/// Upstream libgphoto2 camlibs/ptp2/library.c (camera_sony_capture) lists
/// these bodies as needing roughly three seconds before remote capture.
/// AirPix conservatively applies that allowance before arming passive
/// receiving. Protocol choice and shooting safety remain capability-driven.
class SonyCameraProfile {
  const SonyCameraProfile._(this.modelId, this.needsStartupGrace);

  final String modelId;
  final bool needsStartupGrace;

  static const _warmupAliases = <String, List<String>>{
    'ZV-E10': ['zve10'],
    'ZV-1': ['zv1'],
    'DSC-RX100M7': ['dscrx100m7', 'rx100m7', 'rx100vii'],
    'ILCE-7RM4': ['ilce7rm4', 'a7riv', 'a7r4'],
    'ILCE-7RM4A': ['ilce7rm4a', 'a7riva', 'a7r4a'],
    'DSC-RX0M2': ['dscrx0m2', 'rx0m2', 'rx0ii'],
    'ILCE-7M3': ['ilce7m3', 'a7iii', 'a73'],
    'ILCE-7SM3': ['ilce7sm3', 'a7siii', 'a7s3'],
    'ILCE-7M4': ['ilce7m4', 'a7iv', 'a74'],
    'ILCE-7M5': ['ilce7m5', 'a7v', 'a75'],
    'ILCE-9M2': ['ilce9m2', 'a9ii', 'a92'],
    'ILCE-1': ['ilce1', 'a1'],
    'ILCE-7C': ['ilce7c', 'a7c'],
  };

  static SonyCameraProfile forModel(String model) {
    final key = model
        .trim()
        .toLowerCase()
        .replaceAll('α', 'a')
        .replaceAll(RegExp('[^a-z0-9]'), '')
        .replaceFirst(RegExp('^sony'), '')
        .replaceFirst(RegExp('^alpha'), 'a');
    for (final entry in _warmupAliases.entries) {
      if (entry.value.contains(key)) {
        return SonyCameraProfile._(entry.key, true);
      }
    }
    // Unknown models still negotiate only the advertised PTP capabilities.
    return SonyCameraProfile._(model.trim().isEmpty ? 'Unknown' : model, false);
  }

  bool get isA7R4 => modelId == 'ILCE-7RM4' || modelId == 'ILCE-7RM4A';
  Duration get startupGrace =>
      needsStartupGrace ? const Duration(seconds: 3) : Duration.zero;
  int get startupPropertyRetries => needsStartupGrace ? 16 : 10;
  int get startupBusyRetries => needsStartupGrace ? 6 : 4;
  int get baselineChecks => needsStartupGrace ? 30 : 20;
  int get priorityConfirmationChecks => needsStartupGrace ? 12 : 8;
}
