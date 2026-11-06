import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mobileapp/core/platform/live_camera_types.dart';
import 'package:mobileapp/core/platform/otg_file_picker.dart';
import 'package:mobileapp/core/platform/ptp_tether_codec.dart';
import 'package:mobileapp/core/platform/ptp_tether_link.dart';
import 'package:mobileapp/core/platform/ptp_shooting_safety.dart';

enum _TetherFamily {
  canonEos,
  nikon,
  sony,
  fuji,
  panasonic,
  olympus,
  pentax,
  standard,
}

class PtpTetherCommandException extends PlatformException {
  PtpTetherCommandException(this.opcode, this.responseCode)
    : super(
        code: responseCode == 0x2019 ? 'CAMERA_BUSY' : 'PTP_COMMAND_REJECTED',
        message: switch (responseCode) {
          0x2019 => 'The camera is busy finishing a photo. AirPix will retry.',
          0x2005 =>
            'This camera does not support the required shooting operation in its current USB mode.',
          0x2009 =>
            'This photo is no longer available from the camera connection.',
          0x200f =>
            'The camera denied access. Check its USB shooting mode and access settings.',
          0x2013 =>
            'The camera has no memory card available for this operation.',
          _ =>
            'The camera could not complete the shooting or photo-transfer request. Check its USB mode and reconnect.',
        },
        details: {'opcode': opcode, 'responseCode': responseCode},
      );

  final int opcode;
  final int responseCode;
}

class _TetherPhoto {
  _TetherPhoto({
    required this.id,
    required this.handle,
    required this.info,
    this.hostTransfer = false,
    this.sonyMemory = false,
    this.usesCanonEventMetadata = false,
    this.existing = false,
  });

  final String id;
  final int handle;
  PtpObjectInfo info;
  final bool hostTransfer;
  final bool sonyMemory;
  final bool existing;
  bool usesCanonEventMetadata;
  OtgPickedFile? staged;
}

class _TetherRun {
  _TetherRun(this.id, this.events);

  final String id;
  final StreamController<LiveCameraEvent> events;
  PtpTetherConnection? connection;
  PtpDeviceInfo? info;
  _TetherFamily? family;
  final Set<int> operations = {};
  final Set<int> baselineHandles = {};
  final Set<int> existingHandles = {};
  final Set<int> storageIds = {};
  final Set<int> observedHandles = {};
  final Map<int, int> generations = {};
  final Set<int> eventHandles = {};
  final Map<int, DateTime> metadataRetryAfter = {};
  final Map<int, int> metadataFailures = {};
  final Set<int> missingMetadataHandles = {};
  final Set<int> hostTransferHandles = {};
  final Map<int, PtpObjectInfo> canonHostMetadata = {};
  final Set<int> ignoredHandles = {};
  final Set<String> delivered = {};
  final Map<int, String> currentIds = {};
  final LinkedHashMap<String, _TetherPhoto> pending = LinkedHashMap();
  final Map<int, int> canonProperties = {};
  final Map<int, List<int>> canonChoices = {};
  Map<int, PtpProperty> sonyProperties = {};
  int? fujiUsbMode;
  int? olympusOriginalControlMode;
  bool olympusRestoreRequired = false;
  bool canReleaseAfterError = false;
  int sonyProtocol = 0;
  int sonySequence = 0;
  int baselineCount = 0;
  bool canonRemote = false;
  bool canonEvents = false;
  int? canonCardDestination;
  bool nikonBodyMode = false;
  bool sonyConnected = false;
  bool fullObjectOnly = false;
  // Some Fuji tether connections expose card objects as well as host events.
  // Probe only read-only PTP operations; no mode switch or shutter command.
  bool fujiCardPolling = false;
  bool ready = false;
  bool stopping = false;
  bool disconnected = false;
  bool closed = false;
  Future<void> tail = Future.value();
  Future<void>? refresh;
  Future<void>? closing;
  StreamSubscription<Map<Object?, Object?>>? subscription;
  Timer? timer;
  DateTime? lastCardScan;
  int consecutiveCameraBusyChecks = 0;
  DateTime? pollRetryAfter;
}

/// Original PTP tether implementation using documented wire formats and the
/// protocol behavior recorded by libgphoto2 (see docs/USB_TETHER_SUPPORT.md).
/// No proprietary SDK or libgphoto2 source is embedded. In particular, no remote
/// shutter, UI-lock, live-view or delete command is used for physical shooting.
class PtpTetherCameraTransport implements LiveCameraTransport {
  PtpTetherCameraTransport({
    PtpTetherLink? link,
    this.uploadMode = LiveCameraUploadMode.newShotsOnly,
    // Notifications are optional wake-ups. Polling remains active without
    // a shutter event; one active PTP transaction at a time protects the body.
    this.eventPollInterval = const Duration(milliseconds: 500),
    this.cardScanInterval = const Duration(seconds: 1),
    this.stopGracePeriod = const Duration(seconds: 3),
    Future<void> Function(Duration)? delay,
    DateTime Function()? now,
    Future<bool> Function(OtgPickedFile)? stagedFileExists,
  }) : _link = link ?? MethodChannelPtpTetherLink(),
       _delay = delay ?? Future<void>.delayed,
       _now = now ?? DateTime.now,
       _stagedFileExists = stagedFileExists ?? _fileExists;

  final PtpTetherLink _link;
  final LiveCameraUploadMode uploadMode;
  final Duration eventPollInterval;
  final Duration cardScanInterval;
  final Duration stopGracePeriod;
  final Future<void> Function(Duration) _delay;
  final DateTime Function() _now;
  final Future<bool> Function(OtgPickedFile) _stagedFileExists;
  final Map<String, _TetherRun> _runs = {};
  final Map<String, StreamController<LiveCameraEvent>> _eventStreams = {};
  _TetherRun? _active;

  static const _sonyMemoryHandle = 0xffffc001;
  static const _maxPhotoBytes = 512 * 1024 * 1024;
  // Index a small amount of the initial card contents per event check. Keep the
  // pending metadata bounded while a large photo is transferring, and always
  // check physical-shutter events before resuming the backlog.
  static const _existingMetadataBatchSize = 8;
  static const _maxExistingPending = 32;
  static const _extensions = {
    'jpg',
    'jpeg',
    'png',
    'heic',
    'heif',
    'tif',
    'tiff',
    'webp',
    'dng',
    'arw',
    'cr2',
    'cr3',
    'nef',
    'nrw',
    'raf',
    'rw2',
    'orf',
    'pef',
  };

  static Future<bool> _fileExists(OtgPickedFile photo) async {
    try {
      final file = File(photo.path);
      return await file.exists() && await file.length() > 0;
    } on FileSystemException {
      return false;
    }
  }

  @override
  Stream<LiveCameraEvent> eventsForSession(String sessionId) => _eventStreams
      .putIfAbsent(sessionId, () => StreamController.broadcast())
      .stream;

  void _emit(_TetherRun run, String type, String message, {String? code}) {
    if (run.events.isClosed) return;
    run.events.add(
      LiveCameraEvent(
        sessionId: run.id,
        type: type,
        message: message,
        code: code,
      ),
    );
  }

  void _checkActive(_TetherRun run) {
    if (run.stopping || run.closed || run.disconnected) {
      throw PlatformException(
        code: run.disconnected
            ? 'USB_CAMERA_DISCONNECTED'
            : 'LIVE_CAMERA_CANCELLED',
        message: 'This camera session has ended.',
      );
    }
  }

  Future<T> _serial<T>(_TetherRun run, Future<T> Function() operation) {
    final result = Completer<T>();
    run.tail = run.tail.then((_) async {
      try {
        _checkActive(run);
        result.complete(await operation());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<PtpTetherResponse> _command(
    _TetherRun run,
    int opcode, {
    List<int> params = const [],
    Uint8List? data,
    bool duringClose = false,
    int busyRetries = 3,
  }) async {
    PtpShootingSafety.requirePassive(
      opcode,
      vendorId: run.connection?.vendorId ?? 0,
      params: params,
      data: data,
    );
    for (var attempt = 0; ; attempt++) {
      if (!duringClose) _checkActive(run);
      if (!duringClose &&
          run.ready &&
          run.pollRetryAfter?.isAfter(_now()) == true) {
        throw PtpTetherCommandException(opcode, 0x2019);
      }
      final response = await _link.command(
        run.id,
        opcode,
        params: params,
        outData: data,
      );
      if (response.succeeded) return response;
      if (response.responseCode == 0x2019 &&
          run.ready &&
          !duringClose &&
          opcode != 0x1008) {
        // Give exposure/card writing priority. Faster polling must not create
        // a tight retry loop while the physical camera is busy.
        final exponent = run.consecutiveCameraBusyChecks.clamp(0, 3);
        run.pollRetryAfter = _now().add(
          Duration(milliseconds: (500 * (1 << exponent)).clamp(500, 3000)),
        );
        throw PtpTetherCommandException(opcode, response.responseCode);
      }
      if (response.responseCode == 0x2019 &&
          attempt < busyRetries &&
          !duringClose) {
        await _delay(Duration(milliseconds: 100 * (attempt + 1)));
        continue;
      }
      throw PtpTetherCommandException(opcode, response.responseCode);
    }
  }

  void _requireOperations(_TetherRun run, Iterable<int> required) {
    if (required.every(run.operations.contains)) return;
    throw PlatformException(
      code: 'TETHER_MODE_UNSUPPORTED',
      message:
          '${run.info?.model ?? run.connection?.name ?? "This camera"} '
          'does not expose the shooting protocol required in its current USB '
          'mode. Select the model’s USB tethering / PC Remote mode and reconnect.',
    );
  }

  @override
  Future<LiveCameraSession> start(String sessionId) async {
    if (_active != null || _runs.containsKey(sessionId)) {
      throw PlatformException(code: 'LIVE_CAMERA_BUSY');
    }
    final controller = _eventStreams.putIfAbsent(
      sessionId,
      () => StreamController.broadcast(),
    );
    final run = _TetherRun(sessionId, controller);
    _active = run;
    _runs[sessionId] = run;
    // Keep this native subscription through rollback/close. The page may cancel
    // its outer subscription first; that must not prematurely close the camera.
    run.subscription = _link
        .events(sessionId)
        .listen(
          (event) => _nativeEvent(run, event),
          onError: (Object error) {
            if (!run.stopping && !run.closed) {
              _emit(
                run,
                'status',
                'Camera event notifications interrupted; checking for new photos periodically.',
              );
            }
          },
        );
    try {
      await _serial(run, () => _prepare(run));
      _checkActive(run);
      run.ready = true;
      run.timer = Timer.periodic(eventPollInterval, (_) {
        if (run.ready && !run.stopping) {
          unawaited(
            _refresh(run).catchError((Object error) {
              _reportPollError(run, error);
            }),
          );
        }
      });
      final connection = run.connection!;
      final family = switch (run.family!) {
        _TetherFamily.canonEos => 'Canon EOS',
        _TetherFamily.nikon => 'Nikon',
        _TetherFamily.sony => 'Sony',
        _TetherFamily.fuji => 'Fujifilm',
        _TetherFamily.panasonic => 'Panasonic / LUMIX',
        _TetherFamily.olympus => 'OM SYSTEM / Olympus',
        _TetherFamily.pentax => 'Pentax / Ricoh',
        _TetherFamily.standard => 'USB camera',
      };
      final monitoring =
          run.family == _TetherFamily.fuji && !run.fujiCardPolling
          ? 'This model requires a camera new-photo notification; its '
                'card list is not exposed in tether mode.'
          : run.family == _TetherFamily.sony
          ? 'AirPix checks the Sony shooting-mode queue every '
                '${eventPollInterval.inMilliseconds / 1000} seconds without '
                'requiring a shutter event.'
          : 'AirPix monitors camera events and checks for new card photos '
                'every ${_effectiveCardScanInterval(run).inSeconds} second(s) '
                'even if the camera sends no shutter event.';
      return LiveCameraSession(
        id: run.id,
        cameraId: connection.cameraId,
        name: run.info!.model.isEmpty ? connection.name : run.info!.model,
        physicalShutter: connection.physicalShutter,
        message: uploadMode == LiveCameraUploadMode.existingAndNew
            ? '$family shooting-mode PTP session prepared. $monitoring '
                  'Existing photos and each new shot enter the local upload '
                  'queue; new shots have priority. Confirm the camera screen '
                  'and physical shutter still work.'
            : '$family shooting-mode PTP session prepared. $monitoring '
                  'Press the camera’s physical shutter once and verify the '
                  'screen stays usable and a new photo arrives. Only newly '
                  'received photos enter the cloud upload queue.',
        baselineCount: run.baselineCount,
        uploadMode: uploadMode,
      );
    } catch (error) {
      try {
        await stop(sessionId);
      } catch (_) {
        // Preserve the actual negotiation failure for setup guidance.
      }
      final connection = run.connection;
      if (error is PlatformException && connection != null) {
        // Keep the camera identity after release so the UI can show the exact
        // brand's USB mode instead of a generic connection-failed toast.
        throw PlatformException(
          code: error.code,
          message: error.message,
          stacktrace: error.stacktrace,
          details: <Object?, Object?>{
            if (error.details is Map) ...error.details as Map,
            'camera': run.info?.model ?? connection.name,
            'vendorId': connection.vendorId,
          },
        );
      }
      rethrow;
    }
  }

  Future<void> _prepare(_TetherRun run) async {
    _emit(
      run,
      'status',
      'Identifying the camera and preparing its shooting connection…',
    );
    run.connection = await _link.open(run.id);
    _checkActive(run);
    final response = await _command(run, 0x1001);
    run.info = PtpTetherCodec.decodeDeviceInfo(response.data);
    run.operations.addAll(run.info!.operations);
    final name = '${run.info!.manufacturer} ${run.info!.model}'.toLowerCase();
    final vendor = run.connection!.vendorId;
    final extension = run.info!.vendorExtensionId;
    final isFuji =
        vendor == 0x04cb ||
        extension == 14 ||
        name.contains('fujifilm') ||
        name.contains('fuji');
    // Fuji tether objects are read as complete objects. Do not use the generic
    // partial-object path for this vendor.
    run.fullObjectOnly = isFuji;
    if (vendor == 0x04a9 || extension == 11 || name.contains('canon')) {
      run.family = _TetherFamily.canonEos;
      await _prepareCanon(run);
    } else if (vendor == 0x04b0 || extension == 10 || name.contains('nikon')) {
      run.family = _TetherFamily.nikon;
      await _prepareNikon(run);
    } else if (vendor == 0x054c || extension == 17 || name.contains('sony')) {
      run.family = _TetherFamily.sony;
      if (uploadMode == LiveCameraUploadMode.existingAndNew) {
        // This adapter exposes Sony's consumptive PC Remote RAM queue. Older
        // card files require a separate, model-specific background-transfer
        // protocol; standard listing opcodes alone do not prove support. Never
        // switch into MTP or drain an old RAM entry to pretend this mode works.
        throw PlatformException(
          code: 'TETHER_EXISTING_PHOTOS_UNAVAILABLE',
          message:
              'This Sony PC Remote adapter receives new shots only. '
              'Select New shots only to keep shooting and uploading. '
              'Existing memory-card photos need a separate import; AirPix '
              'will not switch the camera into file-transfer mode.',
        );
      }
      await _prepareSony(run);
    } else if (isFuji) {
      run.family = _TetherFamily.fuji;
      await _prepareFuji(run);
    } else if (vendor == 0x04da ||
        extension == 28 ||
        name.contains('panasonic') ||
        name.contains('lumix')) {
      run.family = _TetherFamily.panasonic;
      await _preparePanasonic(run);
    } else if (vendor == 0x07b4 ||
        vendor == 0x33a2 ||
        extension == 0xfffd ||
        name.contains('olympus') ||
        name.contains('om system') ||
        name.contains('omsystem')) {
      run.family = _TetherFamily.olympus;
      await _prepareOlympus(run);
    } else if (vendor == 0x0a17 ||
        vendor == 0x25fb ||
        extension == 13 ||
        name.contains('pentax') ||
        name.contains('ricoh')) {
      run.family = _TetherFamily.pentax;
      _preparePentax(run);
    } else if (!run.fullObjectOnly &&
        run.connection!.physicalShutter == 'supported') {
      run.family = _TetherFamily.standard;
    } else {
      throw PlatformException(
        code: 'TETHER_CAMERA_UNSUPPORTED',
        message: _unsupportedCameraGuidance(run, name, vendor, extension),
      );
    }
    _checkActive(run);
    if (run.family != _TetherFamily.sony && run.family != _TetherFamily.fuji) {
      _requireOperations(run, [0x1004, 0x1007, 0x1008, 0x1009]);
      final handles = await _cardHandles(run);
      run.baselineHandles.addAll(handles);
      if (uploadMode == LiveCameraUploadMode.existingAndNew) {
        run.existingHandles.addAll(handles);
      }
      run.observedHandles.addAll(handles);
      run.baselineCount = handles.length;
      run.eventHandles.clear();
      run.hostTransferHandles.clear();
      run.lastCardScan = _now();
    }
  }

  Future<void> _preparePanasonic(_TetherRun run) async {
    // Require the tether capture capability, but NEVER invoke the shutter.
    // PC(Storage) / PictBridge card access alone is not a shooting connection.
    _requireOperations(run, [0x9404, 0x940a, 0x1004, 0x1007, 0x1008, 0x1009]);
    await _verifyPanasonicRecording(run);
  }

  Future<void> _verifyPanasonicRecording(_TetherRun run) async {
    final reply = await _command(run, 0x940a, params: [0x08000090]);
    final target = PtpTetherCodec.decodePanasonicCaptureTarget(reply.data);
    if (target != 0 && target != 2) {
      throw PlatformException(
        code: run.ready
            ? 'TETHER_MODE_CHANGED'
            : 'TETHER_CAMERA_SETTING_REQUIRED',
        message:
            'Panasonic / LUMIX must use PC(Tether) and record to its '
            'memory card (SD or SD + PC). Host-only recording is not accepted. '
            'AirPix will not change the recording destination or USB mode.',
      );
    }
  }

  Future<int> _olympusValue(_TetherRun run, int property) async {
    final reply = await _command(run, 0x1015, params: [property]);
    return PtpTetherCodec.decodeValue(4, reply.data) as int;
  }

  Future<void> _prepareOlympus(_TetherRun run) async {
    // 0x9486 identifies the OM-D PTP dialect, not the older XML/PictBridge
    // control protocol. Advertised properties alone are insufficient.
    _requireOperations(run, [
      0x9486,
      0x1014,
      0x1015,
      0x1004,
      0x1007,
      0x1008,
      0x1009,
    ]);
    if (!run.info!.properties.containsAll([0xd052, 0xd0dc])) {
      throw PlatformException(
        code: 'TETHER_MODE_UNSUPPORTED',
        message:
            'OM SYSTEM / Olympus must expose its OM-D control and '
            'card-recording properties. Select RAW/Control and reconnect.',
      );
    }
    final reply = await _command(run, 0x1014, params: [0xd052]);
    final control = PtpTetherCodec.decodeProperty(reply.data);
    if (control.code != 0xd052 ||
        control.type != 4 ||
        !const [1, 2].contains(control.intValue)) {
      throw const FormatException('Unsupported OM connection-mode descriptor');
    }
    final original = await _olympusValue(run, 0xd052);
    if (original != control.intValue || !const [1, 2].contains(original)) {
      throw const FormatException('OM connection-mode readback disagrees');
    }
    // Keep originals on the card. Never write the capture target.
    await _verifyOlympusRecording(run, verifyControl: false);
    await _cardHandles(run); // Prime card access before PC-session negotiation.
    if (original == 2) {
      _requireOperations(run, [0x1016]);
      if (!control.writable ||
          control.form != 2 ||
          !control.values.contains(1) ||
          !control.values.contains(2)) {
        throw PlatformException(
          code: 'TETHER_MODE_UNSUPPORTED',
          message:
              'OM SYSTEM / Olympus does not permit reversible PC-session '
              'negotiation on this connection. Select RAW/Control.',
        );
      }
      run.olympusOriginalControlMode = original;
      // Mark before sending: a lost response may still have applied the change.
      run.olympusRestoreRequired = true;
      await _command(
        run,
        0x1016,
        params: [0xd052],
        data: PtpTetherCodec.encodeValue(4, 1),
      );
      await _delay(const Duration(milliseconds: 100));
    }
    await _verifyOlympusRecording(run);
  }

  Future<void> _verifyOlympusRecording(
    _TetherRun run, {
    bool verifyControl = true,
  }) async {
    final target = await _olympusValue(run, 0xd0dc);
    final control = verifyControl ? await _olympusValue(run, 0xd052) : 1;
    if (target != 2 || control != 1) {
      throw PlatformException(
        code: run.ready
            ? 'TETHER_MODE_CHANGED'
            : 'TETHER_CAMERA_SETTING_REQUIRED',
        message:
            'OM SYSTEM / Olympus needs a RAW/Control connection and '
            'camera-card recording. AirPix leaves shooting settings unchanged; '
            'restore card recording before starting again.',
      );
    }
  }

  void _preparePentax(_TetherRun run) {
    // pkTriggerCord's vendor protocol uses SCSI over Mass Storage, not PTP.
    // It cannot be implemented by relabelling an iPhone card importer.
    if (run.connection!.physicalShutter != 'supported') {
      throw PlatformException(
        code: 'TETHER_CAMERA_UNSUPPORTED',
        message:
            'Pentax / Ricoh USB live shooting is not verified for this '
            'connection. Its documented Pentax SCSI tether protocol requires '
            'Mass Storage, which AirPix never enables. PTP/MTP file access '
            'alone does not prove that you can keep shooting.',
      );
    }
    _requireOperations(run, [0x1004, 0x1007, 0x1008, 0x1009]);
  }

  Future<void> _prepareFuji(_TetherRun run) async {
    if (uploadMode == LiveCameraUploadMode.existingAndNew) {
      throw PlatformException(
        code: 'TETHER_EXISTING_PHOTOS_UNAVAILABLE',
        message:
            'Fujifilm USB Tether mode receives new shots. Select New shots only '
            'for live shooting, or stop receiving and use a separate card import '
            'for older photos.',
      );
    }
    _requireOperations(run, [0x1015, 0x1008, 0x1009]);
    if (!run.info!.properties.contains(PtpTetherPropertyCode.fujiUsbMode)) {
      throw PlatformException(
        code: 'TETHER_MODE_UNSUPPORTED',
        message:
            'This Fujifilm connection does not expose its USB tether-mode '
            'property. Select USB TETHER SHOOTING AUTO/FIXED and reconnect.',
      );
    }
    final mode = await _command(
      run,
      PtpTetherOperation.getPropertyValue,
      params: [PtpTetherPropertyCode.fujiUsbMode],
    );
    final value = PtpTetherCodec.decodeValue(4, mode.data);
    if (value is! int || value != 5) {
      throw PlatformException(
        code: 'TETHER_CAMERA_SETTING_REQUIRED',
        message:
            'Set the Fujifilm camera USB mode to USB TETHER SHOOTING AUTO/FIXED '
            'before starting AirPix. Card Reader, RAW conversion and Webcam '
            'modes are not live-shooting modes.',
      );
    }
    run.fujiUsbMode = value;
    final events = run.info!.events;
    final hasPhotoEvents = events.contains(0xc004) || events.contains(0x4002);
    // Prefer read-only card polling when this tether mode actually exposes
    // standard storage/handle commands. It works even if event notifications
    // are missing. Never turn on card-reader mode to obtain those commands.
    if (run.operations.containsAll([0x1004, 0x1007, 0x1008, 0x1009])) {
      try {
        final handles = await _cardHandles(run, requireStorage: false);
        if (run.storageIds.isNotEmpty) {
          run.fujiCardPolling = true;
          run.baselineHandles.addAll(handles);
          run.observedHandles.addAll(handles);
          run.baselineCount = handles.length;
          run.lastCardScan = _now();
        }
      } on PtpTetherCommandException catch (error) {
        // Some Fuji tether protocols expose host notifications but reject
        // card listing. Only a documented unsupported/busy PTP response
        // permits the existing event-based receiver to continue.
        if (!hasPhotoEvents ||
            !const {0x2005, 0x2009, 0x2019}.contains(error.responseCode)) {
          rethrow;
        }
      }
    }
    if (!hasPhotoEvents && !run.fujiCardPolling) {
      throw PlatformException(
        code: 'TETHER_MODE_UNSUPPORTED',
        message:
            'This Fujifilm tether connection exposes neither a readable '
            'card photo list nor new-photo notifications. Select a supported '
            'USB TETHER SHOOTING mode; AirPix cannot safely monitor this mode.',
      );
    }
  }

  String _unsupportedCameraGuidance(
    _TetherRun run,
    String name,
    int vendor,
    int extension,
  ) {
    final model = run.info!.model.trim();
    final identity = model.isEmpty ? 'Connected camera' : model;
    if (run.fullObjectOnly) {
      return 'Fujifilm camera detected: $identity. Select USB TETHER SHOOTING '
          'AUTO/FIXED for new-shot transfer. USB CARD READER is for existing '
          'files; unsupported Fuji modes are rejected instead of locking the body.';
    }
    return '$identity has no supported shooting adapter in this build. '
        'Use camera FTP when available, or manual import for stored photos.';
  }

  Future<void> _prepareCanon(_TetherRun run) async {
    final model = run.info!.model.toLowerCase();
    // EOS M/PowerShot require different live-view and remote mode sequences.
    // Do not send regular EOS mode values to those bodies by brand alone.
    if (model.contains('powershot') ||
        (RegExp(r'eos\s+m').hasMatch(model) &&
            !RegExp(r'm6\s*(mark\s*)?ii').hasMatch(model))) {
      throw PlatformException(
        code: 'TETHER_CAMERA_UNSUPPORTED',
        message:
            '${run.info!.model} needs a separate camera adapter. This build supports the regular EOS shooting protocol.',
      );
    }
    _requireOperations(run, [0x9114, 0x9115, 0x9116]);
    // Mark before the request: cancellation can win after the camera accepted
    // it but before Dart receives its response, and cleanup is still required.
    _checkActive(run);
    run.canonRemote = true;
    await _command(run, 0x9114, params: [1]);
    _checkActive(run);
    run.canonEvents = true;
    await _command(run, 0x9115, params: [1]);
    if (run.operations.contains(0x9127)) {
      try {
        await _command(run, 0x9127, params: [0xd11c]);
      } on PtpTetherCommandException {
        // Initial GetEvent also supplies properties; an optional refresh request
        // may be refused by a body even when its opcode is advertised.
      }
    }
    for (var attempt = 0; attempt < 12; attempt++) {
      await _pollCanon(run);
      if (run.canonProperties.containsKey(0xd11c)) break;
      await _delay(const Duration(milliseconds: 100));
    }
    final destination = run.canonProperties[0xd11c];
    if (destination == null || destination <= 0 || destination == 4) {
      throw PlatformException(
        code: 'TETHER_CARD_RECORDING_REQUIRED',
        message:
            'Set the Canon camera to record to its memory card, then reconnect. '
            'AirPix will not change camera recording settings automatically.',
      );
    }
    run.canonCardDestination = destination;
    // Canon may change its advertised operations after entering remote mode.
    final updated = await _command(run, 0x1001);
    run.operations.addAll(
      PtpTetherCodec.decodeDeviceInfo(updated.data).operations,
    );
  }

  Future<void> _prepareNikon(_TetherRun run) async {
    if (run.operations.contains(0x90c2)) {
      // 0 returns control to the physical body. 1 would lock it into full PC
      // control and is deliberately never used by this receiver.
      run.nikonBodyMode = true;
      await _command(run, 0x90c2, params: [0]);
    } else if (run.connection!.physicalShutter != 'supported') {
      throw PlatformException(
        code: 'TETHER_MODE_UNSUPPORTED',
        message:
            'This Nikon USB connection does not expose the camera-control '
            'release command. Select its supported shooting USB mode and reconnect.',
      );
    }
    // Discard old event notifications before the card baseline, without reading
    // or deleting any old images. They must not become new shots after arming.
    await _pollNikon(run);
  }

  Future<void> _prepareSony(_TetherRun run) async {
    _requireOperations(run, [0x9201, 0x9202]);
    await _command(run, 0x9201, params: [1, 0, 0]);
    await _command(run, 0x9201, params: [2, 0, 0]);
    final capabilities = await _sonyExtensionInfo(run);
    run.sonyProtocol = capabilities.version;
    run.operations.addAll(
      capabilities.codes.where((code) => code >= 0x9000 && code < 0xa000),
    );
    await _command(run, 0x9201, params: [3, 0, 0]);
    run.sonyConnected = true;
    _requireOperations(run, [0x9209, 0x1008, 0x1009]);
    await _readSonyProperties(run);
    await _ensureSonyBaselineIdle(run);
    // Validate the photographer's settings; never change priority, destination,
    // USB mode, screen, or shutter settings to make a connection succeed.
    await _requireSonyProperty(
      run,
      0xd222,
      17,
      help:
          'On Sony Alpha 7 IV: Network > Cnct./Remote Sht. > Remote Shoot '
          'Setting > Still Img. Save Dest. > Dest.+Camera. On older Sony '
          'models, select PC Remote > PC+Camera. Use Remote Shooting over '
          'USB, not Mass Storage.',
    );
    await _requireSonyProperty(
      run,
      0xd25a,
      0,
      help:
          'Set Sony PC Remote control priority to Camera so its physical controls remain available.',
    );
    await _readSonyProperties(run);
    if (run.sonyProperties[0xd222]?.intValue != 17 ||
        run.sonyProperties[0xd25a]?.intValue != 0) {
      throw PlatformException(
        code: 'TETHER_MODE_NOT_CONFIRMED',
        message:
            'The Sony camera did not confirm Camera priority and PC + Camera recording. Live shooting was not started.',
      );
    }
    await _ensureSonyBaselineIdle(run);
  }

  Future<SonyExtensionInfo> _sonyExtensionInfo(_TetherRun run) async {
    // Some Sony bodies initially return a successful but empty dataset while
    // the remote connection initializes. libgphoto2 retries only this condition.
    // A nonempty malformed payload remains a protocol error, never success.
    for (var attempt = 0; attempt < 20; attempt++) {
      final response = await _command(run, 0x9202, params: [0x12c, 1]);
      if (response.data.isNotEmpty) {
        final capabilities = PtpTetherCodec.decodeSonyExtensionInfo(
          response.data,
        );
        if (capabilities.codes.isNotEmpty) return capabilities;
      }
      if (attempt < 19) await _delay(const Duration(milliseconds: 100));
    }
    throw PlatformException(
      code: 'TETHER_MODE_NOT_CONFIRMED',
      message:
          'The Sony camera did not finish preparing its remote shooting '
          'connection. Check PC Remote mode and reconnect.',
    );
  }

  Future<void> _ensureSonyBaselineIdle(_TetherRun run) async {
    for (var attempt = 0; attempt < 12; attempt++) {
      final count = run.sonyProperties[0xd215]?.intValue;
      if (count == null) {
        throw PlatformException(
          code: 'TETHER_MODE_NOT_CONFIRMED',
          message:
              'The Sony camera did not expose its new-photo queue. Check USB PC Remote mode and reconnect.',
        );
      }
      if (count == 0 || count == 0x8000) return;
      if (count > 0x8000) {
        // GetObject consumes a RAM entry. Never read and discard old pictures
        // just to manufacture an empty baseline.
        throw PlatformException(
          code: 'TETHER_PREVIOUS_PHOTOS_PENDING',
          message:
              'The Sony camera has photos waiting from an earlier PC Remote session. Finish that transfer before starting a new shooting session.',
        );
      }
      await _delay(const Duration(milliseconds: 200));
      await _readSonyProperties(run);
    }
    throw PlatformException(
      code: 'CAMERA_BUSY',
      message:
          'The Sony camera is finishing a photo. Wait for that transfer to finish, then start Live shooting again.',
    );
  }

  Future<void> _readSonyProperties(_TetherRun run) async {
    final response = await _command(run, 0x9209);
    run.sonyProperties = PtpTetherCodec.decodeSonyProperties(
      response.data,
      protocolVersion: run.sonyProtocol,
    );
  }

  Future<void> _requireSonyProperty(
    _TetherRun run,
    int code,
    int value, {
    required String help,
  }) async {
    if (run.sonyProperties[code]?.intValue == value) return;
    throw PlatformException(
      code: 'TETHER_CAMERA_SETTING_REQUIRED',
      message:
          '$help AirPix leaves camera settings unchanged. '
          'Disconnect USB, set this on the camera, then reconnect.',
    );
  }

  Future<Set<int>> _cardHandles(
    _TetherRun run, {
    bool requireStorage = true,
  }) async {
    final response = await _command(run, 0x1004);
    final storages = PtpTetherCodec.decodeUint32Array(
      response.data,
    ).where((id) => id != 0 && id != 0xffffffff).toSet();
    if (run.ready &&
        (storages.length != run.storageIds.length ||
            !storages.every(run.storageIds.contains))) {
      throw PlatformException(
        code: 'CAMERA_STORAGE_CHANGED',
        message:
            'The camera memory card changed. Start a new session before receiving more photos.',
      );
    }
    if (!run.ready) {
      run.storageIds
        ..clear()
        ..addAll(storages);
    }
    final result = <int>{};
    for (final storage in storages) {
      final objects = await _command(run, 0x1007, params: [storage, 0, 0]);
      result.addAll(PtpTetherCodec.decodeUint32Array(objects.data));
    }
    if (storages.isEmpty && !run.ready && requireStorage) {
      throw PlatformException(
        code: 'TETHER_CARD_RECORDING_REQUIRED',
        message:
            'Insert a writable memory card in the camera before starting Live shooting.',
      );
    }
    return result;
  }

  Future<void> _pollCanon(_TetherRun run) async {
    final response = await _command(run, 0x9116);
    for (final event in PtpTetherCodec.decodeCanonEvents(response.data)) {
      _consumeEvent(run, event);
    }
  }

  Future<void> _pollNikon(_TetherRun run) async {
    final extended = run.operations.contains(0x941c);
    if (!extended && !run.operations.contains(0x90c7)) return;
    final response = await _command(run, extended ? 0x941c : 0x90c7);
    for (final event in PtpTetherCodec.decodeNikonEvents(
      response.data,
      extended: extended,
    )) {
      _consumeEvent(run, event);
    }
  }

  void _consumeEvent(_TetherRun run, PtpTetherEvent event) {
    final property = event.propertyCode;
    if (property != null) {
      if (event.kind == PtpTetherEventKind.propertyChanged &&
          event.propertyValue != null) {
        run.canonProperties[property] = event.propertyValue!;
      } else if (event.kind == PtpTetherEventKind.propertyChoices) {
        run.canonChoices[property] = event.propertyValues;
      }
    }
    if (!run.ready) return;
    if (run.family == _TetherFamily.nikon &&
        event.kind == PtpTetherEventKind.objectTransfer) {
      _reportPollError(
        run,
        PlatformException(
          code: 'TETHER_MODE_CHANGED',
          message:
              'The Nikon camera reported a PC-memory capture instead of a card photo. Select recording to the camera card and start a new session.',
        ),
      );
      return;
    }
    final handle = event.handle;
    if (event.kind == PtpTetherEventKind.objectRemoved && handle != null) {
      run.canonHostMetadata.remove(handle);
      _clearMetadataRetry(run, handle);
      run.eventHandles.remove(handle);
      run.observedHandles.remove(handle);
      run.baselineHandles.remove(handle);
      run.existingHandles.remove(handle);
      run.ignoredHandles.remove(handle);
      run.currentIds.remove(handle);
      run.generations[handle] = (run.generations[handle] ?? 0) + 1;
    } else if (handle != null &&
        (event.kind == PtpTetherEventKind.objectAdded ||
            event.kind == PtpTetherEventKind.objectTransfer)) {
      // A fresh camera notification can announce that an earlier provisional
      // object is now complete; allow its metadata to be checked immediately.
      _clearMetadataRetry(run, handle);
      run.eventHandles.add(handle);
      if (run.family == _TetherFamily.canonEos &&
          event.kind == PtpTetherEventKind.objectTransfer) {
        run.hostTransferHandles.add(handle);
        run.canonHostMetadata.remove(handle);
        // Only the classic C186 event has verified full-width size/name fields.
        // Some EOS bodies expose their RAM handle through GetPartialObject but
        // reject standard GetObjectInfo for it. Keep this exact event metadata
        // as a bounded fallback; never invent the size of C1A9/C1B8 objects.
        final name = event.name;
        final size = event.size;
        final format = event.format;
        if (event.code == 0xc186 &&
            name != null &&
            name.isNotEmpty &&
            name.length <= 255 &&
            !name.contains('/') &&
            !name.contains('\\') &&
            size != null &&
            size > 0 &&
            size <= _maxPhotoBytes &&
            format != null &&
            format > 0 &&
            format != 0x3001) {
          final metadata = PtpObjectInfo(
            handle: handle,
            format: format,
            size: size,
            name: name,
            captureDate: '',
            modificationDate: '',
            parent: 0,
            storage: 0,
          );
          if (_isPhoto(metadata)) run.canonHostMetadata[handle] = metadata;
        }
      }
    }
  }

  void _nativeEvent(_TetherRun run, Map<Object?, Object?> event) {
    if (event['sessionId'] != run.id || run.closed || run.stopping) return;
    final type = event['type'];
    if (type == 'disconnected') {
      run.disconnected = true;
      run.timer?.cancel();
      _emit(
        run,
        'disconnected',
        event['message']?.toString() ?? 'Camera disconnected.',
        code: event['code']?.toString() ?? 'USB_CAMERA_DISCONNECTED',
      );
      return;
    }
    if (type == 'ptpEvent') {
      final bytes = event['data'];
      if (bytes is Uint8List) {
        try {
          final packet = PtpTetherCodec.decodeUsbEvent(
            bytes,
            vendorExtensionId: switch (run.family) {
              _TetherFamily.nikon => 10,
              _TetherFamily.sony => 17,
              _TetherFamily.fuji => 14,
              _TetherFamily.panasonic => 28,
              _TetherFamily.olympus => 0xfffd,
              _ => 0,
            },
          );
          // RAM/preview notifications are not card handles. Ignore them and
          // let card reconciliation verify the target and discover the original.
          final invalidMode =
              run.family == _TetherFamily.olympus &&
              const {0xc005, 0xc105}.contains(packet.code);
          if (invalidMode && run.ready) {
            _reportPollError(
              run,
              PlatformException(
                code: 'TETHER_MODE_CHANGED',
                message:
                    'The OM camera ended its control connection. '
                    'Receiving stopped; reconnect '
                    'in the documented shooting mode with card recording.',
              ),
            );
            return;
          }
          if (packet.code == 0x4004 || packet.code == 0x4005) {
            if (run.ready) {
              run.disconnected = true;
              run.timer?.cancel();
              _emit(
                run,
                'disconnected',
                'The camera memory card changed. Start a new session to index it safely.',
                code: 'CAMERA_STORAGE_CHANGED',
              );
            }
            return;
          }
          if (run.family != _TetherFamily.sony) _consumeEvent(run, packet);
        } on FormatException {
          // Notifications are hints; vendor polling and card reconciliation
          // remain authoritative and cannot mistake malformed bytes for a file.
        }
      }
      if (run.ready) {
        unawaited(
          _refresh(
            run,
          ).catchError((Object error) => _reportPollError(run, error)),
        );
      }
    } else if (type == 'catalogHint' ||
        type == 'catalogRemoved' ||
        type == 'catalogReady') {
      // ImageCaptureCore is an iOS-only backup signal. Raw/vendor PTP remains
      // authoritative; these hints only wake the same reconciliation logic.
      if (run.ready) {
        if (type != 'catalogReady' && run.family != _TetherFamily.sony) {
          final rawHandle = event['handle'];
          final handle = rawHandle is num ? rawHandle.toInt() : null;
          if (handle != null && handle > 0 && handle <= 0xffffffff) {
            _consumeEvent(
              run,
              PtpTetherEvent(
                code: type == 'catalogRemoved' ? 0x4003 : 0x4002,
                kind: type == 'catalogRemoved'
                    ? PtpTetherEventKind.objectRemoved
                    : PtpTetherEventKind.objectAdded,
                handle: handle,
                name: event['name']?.toString(),
                size: (event['size'] as num?)?.toInt(),
              ),
            );
          }
        }
        unawaited(
          _refresh(
            run,
          ).catchError((Object error) => _reportPollError(run, error)),
        );
      }
    } else if (type == 'error') {
      _emit(
        run,
        'error',
        event['message']?.toString() ?? 'Camera communication failed.',
        code: event['code']?.toString(),
      );
    } else if (event['message'] != null) {
      _emit(run, 'status', event['message'].toString());
    }
  }

  void _reportPollError(_TetherRun run, Object error) {
    if (run.stopping || run.closed || run.disconnected) return;
    final code = error is PlatformException ? error.code : 'PTP_PROTOCOL_ERROR';
    final message = error is PlatformException
        ? error.message ?? code
        : '$error';
    if (error is FormatException ||
        const {
          'USB_CAMERA_DISCONNECTED',
          'LIVE_CAMERA_SESSION_ENDED',
          'PTP_SESSION_ENDED',
          'PTP_INVALID_RESPONSE',
          'PTP_TRANSACTION_TIMEOUT',
          'CAMERA_SESSION_ENDED',
          'PTP_SESSION_CLOSED',
          'PTP_TIMEOUT',
          'PTP_TETHER_TIMEOUT',
          'PTP_TRANSACTION_MISMATCH',
          'PTP_SEQUENCE_ERROR',
          'PTP_INVALID_PACKET',
          'PTP_TRANSPORT_FAILED',
          'PTP_WRITE_FAILED',
          'PTP_DATA_LIMIT',
          'TETHER_MODE_CHANGED',
          'PTP_SHOOTING_COMMAND_BLOCKED',
          'CAMERA_STORAGE_CHANGED',
        }.contains(code)) {
      run.canReleaseAfterError =
          code == 'TETHER_MODE_CHANGED' ||
          code == 'PTP_SHOOTING_COMMAND_BLOCKED';
      run.disconnected = true;
      run.timer?.cancel();
      _emit(run, 'disconnected', message, code: code);
      // A completed mode-change reply or a locally blocked command is safe
      // to close/restore. A broken transport gets no further rollback bytes.
      if (run.canReleaseAfterError) {
        unawaited(stop(run.id).catchError((Object _) {}));
      }
    } else {
      _emit(run, 'error', 'Camera check will retry. $message', code: code);
    }
  }

  Future<void> _refresh(_TetherRun run) {
    final current = run.refresh;
    if (current != null) return current;
    if (run.pollRetryAfter?.isAfter(_now()) == true) return Future.value();
    // An ordinary PTP DeviceBusy response is expected while the physical
    // shutter is exposing/writing a photo. Do not claim a broken connection
    // or repeat a red failure on each 1-second poll: retry next tick.
    final future = _serial(run, () async {
      try {
        await _refreshInside(run);
        run.consecutiveCameraBusyChecks = 0;
      } on PtpTetherCommandException catch (error) {
        if (error.responseCode != 0x2019) rethrow;
        run.consecutiveCameraBusyChecks++;
        if (run.consecutiveCameraBusyChecks == 1 ||
            run.consecutiveCameraBusyChecks % 15 == 0) {
          _emit(
            run,
            'status',
            run.consecutiveCameraBusyChecks < 15
                ? 'Camera is saving a shot; AirPix will check again without '
                      'interrupting the physical shutter.'
                : 'Camera has stayed busy; keep it awake and close other '
                      'apps using its USB connection.',
          );
        }
      }
    });
    run.refresh = future;
    return future.whenComplete(() => run.refresh = null);
  }

  /// Full card-handle enumeration can block a camera busy saving a physical
  /// shutter shot. Small cards use a one-second fallback; large cards
  /// use a scan capped at five seconds. PTP events still wake photo handling early,
  /// without relying on them for correctness.
  Duration _effectiveCardScanInterval(_TetherRun run) {
    if (cardScanInterval <= Duration.zero ||
        cardScanInterval > const Duration(seconds: 5)) {
      return cardScanInterval;
    }
    final extra = (run.observedHandles.length ~/ 500).clamp(0, 4);
    return Duration(
      milliseconds: (cardScanInterval.inMilliseconds * (1 + extra)).clamp(
        cardScanInterval.inMilliseconds,
        5000,
      ),
    );
  }

  Future<void> _refreshInside(_TetherRun run) async {
    if (!run.ready) return;
    final before = run.pending.length;
    final liveBefore = run.pending.values
        .where((photo) => !photo.existing)
        .length;
    switch (run.family!) {
      case _TetherFamily.canonEos:
        await _pollCanon(run);
        final destination = run.canonProperties[0xd11c];
        if (destination != null && (destination == 0 || destination == 4)) {
          throw PlatformException(
            code: 'TETHER_MODE_CHANGED',
            message:
                'The Canon camera stopped recording to its card. Reconnect after restoring card recording.',
          );
        }
      case _TetherFamily.nikon:
        await _pollNikon(run);
      case _TetherFamily.sony:
        await _refreshSony(run);
      case _TetherFamily.fuji:
        break;
      case _TetherFamily.panasonic:
      case _TetherFamily.olympus:
      case _TetherFamily.pentax:
      case _TetherFamily.standard:
        break;
    }
    if (run.family != _TetherFamily.sony) {
      final lastScan = run.lastCardScan;
      if ((run.family != _TetherFamily.fuji || run.fujiCardPolling) &&
          (lastScan == null ||
              _now().difference(lastScan) >= _effectiveCardScanInterval(run))) {
        if (run.family == _TetherFamily.panasonic) {
          await _verifyPanasonicRecording(run);
        } else if (run.family == _TetherFamily.olympus) {
          await _verifyOlympusRecording(run);
        }
        final handles = await _cardHandles(run);
        // A previous InvalidObjectHandle can refer to a removed or temporary
        // card entry. Retire that hint only when a subsequent complete scan
        // also confirms it absent. Host/RAM transfers are not card entries.
        for (final missing in run.missingMetadataHandles.toList()) {
          if (!handles.contains(missing) &&
              !run.hostTransferHandles.contains(missing)) {
            run.eventHandles.remove(missing);
            run.existingHandles.remove(missing);
            _clearMetadataRetry(run, missing);
          }
        }
        // A missed removal event must not make a reused handle disappear forever.
        for (final old in run.observedHandles.difference(handles).toList()) {
          run.observedHandles.remove(old);
          run.baselineHandles.remove(old);
          run.existingHandles.remove(old);
          run.currentIds.remove(old);
          run.ignoredHandles.remove(old);
          _clearMetadataRetry(run, old);
          run.generations[old] = (run.generations[old] ?? 0) + 1;
        }
        run.eventHandles.addAll(handles.difference(run.observedHandles));
        run.lastCardScan = _now();
      }
      for (final handle in run.eventHandles.toList()) {
        _checkActive(run);
        if (run.baselineHandles.contains(handle) ||
            run.ignoredHandles.contains(handle)) {
          run.eventHandles.remove(handle);
          continue;
        }
        await _tryDiscoverCardPhoto(run, handle);
      }
      if (run.family != _TetherFamily.fuji) {
        final livePending = run.pending.values
            .where((photo) => !photo.existing)
            .length;
        final existingPending = run.pending.length - livePending;
        if (livePending == 0 ||
            (existingPending == 0 && livePending == liveBefore)) {
          // Fresh shots win this check. A previously pending shot may be waiting
          // for its own retry; once the old batch drains, let the backlog progress
          // as well so that one failed live download cannot starve the card.
          await _discoverExistingBatch(run);
        }
      }
    }
    if (run.pending.length > before) {
      _emit(run, 'photosAvailable', 'Camera photo ready to receive.');
    }
  }

  Future<void> _discoverExistingBatch(_TetherRun run) async {
    if (run.existingHandles.isEmpty) return;
    var remaining =
        _maxExistingPending -
        run.pending.values.where((photo) => photo.existing).length;
    if (remaining <= 0) return;
    var attempts = 0;
    var progressed = false;
    // Snapshot only candidates for this bounded batch. Backoff entries stay in
    // the backlog without blocking later complete photos or causing a hot loop.
    final candidates = run.existingHandles
        .where(
          (handle) => run.metadataRetryAfter[handle]?.isAfter(_now()) != true,
        )
        .take(_existingMetadataBatchSize)
        .toList(growable: false);
    for (final handle in candidates) {
      _checkActive(run);
      if (!run.existingHandles.contains(handle)) continue;
      if (attempts >= _existingMetadataBatchSize || remaining <= 0) break;
      attempts++;
      final before = run.pending.length;
      if (await _tryDiscoverCardPhoto(run, handle, existing: true)) {
        run.existingHandles.remove(handle);
        progressed = true;
      }
      remaining -= run.pending.length - before;
      // A native hint can arrive while metadata is in flight. Resume event
      // polling before spending another card request on the initial backlog.
      if (run.eventHandles.any((id) => !run.baselineHandles.contains(id))) {
        break;
      }
    }
    if (progressed && run.pending.isEmpty && _hasReadyExistingWork(run)) {
      // A card can contain many folders or non-photo objects. Continue indexing
      // after productive batches, but never spin on only busy/missing objects.
      _emit(run, 'photosAvailable', 'Checking existing camera photos…');
    }
  }

  bool _hasReadyExistingWork(_TetherRun run) => run.existingHandles.any(
    (handle) => run.metadataRetryAfter[handle]?.isAfter(_now()) != true,
  );

  Future<bool> _tryDiscoverCardPhoto(
    _TetherRun run,
    int handle, {
    bool existing = false,
  }) async {
    if (run.metadataRetryAfter[handle]?.isAfter(_now()) == true) return false;
    try {
      await _discoverCardPhoto(run, handle, existing: existing);
      _clearMetadataRetry(run, handle);
      return true;
    } on PlatformException catch (error) {
      if (error.code == 'CAMERA_FILE_NOT_READY') {
        // Incomplete length/name data must not consume every poll in a burst.
        // A fresh camera notification can end this backoff early.
        _retryMetadataLater(run, handle);
        return false;
      }
      if (error is! PtpTetherCommandException ||
          error.opcode != 0x1008 ||
          run.hostTransferHandles.contains(handle) ||
          (error.responseCode != 0x2009 && error.responseCode != 0x2019)) {
        // Transport, framing, permission and consumptive-buffer failures must
        // never be mistaken for a still-writing card photograph.
        rethrow;
      }
      if (error.responseCode == 0x2009) run.missingMetadataHandles.add(handle);
      _retryMetadataLater(run, handle);
      return false;
    }
  }

  void _retryMetadataLater(_TetherRun run, int handle) {
    final failures = (run.metadataFailures[handle] ?? 0) + 1;
    run.metadataFailures[handle] = failures;
    final exponent = failures > 5 ? 4 : failures - 1;
    run.metadataRetryAfter[handle] = _now().add(
      Duration(milliseconds: 500 * (1 << exponent)),
    );
    if (failures == 1) {
      _emit(
        run,
        'status',
        'One camera photo is still being prepared. Other photos continue to upload.',
      );
    }
  }

  void _clearMetadataRetry(_TetherRun run, int handle) {
    run.metadataRetryAfter.remove(handle);
    run.metadataFailures.remove(handle);
    run.missingMetadataHandles.remove(handle);
  }

  Future<({PtpObjectInfo info, bool fromCanonEvent})> _photoMetadata(
    _TetherRun run,
    int handle, {
    int busyRetries = 3,
  }) async {
    try {
      final response = await _command(
        run,
        0x1008,
        params: [handle],
        busyRetries: busyRetries,
      );
      return (
        info: PtpTetherCodec.decodeObjectInfo(response.data, handle: handle),
        fromCanonEvent: false,
      );
    } on PtpTetherCommandException catch (error) {
      if (run.family == _TetherFamily.canonEos &&
          run.hostTransferHandles.contains(handle) &&
          (error.responseCode == 0x2009 || error.responseCode == 0x2005)) {
        final metadata = run.canonHostMetadata[handle];
        if (metadata != null) {
          _validatePhoto(metadata);
          return (info: metadata, fromCanonEvent: true);
        }
      }
      rethrow;
    }
  }

  Future<void> _discoverCardPhoto(
    _TetherRun run,
    int handle, {
    bool existing = false,
  }) async {
    // Busy metadata is retried on a later poll, so one writing photo cannot
    // spend several request/retry delays ahead of every other burst image.
    final metadata = await _photoMetadata(run, handle, busyRetries: 0);
    _checkActive(run);
    final info = metadata.info;
    if (!_isPhoto(info)) {
      if (info.format == 0x3001 ||
          const {
            'mp4',
            'mov',
            'avi',
            'wav',
            'mp3',
            'xmp',
            'thm',
            'ctg',
            'xml',
          }.contains(info.name.split('.').last.toLowerCase())) {
        run.ignoredHandles.add(handle);
        run.observedHandles.add(handle);
        run.eventHandles.remove(handle);
        return;
      }
      throw PlatformException(
        code: 'CAMERA_FILE_NOT_READY',
        message:
            'The camera has not finished this photo’s filename and metadata.',
      );
    }
    if (existing && info.size > _maxPhotoBytes) {
      // One old, permanently unsupported file must not pin the entire backlog
      // ahead of later valid photos. Do not read or delete its camera original.
      run.ignoredHandles.add(handle);
      run.observedHandles.add(handle);
      run.eventHandles.remove(handle);
      _emit(
        run,
        'error',
        '${info.name} exceeds the 512 MB camera transfer limit and was skipped. '
            'Other photos continue uploading; the original remains on the camera.',
        code: 'TETHER_FILE_TOO_LARGE',
      );
      return;
    }
    _validatePhoto(info);
    final queued = run.pending[run.currentIds[handle]];
    if (queued != null &&
        queued.info.name == info.name &&
        (queued.info.captureDate.isEmpty ||
            info.captureDate.isEmpty ||
            queued.info.captureDate == info.captureDate)) {
      queued.info = info;
      queued.usesCanonEventMetadata = metadata.fromCanonEvent;
      run.observedHandles.add(handle);
      run.eventHandles.remove(handle);
      return;
    }
    final id = _photoId(run, handle, info, run.generations[handle] ?? 0);
    if (!run.delivered.contains(id)) {
      run.pending.putIfAbsent(
        id,
        () => _TetherPhoto(
          id: id,
          handle: handle,
          info: info,
          hostTransfer: run.hostTransferHandles.contains(handle),
          usesCanonEventMetadata: metadata.fromCanonEvent,
          existing: existing,
        ),
      );
    }
    run.currentIds[handle] = id;
    run.observedHandles.add(handle);
    run.eventHandles.remove(handle);
  }

  Future<void> _refreshSony(_TetherRun run) async {
    await _readSonyProperties(run);
    if (run.sonyProperties[0xd25a]?.intValue != 0 ||
        run.sonyProperties[0xd222]?.intValue != 17) {
      throw PlatformException(
        code: 'TETHER_MODE_CHANGED',
        message:
            'Sony Camera priority or PC + Camera recording changed. Start a new session after restoring those settings.',
      );
    }
    // One pending logical object per fixed handle. The complete native download
    // advances Sony's RAM queue; acknowledge local persistence before discovering
    // the next entry, even if its name and size are identical.
    if (run.pending.values.any((photo) => photo.sonyMemory)) return;
    final available = run.sonyProperties[0xd215]?.intValue;
    if (available == null) {
      throw PlatformException(
        code: 'PTP_INVALID_RESPONSE',
        message: 'Sony photo queue state is missing.',
      );
    }
    if (available <= 0x8000) return;
    final response = await _command(run, 0x1008, params: [_sonyMemoryHandle]);
    final info = PtpTetherCodec.decodeObjectInfo(
      response.data,
      handle: _sonyMemoryHandle,
    );
    if (!_isPhoto(info)) {
      throw PlatformException(
        code: 'TETHER_FILE_FORMAT_UNSUPPORTED',
        message:
            'The Sony transfer queue contains a file that is not a supported still photo. Transfer it with the camera software before continuing.',
      );
    }
    _validatePhoto(info);
    final id = _photoId(
      run,
      _sonyMemoryHandle,
      info,
      ++run.sonySequence,
      sessionScoped: true,
    );
    run.pending[id] = _TetherPhoto(
      id: id,
      handle: _sonyMemoryHandle,
      info: info,
      sonyMemory: true,
    );
  }

  bool _isPhoto(PtpObjectInfo info) =>
      info.format != 0x3001 &&
      _extensions.contains(info.name.split('.').last.toLowerCase());

  void _validatePhoto(PtpObjectInfo info) {
    if (info.size <= 0 || info.size > _maxPhotoBytes || info.name.isEmpty) {
      throw PlatformException(
        code: info.size <= 0
            ? 'CAMERA_FILE_NOT_READY'
            : 'TETHER_FILE_TOO_LARGE',
        message: info.size <= 0
            ? 'The camera is still finishing this photo. It will be checked again.'
            : 'This camera file is larger than the supported 512 MB photo transfer limit.',
      );
    }
  }

  String _photoId(
    _TetherRun run,
    int handle,
    PtpObjectInfo info,
    int generation, {
    bool sessionScoped = false,
  }) =>
      '${run.connection!.cameraId}|${sessionScoped ? run.id : "card"}|'
      '$handle|${info.name.length}:${info.name}|'
      '${info.captureDate}|$generation';

  _TetherRun _run(String sessionId, {bool allowClosed = false}) {
    final run = _runs[sessionId];
    if (run == null || (!allowClosed && (run.closed || run.stopping))) {
      throw PlatformException(
        code: 'LIVE_CAMERA_SESSION_ENDED',
        message: 'This camera session has ended.',
      );
    }
    return run;
  }

  @override
  Future<List<ConnectedCameraImage>> pending(String sessionId) async {
    final run = _run(sessionId);
    await _refresh(run);
    final ordered = uploadMode == LiveCameraUploadMode.existingAndNew
        ? [
            ...run.pending.values.where((photo) => !photo.existing),
            ...run.pending.values.where((photo) => photo.existing),
          ]
        : run.pending.values;
    return ordered
        .map(
          (photo) => ConnectedCameraImage(
            id: photo.id,
            name: photo.info.name,
            size: photo.info.size,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<OtgPickedFile> download(String sessionId, String imageId) {
    final run = _run(sessionId);
    return _serial(run, () async {
      final photo = run.pending[imageId];
      if (photo == null) throw PlatformException(code: 'CAMERA_FILES_MISSING');
      final staged = photo.staged;
      if (staged != null) {
        if (await _stagedFileExists(staged)) return staged;
        // A consumed Sony buffer must never be re-read under the old ID.
        if (photo.sonyMemory) {
          throw PlatformException(
            code: 'PTP_STAGED_FILE_MISSING',
            message:
                'The received Sony photo’s local copy is missing. Its camera-card original is preserved.',
          );
        }
      }
      if (!photo.sonyMemory && !photo.usesCanonEventMetadata) {
        // Some cameras publish metadata before the final file length is known.
        // Refresh it on each download attempt without changing this delivery ID.
        final metadata = await _photoMetadata(run, photo.handle);
        final latest = metadata.info;
        if (latest.name != photo.info.name ||
            (latest.captureDate.isNotEmpty &&
                photo.info.captureDate.isNotEmpty &&
                latest.captureDate != photo.info.captureDate)) {
          throw PlatformException(
            code: 'CAMERA_FILES_MISSING',
            message:
                'The original camera photo was replaced before it could be copied.',
          );
        }
        _validatePhoto(latest);
        photo.info = latest;
        photo.usesCanonEventMetadata = metadata.fromCanonEvent;
      }
      final partialOpcode = photo.sonyMemory || run.fullObjectOnly
          ? null
          : run.operations.contains(0x101b)
          ? 0x101b
          : run.family == _TetherFamily.canonEos &&
                run.operations.contains(0x9107)
          ? 0x9107
          : null;
      PtpShootingSafety.requirePassive(
        partialOpcode ?? 0x1009,
        vendorId: run.connection?.vendorId ?? 0,
      );
      final file = await _link.download(
        sessionId,
        transferId: photo.id,
        handle: photo.handle,
        name: photo.info.name,
        expectedSize: photo.info.size,
        partialOpcode: partialOpcode,
      );
      photo.staged = OtgPickedFile(
        path: file.path,
        name: photo.info.name,
        id: photo.id,
      );
      // A fully received file remains saveable by its original session even if
      // Stop wins just after the native file flush completes.
      return photo.staged!;
    });
  }

  @override
  Future<void> acknowledge(String sessionId, List<String> imageIds) async {
    final run = _runs[sessionId];
    if (run == null) {
      await _link.acknowledge(sessionId, imageIds);
      return;
    }
    Future<void> finish() async {
      for (final id in imageIds) {
        final photo = run.pending[id];
        if (photo == null) continue;
        if (photo.hostTransfer &&
            !run.closed &&
            !run.stopping &&
            !run.disconnected) {
          _requireOperations(run, [0x9117]);
          await _command(run, 0x9117, params: [photo.handle]);
        }
        await _link.acknowledge(sessionId, [id]);
        run.delivered.add(id);
        run.pending.remove(id);
        run.hostTransferHandles.remove(photo.handle);
        if (identical(run.canonHostMetadata[photo.handle], photo.info)) {
          run.canonHostMetadata.remove(photo.handle);
        }
      }
      if (run.ready &&
          run.pending.values.where((photo) => photo.existing).length <
              _maxExistingPending &&
          _hasReadyExistingWork(run)) {
        _emit(run, 'photosAvailable', 'Receiving more existing camera photos…');
      }
    }

    if (run.closed || run.stopping || run.disconnected) {
      // Exact-token release remains valid after Stop, but no camera command is
      // sent into a later session. Camera originals are not deleted.
      await _link.acknowledge(sessionId, imageIds);
      for (final id in imageIds) {
        run.pending.remove(id);
      }
      if (run.closed && run.pending.isEmpty) _runs.remove(sessionId);
    } else {
      await _serial(run, finish);
    }
  }

  @override
  Future<void> stop(String sessionId) {
    final run = _runs[sessionId];
    if (run == null) return _link.close(sessionId);
    final current = run.closing;
    if (current != null) return current;
    run.stopping = true;
    run.ready = false;
    run.timer?.cancel();
    final closing = _close(run);
    run.closing = closing;
    return closing;
  }

  Future<void> _close(_TetherRun run) async {
    var idle = false;
    try {
      await run.tail.timeout(stopGracePeriod);
      idle = true;
    } on TimeoutException {
      // Closing native USB aborts a stalled transaction. Never queue rollback
      // bytes into an in-flight PTP data stream.
    }
    PlatformException? releaseFailure;
    if (run.olympusRestoreRequired && !idle && !run.disconnected) {
      releaseFailure = PlatformException(
        code: 'TETHER_RELEASE_INCOMPLETE',
        message:
            'The OM camera did not finish its USB command in time. '
            'Unplug USB and check its screen and physical controls.',
      );
    }
    if (idle &&
        (!run.disconnected || run.canReleaseAfterError) &&
        run.connection != null) {
      var rollbackStreamUsable = true;
      Future<void> bestEffort(int opcode, List<int> params) async {
        if (!rollbackStreamUsable) return;
        try {
          await _command(
            run,
            opcode,
            params: params,
            duringClose: true,
          ).timeout(const Duration(seconds: 2));
        } on TimeoutException {
          // Do not queue another mode command while this response is unresolved.
          rollbackStreamUsable = false;
        } catch (_) {}
      }

      if (run.olympusRestoreRequired) {
        try {
          final original = run.olympusOriginalControlMode!;
          await _command(
            run,
            0x1016,
            params: [0xd052],
            data: PtpTetherCodec.encodeValue(4, original),
            duringClose: true,
          ).timeout(const Duration(seconds: 2));
          final reply = await _command(
            run,
            0x1015,
            params: [0xd052],
            duringClose: true,
          ).timeout(const Duration(seconds: 2));
          if (PtpTetherCodec.decodeValue(4, reply.data) != original) {
            throw const FormatException('OM connection mode was not restored');
          }
          run.olympusRestoreRequired = false;
        } catch (_) {
          rollbackStreamUsable = false;
          releaseFailure = PlatformException(
            code: 'TETHER_RELEASE_INCOMPLETE',
            message:
                'OM camera control restoration could not be confirmed. '
                'Unplug USB and check the camera screen and physical controls.',
          );
        }
      }
      if (run.canonRemote) {
        // Same display-restoration sequence used by the upstream EOS protocol.
        // Card recording is retained; never leave a body in host-only RAM mode.
        await bestEffort(0x9114, [0]);
        await bestEffort(0x9114, [1]);
      }
      if (run.canonEvents) await bestEffort(0x9115, [0]);
      if (run.nikonBodyMode) await bestEffort(0x90c2, [0]);
      // Sony Connect phase 3 is the final OPEN phase, not a disconnect command.
      // Close the standard native session; do not change priority to Application
      // or put recording back into a RAM-only destination during shutdown.
    }
    if (releaseFailure != null) {
      _emit(run, 'error', releaseFailure.message!, code: releaseFailure.code);
    }
    try {
      await _link.close(run.id);
    } finally {
      run.closed = true;
      if (identical(_active, run)) _active = null;
      await run.subscription?.cancel();
      if (!run.events.isClosed) await run.events.close();
      _eventStreams.remove(run.id);
      // Keep completed native files addressable until their local-save ACK.
      run.pending.removeWhere((_, photo) => photo.staged == null);
      if (run.pending.isEmpty) _runs.remove(run.id);
    }
    if (releaseFailure != null) throw releaseFailure;
  }
}
