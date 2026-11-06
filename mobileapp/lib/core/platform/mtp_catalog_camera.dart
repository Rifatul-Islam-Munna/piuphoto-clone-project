import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mobileapp/core/platform/live_camera_types.dart';
import 'package:mobileapp/core/platform/otg_file_picker.dart';
import 'package:mobileapp/core/platform/transfer_screen_awake.dart';

/// Android's passive MTP/PTP photo-catalog reader, based on the original
/// AirPix camera-to-cloud implementation. It NEVER sends a remote-shutter,
/// USB-mode, camera-recording-destination or vendor-control command.
///
/// Native Android opens MtpDevice only for listing/importing objects and
/// closes it after each request. This works only when the camera's selected
/// USB mode exposes files while the physical shutter remains operational.
/// There is intentionally no Mass Storage / folder-picker fallback here.
class MtpCatalogCameraTransport implements LiveCameraTransport {
  MtpCatalogCameraTransport({
    this.uploadMode = LiveCameraUploadMode.newShotsOnly,
  });

  final LiveCameraUploadMode uploadMode;
  _CatalogSession? _session;
  int _generation = 0;

  @override
  Stream<LiveCameraEvent> eventsForSession(String sessionId) =>
      const Stream<LiveCameraEvent>.empty();

  static bool _storageOnly(String name) {
    final lower = name.toLowerCase();
    return lower.contains('mass storage') ||
        lower.contains('card reader') ||
        lower.contains('usb drive') ||
        lower.contains('flash drive') ||
        lower.contains('external disk');
  }

  @override
  Future<LiveCameraSession> start(String sessionId) async {
    if (_session != null) throw PlatformException(code: 'LIVE_CAMERA_BUSY');
    final generation = ++_generation;
    var devices = await OtgFilePicker.connectedCameraDevices();
    if (devices.isNotEmpty && devices.any((device) => !device.hasPermission)) {
      // Android asks for the USB permission on the first camera query.
      await OtgFilePicker.connectedCameraImages(limit: 1);
      devices = await OtgFilePicker.connectedCameraDevices();
    }
    if (generation != _generation) {
      throw PlatformException(code: 'LIVE_CAMERA_CANCELLED');
    }
    final candidates = devices
        .where(
          // Native discovery includes camera-maker vendor interfaces that
          // may not advertise USB class 6. A successful catalog read below
          // verifies PTP/MTP access; merely advertising the class does not.
          (device) => device.hasPermission && !_storageOnly(device.name),
        )
        .toList(growable: false);
    if (candidates.isEmpty) {
      throw PlatformException(
        code: 'TETHER_MODE_UNSUPPORTED',
        message:
            'No accessible PTP/MTP camera photo catalog is available. '
            'Check the camera USB mode and cable. AirPix will not switch '
            'into Mass Storage or open a file picker for live receiving.',
      );
    }
    if (candidates.length != 1) {
      throw PlatformException(
        code: 'MULTIPLE_CAMERAS',
        message:
            'Connect one supported USB camera at a time for live receiving.',
      );
    }
    final device = candidates.single;
    final catalog = await OtgFilePicker.connectedCameraImages();
    if (generation != _generation) {
      throw PlatformException(code: 'LIVE_CAMERA_CANCELLED');
    }
    final existing = catalog
        .where((image) => image.id.startsWith('${device.id}|'))
        .toList(growable: false);
    final run = _CatalogSession(id: sessionId, camera: device);
    run.known.addAll(existing.map((image) => image.id));
    if (uploadMode == LiveCameraUploadMode.existingAndNew) {
      for (final image in existing.reversed) {
        if (image.size > 0) run.pending[image.id] = image;
      }
    }
    _session = run;
    // Keep Flutter's foreground 3-second polling alive during the shoot.
    // This changes phone wake state only, never camera USB mode.
    await TransferScreenAwake.setEnabled('usb-mtp:$sessionId', true);
    return LiveCameraSession(
      id: sessionId,
      cameraId: device.id,
      name: device.name,
      physicalShutter: 'unknown',
      message: uploadMode == LiveCameraUploadMode.existingAndNew
          ? 'PTP/MTP photo catalog connected. Importing older photos and '
                'checking for new camera photos every three seconds. '
                'Make sure the physical shutter remains usable.'
          : 'PTP/MTP photo catalog connected. Existing photos skipped; '
                'AirPix checks for newly available photos every three '
                'seconds without changing the camera shooting mode. '
                'Confirm the physical shutter stays usable.',
      baselineCount: existing.length,
      uploadMode: uploadMode,
    );
  }

  _CatalogSession _require(String sessionId) {
    final run = _session;
    if (run == null || run.id != sessionId) {
      throw PlatformException(
        code: 'LIVE_CAMERA_SESSION_ENDED',
        message: 'This USB camera receiving session has ended.',
      );
    }
    return run;
  }

  @override
  Future<List<ConnectedCameraImage>> pending(String sessionId) async {
    final run = _require(sessionId);
    final snapshot = await OtgFilePicker.connectedCameraImages();
    if (!identical(run, _session)) {
      throw PlatformException(code: 'LIVE_CAMERA_CANCELLED');
    }
    // Android object IDs are "<USB deviceId>|<PTP object handle>".
    final current = snapshot.where(
      (image) => image.id.startsWith('${run.camera.id}|'),
    );
    for (final image in current) {
      // Do not permanently mark a new zero-byte object as already handled:
      // it might become readable only after the physical shutter finishes.
      if (image.size > 0 && run.known.add(image.id)) {
        run.pending[image.id] = image;
      }
      // A newly announced object can initially have incomplete metadata.
      // Keep its original delivery identity while the camera writes bytes.
      if (run.pending.containsKey(image.id) && image.size > 0) {
        run.pending[image.id] = image;
      }
    }
    if (snapshot.isEmpty) {
      final connected = await OtgFilePicker.connectedCameraDevices();
      if (!connected.any((device) => device.id == run.camera.id)) {
        throw PlatformException(
          code: 'USB_CAMERA_DISCONNECTED',
          message: 'USB camera disconnected; saved files remain queued.',
        );
      }
    }
    return run.pending.values.where((image) => image.size > 0).toList();
  }

  @override
  Future<OtgPickedFile> download(String sessionId, String imageId) async {
    final run = _require(sessionId);
    final requested = run.pending[imageId];
    if (requested == null || requested.size <= 0) {
      throw PlatformException(
        code: 'CAMERA_FILE_NOT_READY',
        message: 'The camera is still writing this photo.',
      );
    }
    final imports = await OtgFilePicker.importConnectedCameraImages([imageId]);
    if (!identical(run, _session)) {
      throw PlatformException(code: 'LIVE_CAMERA_CANCELLED');
    }
    OtgPickedFile? staged;
    for (final file in imports) {
      if (file.id == imageId) {
        staged = file;
        break;
      }
    }
    if (staged == null) {
      throw PlatformException(
        code: 'CAMERA_FILE_NOT_READY',
        message: 'The camera has not finished transferring this photo.',
      );
    }
    final file = File(staged.path);
    final int length;
    try {
      length = await file.length();
    } on FileSystemException {
      throw PlatformException(
        code: 'CAMERA_FILE_NOT_READY',
        message: 'The staged photo is not yet available. AirPix will retry.',
      );
    }
    if (length == 0 || (requested.size > 0 && length != requested.size)) {
      try {
        await file.delete();
      } on FileSystemException {
        // Staged file can be retried from the untouched camera original.
      }
      throw PlatformException(
        code: 'CAMERA_FILE_NOT_READY',
        message: 'The camera photo is incomplete; AirPix will retry.',
      );
    }
    return staged;
  }

  @override
  Future<void> acknowledge(String sessionId, List<String> imageIds) async {
    final run = _require(sessionId);
    for (final id in imageIds) {
      run.pending.remove(id);
    }
    // Never delete or acknowledge objects on the camera itself.
  }

  @override
  Future<void> stop(String sessionId) async {
    final owned = _session?.id == sessionId;
    if (owned) _session = null;
    ++_generation;
    if (owned) {
      await TransferScreenAwake.setEnabled('usb-mtp:$sessionId', false);
    }
    // Every native list/import operation closes its own MtpDevice. No
    // remote-control mode or long-lived camera USB owner is held here.
  }
}

class _CatalogSession {
  _CatalogSession({required this.id, required this.camera});

  final String id;
  final ConnectedCameraDevice camera;
  final Set<String> known = <String>{};
  final Map<String, ConnectedCameraImage> pending =
      <String, ConnectedCameraImage>{};
}
