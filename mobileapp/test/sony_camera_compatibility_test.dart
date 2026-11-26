import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/platform/sony/sony_camera_profiles.dart';
import 'package:mobileapp/core/platform/sony/sony_camera_protocol.dart';
import 'package:mobileapp/core/platform/sony/sony_diagnostics.dart';
import 'package:mobileapp/core/platform/sony/sony_error_recovery.dart';

void main() {
  test(
    'upstream documented warm-up profiles match only exact Sony model IDs',
    () {
      const models = [
        'ZV-E10',
        'ZV-1',
        'DSC-RX100M7',
        'ILCE-7RM4',
        'ILCE-7RM4A',
        'DSC-RX0M2',
        'ILCE-7M3',
        'ILCE-7SM3',
        'ILCE-7M4',
        'ILCE-7M5',
        'ILCE-9M2',
        'ILCE-1',
        'ILCE-7C',
      ];
      for (final model in models) {
        final profile = SonyCameraProfile.forModel(model);
        expect(profile.modelId, model);
        expect(profile.startupGrace, const Duration(seconds: 3));
      }
      for (final model in [
        'ILCE-7C2',
        'ILCE-1M2',
        'ZV-E10M2',
        'ILCE-7RM5',
        'Unknown',
      ]) {
        final profile = SonyCameraProfile.forModel(model);
        expect(profile.startupGrace, Duration.zero);
        expect(profile.startupPropertyRetries, 10);
      }
      expect(SonyCameraProfile.forModel('Sony Alpha 7R IV').isA7R4, isTrue);
      expect(SonyCameraProfile.forModel('Sony α7R IVA').modelId, 'ILCE-7RM4A');
      expect(SonyCameraProfile.forModel('Sony Alpha 7 IV').modelId, 'ILCE-7M4');
    },
  );

  test(
    'protocol fallback is allowed only for definitive command rejection',
    () {
      for (final code in [0x2005, 0x2006, 0x201d]) {
        expect(SonyErrorRecovery.rejectsArgument(code), isTrue);
      }
      for (final code in [0x2001, 0x2002, 0x200f, 0x2019, 0x2009]) {
        expect(SonyErrorRecovery.rejectsArgument(code), isFalse);
      }
      expect(SonyCameraProtocol.isQueueReady(1), isFalse);
      expect(SonyCameraProtocol.isQueueReady(0x8000), isFalse);
      expect(SonyCameraProtocol.isQueueReady(0x8001), isTrue);
      expect(SonyCameraProtocol.isQueueIdle(0x8000), isTrue);
    },
  );

  test(
    'metadata recovery backs off, has a finite limit and resets on success',
    () {
      final recovery = SonyErrorRecovery();
      final now = DateTime.utc(2026, 1, 1);
      expect(recovery.canReadMetadata(now), isTrue);
      for (
        var failure = 1;
        failure <= SonyErrorRecovery.maxMetadataFailures;
        failure++
      ) {
        expect(
          recovery.recordMetadataFailure(now),
          failure == SonyErrorRecovery.maxMetadataFailures,
        );
      }
      expect(recovery.canReadMetadata(now), isFalse);
      expect(
        recovery.canReadMetadata(now.add(const Duration(seconds: 5))),
        isTrue,
      );
      recovery.resetMetadata();
      expect(recovery.canReadMetadata(now), isTrue);
      expect(recovery.metadataFailures, 0);
    },
  );

  test(
    'diagnostics include only the camera identity and negotiation state',
    () {
      final diagnostics =
          SonyDiagnostics(
              profile: SonyCameraProfile.forModel('ILCE-7RM4'),
              firmware: '1.20',
              productId: 0x0ccc,
            )
            ..stage = 'readiness'
            ..protocolVersion = 0x12c
            ..parameterlessProperties = true;
      expect(diagnostics.toMap(), {
        'sonyStage': 'readiness',
        'sonyProfile': 'ILCE-7RM4',
        'sonyFirmware': '1.20',
        'sonyUsbProductId': '0x0ccc',
        'sonyProtocolVersion': 0x12c,
        'sonyPropertyQuery': 'parameterless',
      });
    },
  );
}
