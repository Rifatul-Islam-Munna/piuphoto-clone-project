import 'dart:async';

import 'package:flutter/services.dart';
import 'package:mobileapp/core/platform/live_camera_types.dart';
import 'package:mobileapp/core/platform/otg_file_picker.dart';

class _AdaptiveUsbRun {
  _AdaptiveUsbRun(this.id, this.events);

  final String id;
  final StreamController<LiveCameraEvent> events;
  LiveCameraTransport? source;
  LiveCameraTransport? selected;
  StreamSubscription<LiveCameraEvent>? forwarder;
  DateTime? lastCatalogRead;
  bool stopped = false;
}

/// iOS: try the vendor's shooting-capable PTP protocol first. If initial
/// negotiation cannot work, read the existing ImageCaptureCore photo catalog
/// on the SAME camera USB mode. Never select Mass Storage, send a shutter
/// command, or retry a half-finished PTP file transaction.
///
/// Native close MUST be confirmed before the catalog session can start.
class AdaptiveUsbCameraTransport implements LiveCameraTransport {
  AdaptiveUsbCameraTransport({
    required LiveCameraTransport tether,
    required LiveCameraTransport catalog,
    this.catalogPollInterval = const Duration(seconds: 3),
    DateTime Function()? now,
  }) : _tether = tether,
       _catalog = catalog,
       _now = now ?? DateTime.now;

  final LiveCameraTransport _tether;
  final LiveCameraTransport _catalog;
  final Duration catalogPollInterval;
  final DateTime Function() _now;
  final Map<String, StreamController<LiveCameraEvent>> _streams = {};
  final Map<String, _AdaptiveUsbRun> _runs = {};
  final Map<String, LiveCameraTransport> _retired = {};

  static bool recoverableHandshake(PlatformException error) {
    if (error.code == 'PTP_INVALID_RESPONSE') {
      // A malformed reply AFTER vendor setup/download could leave a camera
      // in an unknown state. Recover only from the first, read-only GetDeviceInfo.
      final details = error.details;
      return details is Map && details['operation'] == '0x1001';
    }
    return const {
      'PTP_PASSTHROUGH_UNAVAILABLE',
      'SONY_PTP_CONTROL_UNAVAILABLE',
      'TETHER_CAMERA_UNSUPPORTED',
    }.contains(error.code);
  }

  @override
  Stream<LiveCameraEvent> eventsForSession(String sessionId) => _streams
      .putIfAbsent(
        sessionId,
        () => StreamController<LiveCameraEvent>.broadcast(),
      )
      .stream;

  Future<void> _listen(_AdaptiveUsbRun run, LiveCameraTransport source) async {
    await run.forwarder?.cancel();
    if (run.stopped) {
      throw PlatformException(code: 'LIVE_CAMERA_CANCELLED');
    }
    run.source = source;
    run.forwarder = source
        .eventsForSession(run.id)
        .listen(
          (event) {
            // Native iOS reports a disconnected event when the first PTP
            // handshake fails. Until a reader has successfully started,
            // propagate errors through start(), not as a live disconnect:
            // forwarding it would cancel the entire adaptive recovery.
            if (run.stopped || run.events.isClosed || run.selected != source) {
              return;
            }
            run.events.add(event);
          },
          onError: (Object error, StackTrace stack) {
            if (!run.stopped &&
                !run.events.isClosed &&
                run.selected == source) {
              run.events.addError(error, stack);
            }
          },
        );
  }

  Future<void> _finish(_AdaptiveUsbRun run) async {
    if (identical(_runs[run.id], run)) _runs.remove(run.id);
    await run.forwarder?.cancel();
    run.forwarder = null;
    _streams.remove(run.id);
    if (!run.events.isClosed) await run.events.close();
  }

  @override
  Future<LiveCameraSession> start(String sessionId) async {
    if (_runs.containsKey(sessionId)) {
      throw PlatformException(code: 'LIVE_CAMERA_BUSY');
    }
    final stream = _streams.putIfAbsent(
      sessionId,
      () => StreamController<LiveCameraEvent>.broadcast(),
    );
    final run = _AdaptiveUsbRun(sessionId, stream);
    _runs[sessionId] = run;
    try {
      await _listen(run, _tether);
      try {
        final session = await _tether.start(sessionId);
        if (run.stopped) {
          throw PlatformException(code: 'LIVE_CAMERA_CANCELLED');
        }
        run.selected = _tether;
        return session;
      } on PlatformException catch (initialError) {
        if (run.stopped || !recoverableHandshake(initialError)) rethrow;

        // PTP.start normally closes its native session on failure. Explicitly
        // verify the close result here too. A pending/failed release MUST
        // prevent another transport from taking the device.
        await _tether.stop(sessionId);
        await _listen(run, _catalog);
        try {
          final session = await _catalog.start(sessionId);
          if (run.stopped) {
            throw PlatformException(code: 'LIVE_CAMERA_CANCELLED');
          }
          run.selected = _catalog;
          return LiveCameraSession(
            id: session.id,
            cameraId: session.cameraId,
            name: session.name,
            physicalShutter: session.physicalShutter,
            baselineCount: session.baselineCount,
            uploadMode: session.uploadMode,
            usesPhotoCatalog: true,
            message:
                'PTP control handshake could not start '
                '(${initialError.code}). AirPix is using the camera photo '
                'catalog without changing its USB mode. It checks every '
                '${catalogPollInterval.inSeconds} seconds. Take a test shot '
                'and confirm the camera shutter and display still work. '
                '${session.message}',
          );
        } on PlatformException catch (catalogError) {
          if (catalogError.code == 'LIVE_CAMERA_CANCELLED') rethrow;
          throw PlatformException(
            code: catalogError.code,
            message:
                'Camera PTP handshake failed (${initialError.code}). '
                'The same-mode photo catalog also could not start: '
                '${catalogError.message ?? catalogError.code}',
            details: {
              'ptpFailure': initialError.code,
              if (initialError.details != null)
                'ptpDiagnostics': initialError.details,
              if (catalogError.details != null)
                'catalogDiagnostics': catalogError.details,
            },
          );
        }
      }
    } catch (_) {
      if (identical(run.source, _catalog)) {
        // Also await a native close after a failed catalog open. No implicit
        // device-mode change or silent attempt to claim an unreleased camera.
        try {
          await _catalog.stop(sessionId);
        } catch (_) {}
      }
      await _finish(run);
      rethrow;
    }
  }

  _AdaptiveUsbRun _active(String id) {
    final run = _runs[id];
    if (run == null || run.stopped || run.selected == null) {
      throw PlatformException(
        code: 'CAMERA_SESSION_ENDED',
        message: 'This USB camera receiving session has ended.',
      );
    }
    return run;
  }

  @override
  Future<List<ConnectedCameraImage>> pending(String sessionId) {
    final run = _active(sessionId);
    if (identical(run.selected, _catalog)) {
      final now = _now();
      final last = run.lastCatalogRead;
      if (last != null && now.difference(last) < catalogPollInterval) {
        return Future.value(const <ConnectedCameraImage>[]);
      }
      run.lastCatalogRead = now;
    }
    return run.selected!.pending(sessionId);
  }

  @override
  Future<OtgPickedFile> download(String sessionId, String imageId) =>
      _active(sessionId).selected!.download(sessionId, imageId);

  @override
  Future<void> acknowledge(String sessionId, List<String> imageIds) {
    // A queued file may finish persisting after Stop. Keep exact-session ACK
    // routing to the reader which owned it; never acknowledge another camera.
    final source = _runs[sessionId]?.selected ?? _retired[sessionId];
    if (source == null) return Future.value();
    return source.acknowledge(sessionId, imageIds);
  }

  @override
  Future<void> stop(String sessionId) async {
    final run = _runs[sessionId];
    if (run == null) return;
    run.stopped = true;
    if (run.source != null) {
      _retired[sessionId] = run.source!;
      while (_retired.length > 16) {
        _retired.remove(_retired.keys.first);
      }
    }
    try {
      await run.source?.stop(sessionId);
    } finally {
      await _finish(run);
    }
  }
}
