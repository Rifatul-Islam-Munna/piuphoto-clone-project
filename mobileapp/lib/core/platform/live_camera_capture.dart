import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mobileapp/core/platform/otg_file_picker.dart';
import 'package:mobileapp/core/platform/live_camera_types.dart';
import 'package:mobileapp/core/platform/ptp_tether_camera.dart';

export 'live_camera_types.dart';

/// Live receiving needs a shooting protocol, not merely a readable catalog.
/// Never fall back to MTP/Mass Storage when tether negotiation fails.
LiveCameraTransport preferredUsbCameraTransport({
  required TargetPlatform platform,
  required LiveCameraUploadMode uploadMode,
}) {
  return PtpTetherCameraTransport(
    uploadMode: uploadMode,
    eventPollInterval: const Duration(seconds: 3),
    cardScanInterval: const Duration(seconds: 3),
  );
}

class NativeLiveCameraTransport implements LiveCameraTransport {
  const NativeLiveCameraTransport({
    this.uploadMode = LiveCameraUploadMode.newShotsOnly,
  });

  final LiveCameraUploadMode uploadMode;
  static const _methods = MethodChannel('airpix/otg_picker');
  static const _events = EventChannel('airpix/otg_live');

  @override
  Stream<LiveCameraEvent> eventsForSession(String sessionId) => _events
      .receiveBroadcastStream({'sessionId': sessionId})
      .where((value) => value is Map)
      .map(
        (value) =>
            LiveCameraEvent.fromMap(Map<Object?, Object?>.from(value as Map)),
      );

  @override
  Future<LiveCameraSession> start(String sessionId) async {
    final data = await _methods.invokeMapMethod<Object?, Object?>(
      'startLiveCameraSession',
      {'sessionId': sessionId, 'uploadMode': uploadMode.name},
    );
    return LiveCameraSession.fromMap(data ?? const {});
  }

  @override
  Future<void> stop(String sessionId) => _methods.invokeMethod<void>(
    'stopLiveCameraSession',
    {'sessionId': sessionId},
  );

  @override
  Future<List<ConnectedCameraImage>> pending(String sessionId) async {
    final data = await _methods.invokeListMethod<Object?>(
      'pendingLiveCameraImages',
      {'sessionId': sessionId},
    );
    return (data ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map(ConnectedCameraImage.fromMap)
        .where((image) => image.id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<OtgPickedFile> download(String sessionId, String imageId) async {
    final data = await _methods.invokeMapMethod<Object?, Object?>(
      'downloadLiveCameraImage',
      {'sessionId': sessionId, 'id': imageId},
    );
    final path = data?['path']?.toString() ?? '';
    final name = data?['name']?.toString() ?? '';
    if (path.isEmpty || name.isEmpty || data?['id']?.toString() != imageId) {
      throw PlatformException(
        code: 'CAMERA_IMPORT_FAILED',
        message: 'The camera did not provide a complete photo. Retrying.',
      );
    }
    return OtgPickedFile(path: path, name: name, id: imageId);
  }

  @override
  Future<void> acknowledge(String sessionId, List<String> imageIds) =>
      _methods.invokeMethod<void>('acknowledgeLiveCameraImages', {
        'sessionId': sessionId,
        'ids': imageIds,
      });
}

enum LiveCameraPhase {
  connecting,
  waiting,
  importing,
  stopped,
  disconnected,
  error,
}

class LiveCameraUpdate {
  const LiveCameraUpdate(
    this.phase,
    this.message, {
    this.code,
    this.savedPhotos = 0,
  });

  final LiveCameraPhase phase;
  final String message;
  final String? code;
  final int savedPhotos;
}

typedef SaveLiveCameraPhoto =
    Future<void> Function(OtgPickedFile file, LiveCameraSession session);

class _CaptureRun {
  _CaptureRun(this.id, this.save);

  final String id;
  final SaveLiveCameraPhoto save;
  LiveCameraSession? session;
  StreamSubscription<LiveCameraEvent>? subscription;
  Timer? timer;
  Future<void>? drain;
  bool active = true;
  bool pollAgain = false;
  final Set<String> savedIds = {};
  final Set<String> pendingAcks = {};
  final Map<String, DateTime> retryAfter = {};
  final Map<String, OtgPickedFile> staged = {};
}

/// Keeps camera delivery independent from internet speed. Native notifications
/// are hints; a photo stays pending until the local upload queue has saved it.
class LiveCameraCapture {
  LiveCameraCapture({
    LiveCameraTransport? transport,
    this.uploadMode = LiveCameraUploadMode.newShotsOnly,
    required this.onUpdate,
    // Poll even without shutter notifications. A running drain is coalesced.
    this.pollInterval = const Duration(seconds: 3),
    this.retryDelay = const Duration(seconds: 3),
    DateTime Function()? now,
    Future<bool> Function(OtgPickedFile)? isStagedFileUsable,
  }) : _transport =
           transport ??
           preferredUsbCameraTransport(
             platform: Platform.isIOS
                 ? TargetPlatform.iOS
                 : Platform.isAndroid
                 ? TargetPlatform.android
                 : TargetPlatform.windows,
             uploadMode: uploadMode,
           ),
       _now = now ?? DateTime.now,
       _isStagedFileUsable = isStagedFileUsable ?? _fileIsUsable;

  final LiveCameraTransport _transport;
  final LiveCameraUploadMode uploadMode;
  final void Function(LiveCameraUpdate) onUpdate;
  final Duration pollInterval;
  final Duration retryDelay;
  final DateTime Function() _now;
  final Future<bool> Function(OtgPickedFile) _isStagedFileUsable;
  static int _serial = 0;
  int _operation = 0;
  bool _starting = false;
  _CaptureRun? _run;

  static Future<bool> _fileIsUsable(OtgPickedFile file) async {
    try {
      final staged = File(file.path);
      return await staged.exists() && await staged.length() > 0;
    } on FileSystemException {
      return false;
    }
  }

  bool get isActive => _run?.active == true;
  bool _current(_CaptureRun run) => identical(_run, run) && run.active;

  Future<LiveCameraSession> start({required SaveLiveCameraPhoto save}) async {
    if (_starting) throw PlatformException(code: 'LIVE_CAMERA_BUSY');
    _starting = true;
    final operation = ++_operation;
    try {
      await _stopCurrent(notify: false);
      if (operation != _operation) {
        throw PlatformException(code: 'LIVE_CAMERA_CANCELLED');
      }
      final run = _CaptureRun(
        'live-${_now().microsecondsSinceEpoch}-${++_serial}',
        save,
      );
      _run = run;
      onUpdate(
        const LiveCameraUpdate(
          LiveCameraPhase.connecting,
          'Detecting the camera and preparing live shooting. Wait for the ready message before taking a new photo.',
        ),
      );
      run.subscription = _transport
          .eventsForSession(run.id)
          .listen(
            (event) => _handleEvent(run, event),
            onError: (Object error) {
              // Polling still retrieves native pending objects if a notification is lost.
              if (_current(run)) {
                onUpdate(
                  LiveCameraUpdate(
                    run.session == null
                        ? LiveCameraPhase.connecting
                        : LiveCameraPhase.waiting,
                    'Camera notifications interrupted; checking for new photos periodically.',
                    savedPhotos: run.savedIds.length,
                  ),
                );
              }
            },
          );
      try {
        final session = await _transport.start(run.id);
        if (!_current(run)) {
          await _transport.stop(run.id);
          throw PlatformException(code: 'LIVE_CAMERA_CANCELLED');
        }
        if (session.id != run.id) {
          throw PlatformException(code: 'LIVE_CAMERA_INVALID_SESSION');
        }
        run.session = session;
        onUpdate(LiveCameraUpdate(LiveCameraPhase.waiting, session.message));
        run.timer = Timer.periodic(pollInterval, (_) => unawaited(poll()));
        unawaited(poll());
        return session;
      } catch (_) {
        if (_current(run)) {
          try {
            await stop(notify: false);
          } catch (_) {
            // Preserve the actual startup error for actionable UI guidance.
          }
        }
        rethrow;
      }
    } finally {
      _starting = false;
    }
  }

  void _handleEvent(_CaptureRun run, LiveCameraEvent event) {
    if (!_current(run) || event.sessionId != run.id) return;
    if (event.type == 'disconnected') {
      unawaited(_disconnect(run, event.message, event.code));
    } else if (event.type == 'photosAvailable') {
      if (run.drain != null) run.pollAgain = true;
      unawaited(poll());
    } else if (event.type == 'error') {
      onUpdate(
        LiveCameraUpdate(
          LiveCameraPhase.error,
          event.message,
          code: event.code,
          savedPhotos: run.savedIds.length,
        ),
      );
    } else if (event.message.isNotEmpty && run.drain == null) {
      onUpdate(
        LiveCameraUpdate(
          run.session == null
              ? LiveCameraPhase.connecting
              : LiveCameraPhase.waiting,
          event.message,
          savedPhotos: run.savedIds.length,
        ),
      );
    }
  }

  Future<void> _disconnect(
    _CaptureRun run,
    String message,
    String? code,
  ) async {
    if (!_current(run)) return;
    Object? releaseError;
    try {
      await stop(notify: false);
    } catch (error) {
      releaseError = error;
    }
    if (_run == null) {
      onUpdate(
        LiveCameraUpdate(
          LiveCameraPhase.disconnected,
          releaseError != null
              ? _releaseFailureMessage(releaseError)
              : message.isEmpty
              ? 'Camera disconnected. Reconnect and start live shooting again.'
              : message,
          code: releaseError is PlatformException
              ? releaseError.code
              : releaseError != null
              ? 'PTP_CLOSE_FAILED'
              : code,
          savedPhotos: run.savedIds.length,
        ),
      );
    }
  }

  Future<void> poll() {
    final run = _run;
    if (run == null || !_current(run) || run.session == null) {
      return Future.value();
    }
    final currentDrain = run.drain;
    if (currentDrain != null) {
      return currentDrain;
    }
    final future = _drain(run);
    run.drain = future;
    return future.whenComplete(() {
      run.drain = null;
      if (_current(run) && run.pollAgain) {
        run.pollAgain = false;
        unawaited(poll());
      }
    });
  }

  Future<void> _drain(_CaptureRun run) async {
    try {
      if (run.pendingAcks.isNotEmpty) {
        final ids = run.pendingAcks.toList(growable: false);
        await _transport.acknowledge(run.id, ids);
        run.pendingAcks.removeAll(ids);
      }
      if (!_current(run)) return;
      final pending = await _transport.pending(run.id);
      final unique = {for (final image in pending) image.id: image};
      for (final image in unique.values) {
        if (!_current(run)) return;
        if (run.savedIds.contains(image.id)) continue;
        if (run.retryAfter[image.id]?.isAfter(_now()) == true) continue;
        try {
          onUpdate(
            LiveCameraUpdate(
              LiveCameraPhase.importing,
              'Receiving ${image.name} from camera...',
              savedPhotos: run.savedIds.length,
            ),
          );
          final staged = run.staged[image.id];
          if (staged != null && !await _isStagedFileUsable(staged)) {
            run.staged.remove(image.id);
          }
          final file =
              run.staged[image.id] ??
              await _transport.download(run.id, image.id);
          run.staged[image.id] = file;
          // Finish saving a download that was already in flight when Stop was
          // pressed. The callback captures its original event/album destination.
          await run.save(file, run.session!);
          run.savedIds.add(image.id);
          run.staged.remove(image.id);
          run.pendingAcks.add(image.id);
          run.retryAfter.remove(image.id);
          if (!_current(run)) {
            // Exact-token ACK is safe after Stop/disconnect and lets native
            // code release old staging bookkeeping after this copy finishes.
            try {
              await _transport.acknowledge(run.id, [image.id]);
            } catch (_) {}
            return;
          }
          await _transport.acknowledge(run.id, [image.id]);
          run.pendingAcks.remove(image.id);
          onUpdate(
            LiveCameraUpdate(
              LiveCameraPhase.waiting,
              'Received ${run.savedIds.length} photo(s). ${file.name} will upload to the cloud automatically. Keep shooting.',
              savedPhotos: run.savedIds.length,
            ),
          );
          if (run.session!.uploadMode == LiveCameraUploadMode.existingAndNew) {
            // Refresh the transport's priority order between complete files.
            // A new shutter event must not sit behind a snapshot of old photos.
            run.pollAgain = true;
            return;
          }
        } catch (error) {
          if (!_current(run)) return;
          if (error is PlatformException &&
              const {
                'PTP_STAGED_FILE_MISSING',
                'PTP_TRANSFER_NOT_RECOVERABLE',
                'PTP_STAGING_FAILED',
                'PTP_SESSION_CLOSED',
                'PTP_TRANSPORT_FAILED',
              }.contains(error.code)) {
            await _disconnect(run, _message(error), error.code);
            return;
          }
          run.retryAfter[image.id] = _now().add(retryDelay);
          onUpdate(
            LiveCameraUpdate(
              LiveCameraPhase.error,
              'Could not finish ${image.name}; it remains pending and will retry. ${_message(error)}',
              code: error is PlatformException ? error.code : null,
              savedPhotos: run.savedIds.length,
            ),
          );
        }
      }
    } catch (error) {
      if (!_current(run)) return;
      final code = error is PlatformException ? error.code : null;
      if (const {
        'LIVE_CAMERA_SESSION_ENDED',
        'LIVE_CAMERA_SESSION_MISMATCH',
        'LIVE_CAMERA_NOT_RUNNING',
        'LIVE_CAMERA_SESSION_NOT_FOUND',
        'CAMERA_SESSION_ENDED',
        'CAMERA_STORAGE_CHANGED',
        'USB_CAMERA_DISCONNECTED',
        'NO_CAMERA_CONNECTED',
        'PTP_SESSION_CLOSED',
        'PTP_TRANSPORT_FAILED',
        'PTP_TETHER_TIMEOUT',
        'PTP_TIMEOUT',
        'TETHER_MODE_CHANGED',
      }.contains(code)) {
        await _disconnect(run, _message(error), code);
      } else {
        onUpdate(
          LiveCameraUpdate(
            LiveCameraPhase.error,
            'Camera check will retry. ${_message(error)}',
            code: code,
            savedPhotos: run.savedIds.length,
          ),
        );
      }
    }
  }

  String _message(Object error) => error is PlatformException
      ? (error.message ?? error.code)
      : error.toString();

  String _releaseFailureMessage(Object error) =>
      'Receiving stopped, but the phone could not confirm that the camera '
      'connection was released. Disconnect the USB cable before reconnecting. '
      'Photos already received continue uploading to cloud. ${_message(error)}';

  Future<void> stop({bool notify = true}) {
    _operation++;
    return _stopCurrent(notify: notify);
  }

  Future<void> _stopCurrent({required bool notify}) async {
    final run = _run;
    if (run == null) return;
    run.active = false;
    _run = null;
    run.timer?.cancel();
    try {
      await run.subscription?.cancel();
    } catch (_) {
      // A notification cleanup error must not prevent releasing the camera.
    }
    try {
      await _transport.stop(run.id);
    } catch (error) {
      if (notify && _run == null) {
        onUpdate(
          LiveCameraUpdate(
            LiveCameraPhase.error,
            _releaseFailureMessage(error),
            code: error is PlatformException ? error.code : 'PTP_CLOSE_FAILED',
            savedPhotos: run.savedIds.length,
          ),
        );
      }
      rethrow;
    }
    if (notify && _run == null) {
      onUpdate(
        LiveCameraUpdate(
          LiveCameraPhase.stopped,
          'Live shooting stopped. Cloud uploads continue automatically for photos already received.',
          savedPhotos: run.savedIds.length,
        ),
      );
    }
  }
}
