/// Bounded recovery for well-framed Sony replies only. Never retry an
/// ambiguous transfer, a transport timeout or malformed data as if successful.
class SonyErrorRecovery {
  static const recoveryRequired = 'SONY_TRANSFER_RECOVERY_REQUIRED';
  static const maxMetadataFailures = 8;
  static const capabilityAttemptsPerVersion = 20;
  static const capabilityRetryDelay = Duration(milliseconds: 150);

  static bool isBusy(int code) => code == 0x2019;
  static bool rejectsArgument(int code) =>
      const {0x2005, 0x2006, 0x201d}.contains(code);
  static bool metadataNotReady(int code) => code == 0x2009 || isBusy(code);

  static Duration startupRetryDelay(int attempt) =>
      Duration(milliseconds: (250 + attempt * 100).clamp(250, 750));

  // The next ordinary poll gets one immediate chance; repeated failures
  // back off to avoid hammering the camera during exposure/card writing.
  static Duration metadataRetryDelay(int failures) => failures <= 1
      ? Duration.zero
      : Duration(milliseconds: (250 * (1 << (failures - 2).clamp(0, 4))));

  int metadataFailures = 0;
  DateTime? metadataRetryAfter;

  bool canReadMetadata(DateTime now) =>
      metadataRetryAfter?.isAfter(now) != true;

  bool recordMetadataFailure(DateTime now) {
    metadataFailures++;
    metadataRetryAfter = now.add(metadataRetryDelay(metadataFailures));
    return metadataFailures >= maxMetadataFailures;
  }

  void resetMetadata() {
    metadataFailures = 0;
    metadataRetryAfter = null;
  }
}
