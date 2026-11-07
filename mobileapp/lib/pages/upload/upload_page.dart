import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:auto_route/auto_route.dart';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobileapp/core/guest/guest_qr_payload.dart';
import 'package:mobileapp/core/guest/guest_qr_preparation.dart';
import 'package:mobileapp/core/guest/guest_face_delivery.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/platform/canon_ccapi_camera.dart';
import 'package:mobileapp/core/platform/camera_ftp_receiver.dart';
import 'package:mobileapp/core/platform/debug_pc_camera_transport.dart';
import 'package:mobileapp/core/platform/transfer_screen_awake.dart';
import 'package:mobileapp/core/platform/device_settings.dart';
import 'package:mobileapp/core/platform/gallery_auto_import.dart';
import 'package:mobileapp/core/platform/live_camera_capture.dart';
import 'package:mobileapp/core/platform/otg_file_picker.dart';
import 'package:mobileapp/core/platform/usb_camera_guidance.dart';
import 'package:mobileapp/core/platform/usb_camera_mode_advisor.dart';
import 'package:mobileapp/core/router/app_router.dart';
import 'package:mobileapp/core/storage/active_event_storage.dart';
import 'package:mobileapp/core/storage/camera_ftp_profile_storage.dart';
import 'package:mobileapp/core/storage/usb_camera_upload_mode_storage.dart';
import 'package:mobileapp/core/storage/user_storage.dart';
import 'package:mobileapp/core/storage/uploaded_gallery_storage.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/core/upload/upload_queue_service.dart';
import 'package:mobileapp/core/upload/camera_staging_cleanup.dart';
import 'package:mobileapp/core/upload/upload_queue_storage.dart';
import 'package:mobileapp/models/album_model.dart';
import 'package:mobileapp/models/event_invitation_model.dart';
import 'package:mobileapp/pages/upload/camera_transfer_page.dart';
import 'package:mobileapp/pages/upload/transfer_list_page.dart';
import 'package:mobileapp/pages/upload/usb_camera_upload_mode_selector.dart';
import 'package:mobileapp/pages/upload/usb_camera_reader_selector.dart';
import 'package:mobileapp/pages/upload/usb_camera_setup_help.dart';
import 'package:mobileapp/utilities/app_toast.dart';
import 'package:mobileapp/widgets/app_ui.dart';
import 'package:mobileapp/widgets/intrinsic_qr_image.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobileapp/pages/upload/canon_wireless_setup_dialog.dart';

// Keep simulator UI out of production unless an explicit test build enables it.
const bool _pcSimulatorEnabled =
    kDebugMode || bool.fromEnvironment('AIRPIX_ENABLE_PC_CAMERA_SIMULATOR');

class _SelectedUploadFile {
  const _SelectedUploadFile({required this.path, required this.name});

  final String path;
  final String name;
}

/// Outcome of trying to read photos straight off a USB-connected camera.
sealed class _CameraRead {
  const _CameraRead();
}

final class _CameraPhotos extends _CameraRead {
  const _CameraPhotos(this.images);

  final List<ConnectedCameraImage> images;
}

/// Camera scan failed or returned no readable files; offer explicit alternatives.
final class _NoCameraPhotos extends _CameraRead {
  const _NoCameraPhotos(this.guidance);

  final UsbCameraGuidance guidance;
}

final class _CameraCatalogLoading extends _CameraRead {
  const _CameraCatalogLoading();
}

final class _CameraAccessDenied extends _CameraRead {
  const _CameraAccessDenied({required this.fixInSettings});

  /// iOS keeps the choice in Settings; Android asks again on the next attempt.
  final bool fixInSettings;
}

const _cameraDeniedCodes = {
  'CAMERA_ACCESS_DENIED',
  'USB_PERMISSION_DENIED',
  'USB_PERMISSION_REQUIRED',
};

enum _WirelessImportMode { ftp, sharedNetwork, cameraHotspot }

class _WirelessCaptureTarget {
  const _WirelessCaptureTarget({
    required this.event,
    required this.mode,
    required this.isEnhanced,
    this.albumId,
  });
  final EventSummary event;
  final _WirelessImportMode mode;
  final bool isEnhanced;
  final String? albumId;
}

class _UsbCaptureTarget {
  const _UsbCaptureTarget({
    required this.event,
    required this.uploadMode,
    required this.isEnhanced,
    this.albumId,
    this.photoCatalog = false,
  });

  final EventSummary event;
  final LiveCameraUploadMode uploadMode;
  final bool isEnhanced;
  final String? albumId;
  final bool photoCatalog;
}

@RoutePage()
class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> with WidgetsBindingObserver {
  final _picker = ImagePicker();
  final List<_SelectedUploadFile> _selectedFiles = [];
  Timer? _wirelessTimer;
  Timer? _galleryTimer;
  LiveCameraCapture? _liveCamera;
  String? _liveCameraEventId;
  Future<void>? _usbShutdown;
  String? _usbReleaseIssue;
  bool _otgStarting = false;
  bool _usbStartRequested = false;
  bool _guestQrPreparing = false;
  Future<void> _usbModeSaveQueue = Future<void>.value();
  // iPhone defaults to ImageCaptureCore's catalog reader, which does not
  // require a raw PTP GetDeviceInfo command before connecting. This is the
  // known camera-discovery route from the earlier implementation. The
  // advanced vendor tether path remains selectable for cameras whose remote
  // shooting queue does not expose a normal photo catalog.
  bool _usbPhotoCatalogReader = Platform.isIOS;
  bool _usbSessionPhotoCatalogReader = false;
  LiveCameraUploadMode _usbUploadMode = LiveCameraUploadMode.newShotsOnly;
  LiveCameraUploadMode _usbSessionUploadMode =
      LiveCameraUploadMode.newShotsOnly;
  bool _isEnhanced = false;
  bool _uploading = false;
  bool _galleryImporting = false;
  bool _galleryBusy = false;
  bool _otgImporting = false;
  bool _otgBusy = false;
  bool _usbPickInProgress = false;
  bool _freeingSpace = false;
  bool _autoImporting = false;
  bool _wirelessScanning = false;
  bool _wirelessBusy = false;
  bool _disposed = false;
  final _receiverOwnerId =
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 31)}';
  bool _resolvingSoloEvent = false;
  bool _soloEventResolved = false;
  bool _connectionPageOpen = false;
  CameraFtpReceiver? _ftpReceiver;
  CameraFtpConnection? _ftpConnection;
  bool _ftpStarting = false;
  bool _ftpHasReceived = false;
  Future<void>? _wirelessShutdown;
  String? _wirelessAwakeOwner;
  String? _receivingEventId;
  String? _sessionKind;
  DateTime? _sessionStartedAt;
  bool _wiredPhotoReceived = false;
  final _sessionStatus = ValueNotifier<CameraTransferSessionStatus>(
    const CameraTransferSessionStatus(
      connectionLabel: 'No camera connected',
      message: 'Connect your camera to receive new photos.',
      isActive: false,
    ),
  );
  int _wirelessGeneration = 0;
  int _otgGeneration = 0;
  int _galleryGeneration = 0;
  int _wirelessFailureCount = 0;
  int? _gallerySinceMs;
  final Set<String> _processedGalleryIds = {};
  String? _galleryStatus;
  String? _otgStatus;
  String? _uploadStatus;
  String? _wirelessStatus;
  String? _otgSourceName;
  CanonCcapiCamera? _canonCcapiCamera;
  CancelToken? _wirelessConnectCancellation;
  DateTime? _wirelessRetryAfter;
  String? _loadedAlbumEventId;
  String? _selectedAlbumId;
  List<AlbumModel> _albums = [];

  bool get _wirelessImporting =>
      _wirelessScanning ||
      _autoImporting ||
      _ftpStarting ||
      _ftpReceiver != null;

  bool get _usbSessionLocked =>
      _usbStartRequested || _otgStarting || _otgImporting || _otgBusy;

  bool _isUsbReleaseError(String? code) => const {
    'PTP_CLOSE_FAILED',
    'PTP_CLOSE_TIMEOUT',
    'PTP_CLOSE_PENDING',
  }.contains(code);

  void _safeSetState(VoidCallback update) {
    if (!mounted || _disposed) return;
    setState(update);
    _refreshSessionStatus();
  }

  void _refreshSessionStatus() {
    if (_disposed) return;
    String label = 'No camera connected';
    String message = 'Connect your camera to receive new photos.';
    bool connecting = false;
    switch (_sessionKind) {
      case 'usb':
        label = _otgSourceName ?? 'Camera cable';
        message =
            '${UsbCameraUploadModeSelector.labelFor(_usbSessionUploadMode)}. '
            '${_otgStatus ?? 'Waiting for the camera.'}';
        connecting = _otgStarting || _usbStartRequested;
        break;
      case 'ftp':
        label = _ftpReceiver?.authenticatedClientCount == 0
            ? 'Wi-Fi receiver ready'
            : 'Camera FTP';
        message = _wirelessStatus ?? 'Start a wireless camera session.';
        connecting = _ftpStarting;
        break;
      case 'wireless':
        label = 'Camera Wi-Fi';
        message = _wirelessStatus ?? 'Waiting for the camera.';
        connecting = _wirelessScanning;
        break;
      case 'gallery':
        label = 'Phone gallery';
        message = _galleryStatus ?? 'Waiting for a photo.';
        break;
    }
    _sessionStatus.value = CameraTransferSessionStatus(
      connectionLabel: label,
      message: message,
      isActive: _liveConnectionActive,
      isConnecting: connecting,
    );
  }

  void _beginReceivingSession(EventSummary event, String kind) {
    _sessionKind = kind;
    _sessionStartedAt = DateTime.now();
    _receivingEventId = event.id;
  }

  Future<void> _stopReceivingSession() async {
    if (_liveCamera != null || _usbStartRequested) await _stopOtgAutoImport();
    if (_wirelessImporting) await _stopWirelessImport();
    if (_galleryImporting) _stopGalleryAutoImport();
  }

  bool _wirelessActive(int generation) =>
      mounted &&
      !_disposed &&
      generation == _wirelessGeneration &&
      ActiveEventStorage.activeEvent.value?.id == _receivingEventId;

  bool _otgActive(int generation) =>
      mounted && !_disposed && generation == _otgGeneration;

  bool _usbStartActive(int generation, _UsbCaptureTarget target) =>
      _otgActive(generation) &&
      _usbStartRequested &&
      _liveCameraEventId == target.event.id &&
      ActiveEventStorage.activeEvent.value?.id == target.event.id;

  bool _galleryActive(int generation) =>
      mounted && !_disposed && generation == _galleryGeneration;

  @override
  void initState() {
    super.initState();
    _usbUploadMode = UsbCameraUploadModeStorage.read();
    WidgetsBinding.instance.addObserver(this);
    ActiveEventStorage.activeEvent.addListener(_handleLiveEventChange);
  }

  void _handleLiveEventChange() {
    if (_receivingEventId != null &&
        ActiveEventStorage.activeEvent.value?.id != _receivingEventId &&
        (_wirelessImporting || _galleryImporting)) {
      unawaited(_stopReceivingSession());
    }
    if (_liveCameraEventId != null &&
        ActiveEventStorage.activeEvent.value?.id != _liveCameraEventId) {
      unawaited(
        _stopOtgAutoImport().then((_) {
          if (_usbReleaseIssue != null) return;
          _safeSetState(
            () => _otgStatus =
                'Event changed. Start live shooting again for the selected event.',
          );
        }),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permission sheets can make the app inactive; only a real background
    // transition ends foreground-only USB shooting.
    if (state == AppLifecycleState.paused && _wirelessImporting) {
      unawaited(
        _stopWirelessImport().then((_) {
          _safeSetState(
            () => _wirelessStatus =
                'Receiving paused in the background. Open AirPix and start again; '
                'the camera can retry pending FTP photos.',
          );
        }),
      );
    }
    if (state == AppLifecycleState.paused &&
        (_liveCamera != null || _usbStartRequested)) {
      unawaited(
        _stopOtgAutoImport().then((_) {
          if (_usbReleaseIssue != null) return;
          _safeSetState(
            () => _otgStatus =
                'Live shooting paused while the app was in the background. '
                'Keep AirPix open and start again before taking photos.',
          );
        }),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _wirelessGeneration += 1;
    _otgGeneration += 1;
    _galleryGeneration += 1;
    _wirelessTimer?.cancel();
    _galleryTimer?.cancel();
    _wirelessTimer = null;
    _galleryTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    ActiveEventStorage.activeEvent.removeListener(_handleLiveEventChange);
    final liveCamera = _liveCamera;
    _liveCamera = null;
    if (liveCamera != null) {
      unawaited(
        liveCamera.stop(notify: false).catchError((Object error) {
          debugPrint('USB session cleanup: $error');
        }),
      );
    }
    final ftp = _ftpReceiver;
    _ftpReceiver = null;
    if (ftp != null) unawaited(ftp.stop());
    final awakeOwner = _wirelessAwakeOwner;
    _wirelessAwakeOwner = null;
    if (awakeOwner != null) {
      unawaited(TransferScreenAwake.setEnabled(awakeOwner, false));
    }
    _sessionStatus.dispose();
    final canonCamera = _canonCcapiCamera;
    _canonCcapiCamera = null;
    if (canonCamera != null) unawaited(canonCamera.close());
    _wirelessConnectCancellation?.cancel('Page closed');
    super.dispose();
  }

  void _addSelectedFiles(List<_SelectedUploadFile> files) {
    if (files.isEmpty) return;

    final existingPaths = _selectedFiles.map((file) => file.path).toSet();
    final freshFiles = files
        .where((file) => !existingPaths.contains(file.path))
        .toList();
    if (freshFiles.isEmpty) return;

    _safeSetState(() {
      _selectedFiles.addAll(freshFiles);
    });
  }

  Future<void> _pickPhoneImages() async {
    final images = await _picker.pickMultiImage(imageQuality: 92);
    if (images.isEmpty) return;

    _addSelectedFiles(
      images
          .map(
            (image) => _SelectedUploadFile(path: image.path, name: image.name),
          )
          .toList(),
    );
  }

  Future<void> _pickCameraImage() async {
    final camera = await Permission.camera.request();
    if (!camera.isGranted) {
      if (camera.isPermanentlyDenied) {
        AppToast.error('Camera access is disabled. Enable it in app settings.');
        await openAppSettings();
      } else {
        AppToast.error('Camera permission is required to take a phone photo.');
      }
      return;
    }

    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 92,
    );
    if (image == null) return;

    _addSelectedFiles([
      _SelectedUploadFile(path: image.path, name: image.name),
    ]);
  }

  Future<void> _pickOtgFiles() async {
    if (_usbPickInProgress) return; // Ignore double taps.
    if (_otgImporting || _otgStarting || _usbStartRequested) {
      AppToast.error(
        'Stop live shooting before manually selecting camera photos.',
      );
      return;
    }
    _usbPickInProgress = true;
    try {
      final read = await _withCameraProgress(
        'Connecting to camera…\nKeep it switched on and connected.',
        _readConnectedCameraImages(),
      );
      if (read == null || !mounted) return; // Cancelled, or page closed.

      switch (read) {
        case _CameraAccessDenied(:final fixInSettings):
          await _showCameraAccessHelp(fixInSettings: fixInSettings);
        case _NoCameraPhotos(:final guidance):
          await _showExternalCameraChoices(guidance: guidance);
        case _CameraCatalogLoading():
          await _showExternalCameraChoices(catalogLoading: true);
        case _CameraPhotos(:final images):
          await _importFromCamera(images);
      }
    } catch (error, stackTrace) {
      debugPrint('USB camera flow failed: $error\n$stackTrace');
      if (mounted) {
        await _showExternalCameraChoices(
          guidance: UsbCameraGuidance.forStatus('unknown', message: '$error'),
        );
      }
    } finally {
      if (Platform.isIOS) {
        try {
          await OtgFilePicker.releaseCameraImportSession();
        } catch (error) {
          debugPrint('Camera import session cleanup: $error');
        }
      }
      _usbPickInProgress = false;
    }
  }

  Future<_CameraRead> _readConnectedCameraImages() async {
    try {
      final images = await OtgFilePicker.connectedCameraImages();
      if (images.isNotEmpty) return _CameraPhotos(images);
      // An empty photo list is not proof of a disconnected camera. Inspect
      // the actual transport state before choosing an error message.
      final diagnostic = await OtgFilePicker.cameraConnectionDiagnostics();
      if (diagnostic.status == 'permission-denied') {
        return const _CameraAccessDenied(fixInSettings: true);
      }
      if (diagnostic.status == 'catalog-loading') {
        return const _CameraCatalogLoading();
      }
      // This follows an explicit manual scan. Android closes that scan's MTP
      // session before returning; passive diagnostics must not reopen it just
      // to rediscover that the completed scan returned no photos.
      final completedEmptyScan =
          diagnostic.status == 'ready' ||
          (diagnostic.status == 'camera-detected' &&
              diagnostic.cameras.isNotEmpty);
      return _NoCameraPhotos(
        UsbCameraGuidance.forStatus(
          completedEmptyScan ? 'empty-media' : diagnostic.status,
          message: completedEmptyScan ? null : diagnostic.message,
        ),
      );
    } on PlatformException catch (error) {
      if (_cameraDeniedCodes.contains(error.code)) {
        return _CameraAccessDenied(fixInSettings: Platform.isIOS);
      }
      if (error.code == 'CAMERA_CATALOG_LOADING') {
        return const _CameraCatalogLoading();
      }
      debugPrint('USB camera read failed (${error.code}): ${error.message}');
      return _NoCameraPhotos(
        UsbCameraGuidance.forStatus(error.code, message: error.message),
      );
    } on MissingPluginException catch (error) {
      debugPrint('USB camera channel unavailable: $error');
      return _NoCameraPhotos(UsbCameraGuidance.forStatus('missing_plugin'));
    }
  }

  Future<void> _importFromCamera(List<ConnectedCameraImage> images) async {
    final selectedIds = await _selectConnectedCameraImages(images);
    if (selectedIds == null || selectedIds.isEmpty || !mounted) return;

    final count = selectedIds.length;
    List<OtgPickedFile>? imported;
    try {
      imported = await _withCameraProgress(
        'Copying $count ${count == 1 ? 'photo' : 'photos'} from camera…',
        _importCameraImagesWithRetry(selectedIds),
      );
    } on PlatformException catch (error) {
      if (_cameraDeniedCodes.contains(error.code)) {
        if (mounted) await _showCameraAccessHelp(fixInSettings: Platform.isIOS);
        return;
      }
      debugPrint('USB camera import failed (${error.code}): ${error.message}');
      if (mounted) {
        await _showExternalCameraChoices(
          guidance: UsbCameraGuidance.forStatus(
            error.code,
            message: error.message,
          ),
        );
      }
      return;
    }
    if (imported == null) return; // Cancelled.

    if (imported.isEmpty) {
      AppToast.error(
        'Could not copy photos from the camera. Keep it connected and try again.',
      );
      return;
    }

    _addSelectedFiles(
      imported
          .map((file) => _SelectedUploadFile(path: file.path, name: file.name))
          .toList(),
    );
    final missed = count - imported.length;
    if (missed > 0) {
      AppToast.error(
        '$missed ${missed == 1 ? 'photo' : 'photos'} could not be copied. Select them again to retry.',
      );
    }
  }

  /// Copies the selected photos, retrying once for any the camera failed to send.
  Future<List<OtgPickedFile>> _importCameraImagesWithRetry(
    List<String> ids,
  ) async {
    final imported = await OtgFilePicker.importConnectedCameraImages(ids);
    final importedIds = imported.map((file) => file.id).nonNulls.toSet();
    final missing = ids.where((id) => !importedIds.contains(id)).toList();
    final platformReportsIds = imported.isEmpty || importedIds.isNotEmpty;
    if (missing.isEmpty || !platformReportsIds) return imported;

    final retried = await OtgFilePicker.importConnectedCameraImages(missing);
    return [...imported, ...retried];
  }

  /// Reports the actual native USB transport, not phone Photos/MediaStore.
  Future<void> _diagnoseUsbCamera() async {
    try {
      final diagnostic = await _withCameraProgress(
        'Checking USB camera…',
        OtgFilePicker.cameraConnectionDiagnostics(),
      );
      if (!mounted || diagnostic == null) return;
      final guidance = UsbCameraGuidance.forStatus(diagnostic.status);
      final modeAdvice = UsbShootingModeAdvice.fromDiagnostics(diagnostic);
      final cameraFound = diagnostic.cameras.isNotEmpty;
      final cableFound = diagnostic.usbEnumerationAvailable
          ? diagnostic.usbHostSupported != false &&
                diagnostic.usbDevices.isNotEmpty
          : cameraFound;
      final shutterSupported = diagnostic.cameras.any(
        (camera) => camera.physicalShutter == 'supported',
      );
      final sessionReady =
          diagnostic.status == 'live-ready' ||
          diagnostic.cameras.any((camera) => camera.liveSessionActive);

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.usb_rounded),
              SizedBox(width: 10),
              Expanded(child: Text('USB camera check')),
            ],
          ),
          scrollable: true,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: sessionReady
                      ? Theme.of(context).colorScheme.primaryContainer
                      : AppColors.muted,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      modeAdvice.wrongMode ? modeAdvice.title : guidance.title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      diagnostic.message,
                      style: const TextStyle(fontSize: 12, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _usbCheckRow(
                icon: Icons.cable_rounded,
                label: 'Cable / adapter',
                value: cableFound ? 'Detected' : 'Not detected',
                ok: cableFound,
              ),
              _usbCheckRow(
                icon: Icons.photo_camera_outlined,
                label: 'Camera',
                value: cameraFound
                    ? diagnostic.cameras.first.name
                    : 'No compatible camera found',
                ok: cameraFound,
              ),
              _usbCheckRow(
                icon: Icons.settings_input_component_outlined,
                label: 'USB shooting mode',
                value: modeAdvice.status,
                ok: sessionReady && !modeAdvice.wrongMode,
              ),
              _usbCheckRow(
                icon: Icons.camera_alt_outlined,
                label: 'Physical shutter',
                value: shutterSupported
                    ? 'Supported by this connection'
                    : 'Not confirmed yet',
                ok: shutterSupported,
              ),
              _usbCheckRow(
                icon: Icons.cloud_upload_outlined,
                label: 'Live transfer',
                value: sessionReady
                    ? 'Ready for new photos'
                    : 'Start a USB session after fixing the item above',
                ok: sessionReady,
              ),
              const SizedBox(height: 12),
              Text(
                'Next step',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                cameraFound || diagnostic.usbDevices.isNotEmpty
                    ? modeAdvice.nextSteps
                    : guidance.nextSteps,
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 10),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: const Text(
                  'Technical details',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'Only needed for troubleshooting or support',
                  style: TextStyle(fontSize: 11),
                ),
                children: [
                  if (diagnostic.connectionNote.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        diagnostic.connectionNote,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  if (Platform.isIOS) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Photo access: ${diagnostic.contentsAuthorization}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Camera control: ${diagnostic.controlAuthorization}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                  for (final camera in diagnostic.cameras) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${camera.name} · ${camera.transportType.isEmpty ? "camera transport" : camera.transportType}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Session ${camera.sessionOpen ? "open" : "closed"} · '
                        'Live ${camera.liveSessionActive ? "active" : "stopped"} · '
                        '${camera.imageCount} images listed',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    if (camera.sessionError.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          camera.sessionError,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.redAccent,
                          ),
                        ),
                      ),
                  ],
                  if (diagnostic.usbDevices.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final device in diagnostic.usbDevices)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${device.name} · ${device.usbIdentifier}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                ],
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(
                    text: [
                      diagnostic.toSupportReport(),
                      'USB mode advice: ${modeAdvice.status}',
                      'Next steps: ${modeAdvice.nextSteps}',
                    ].join(String.fromCharCode(10)),
                  ),
                );
                AppToast.success('USB report copied');
              },
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: const Text('Copy report'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } on MissingPluginException {
      AppToast.error('USB camera check needs a freshly rebuilt app.');
    } on PlatformException catch (error) {
      AppToast.error(error.message ?? 'Could not check the USB camera.');
    } catch (error) {
      debugPrint('USB diagnostic failed: $error');
      AppToast.error('Could not check the USB camera.');
    }
  }

  Widget _usbCheckRow({
    required IconData icon,
    required String label,
    required String value,
    required bool ok,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            size: 18,
            color: ok ? colorScheme.primary : AppColors.mutedForeground,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showUsbLiveFailure(
    UsbCameraGuidance advice,
    String code, {
    UsbShootingModeAdvice? modeAdvice,
    Object? diagnosticDetails,
    VoidCallback? onTryPhotoCatalog,
  }) async {
    if (!mounted) return;
    final diagnostics = <String>[];
    if (diagnosticDetails is Map) {
      if (diagnosticDetails['ptpFailure'] != null) {
        diagnostics.add('Initial PTP: ${diagnosticDetails['ptpFailure']}');
      }
      final ptp = diagnosticDetails['ptpDiagnostics'] is Map
          ? diagnosticDetails['ptpDiagnostics'] as Map
          : diagnosticDetails;
      for (final key in const [
        'operation',
        'decoderReason',
        'responseBytes',
        'declaredLength',
        'containerType',
        'responseCode',
        'dataBytes',
        'responsePrefixHex',
        'errorDomain',
        'errorCode',
      ]) {
        final value = ptp[key];
        if (value is String || value is num) diagnostics.add('$key: $value');
      }
    }
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(advice.title),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(advice.details),
            const SizedBox(height: 16),
            const Text(
              'How to fix the connection',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(advice.nextSteps),
            if (modeAdvice != null) ...[
              const SizedBox(height: 14),
              Text(
                modeAdvice.wrongMode
                    ? 'Wrong camera USB setting detected'
                    : 'Connection-mode guidance for this camera',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(modeAdvice.nextSteps),
            ],
            const SizedBox(height: 12),
            SelectableText(
              'Connection code: $code',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
            if (diagnostics.isNotEmpty)
              SelectableText(
                diagnostics.join('\n'),
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            if (onTryPhotoCatalog != null) ...[
              const SizedBox(height: 12),
              const Text(UsbCameraReaderSelector.explanation),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(dialogContext, 'setup'),
            icon: const Icon(Icons.help_outline),
            label: const Text('Camera setup help'),
          ),
          if (onTryPhotoCatalog != null)
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'catalog'),
              child: const Text('Try compatibility photo reader'),
            ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'setup') await _showLiveCameraSetup();
    if (action == 'catalog') onTryPhotoCatalog?.call();
  }

  Future<void> _showLiveCameraSetup() => showDialog<void>(
    context: context,
    builder: (_) => const UsbCameraSetupHelpDialog(),
  );

  Future<void> _pickOtgFilesFromFiles() async {
    try {
      final files = await OtgFilePicker.pickImages();
      _addSelectedFiles(
        files
            .map(
              (file) => _SelectedUploadFile(path: file.path, name: file.name),
            )
            .toList(),
      );
    } on MissingPluginException catch (error) {
      debugPrint('File picker channel unavailable: $error');
      AppToast.error(
        'USB camera is not supported in this version of AirPix. Please update the app.',
      );
    } on PlatformException catch (error) {
      debugPrint('File picker failed (${error.code}): ${error.message}');
      AppToast.error('Could not open your files. Please try again.');
    }
  }

  /// Keep external-camera detection separate from iPhone Photos and Files.
  Future<void> _showExternalCameraChoices({
    bool catalogLoading = false,
    UsbCameraGuidance? guidance,
  }) async {
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                guidance?.title ??
                    (catalogLoading
                        ? 'Camera detected — still reading photos'
                        : 'No readable USB camera photos detected'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                guidance == null
                    ? (catalogLoading
                          ? 'The camera is connected, but the phone has not finished loading its photo catalog. Keep it awake and retry.'
                          : 'No photos were listed from a wired USB camera. Check the data cable, adapter, camera power and PTP / Photo Transfer mode.')
                    : '${guidance.details}\n\nTry this: ${guidance.nextSteps}',
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Retry camera connection'),
                subtitle: const Text(
                  'Search for the wired USB/PTP camera again',
                ),
                onTap: () => Navigator.pop(sheetContext, 'retry'),
              ),
              ListTile(
                leading: const Icon(Icons.sd_storage_outlined),
                title: const Text('Browse SD card / USB drive'),
                subtitle: const Text(
                  'Select the external drive in Files > Locations',
                ),
                onTap: () => Navigator.pop(sheetContext, 'files'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Use photos saved on this iPhone'),
                subtitle: const Text('Open the iPhone photo library instead'),
                onTap: () => Navigator.pop(sheetContext, 'phone'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'retry':
        // Release the in-progress picker lock before retrying.
        Future<void>.delayed(const Duration(milliseconds: 250), () {
          if (mounted) _pickOtgFiles();
        });
      case 'files':
        await _pickOtgFilesFromFiles();
      case 'phone':
        await _pickPhoneImages();
    }
  }

  Future<void> _showCameraAccessHelp({required bool fixInSettings}) async {
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Allow camera access'),
        content: Text(
          fixInSettings
              ? 'AirPix needs permission to read photos from your connected camera. Allow it in Settings, then try again.'
              : 'Tap USB / OTG camera again and choose Allow when your phone asks to access the camera.',
        ),
        actions: [
          if (fixInSettings)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Not now'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, fixInSettings),
            child: Text(fixInSettings ? 'Open Settings' : 'OK'),
          ),
        ],
      ),
    );
    // null means dismissed by tapping outside; only an explicit tap opens Settings.
    if (openSettings == true) await openAppSettings();
  }

  /// Runs [task] behind a cancellable progress dialog, shown only if it takes
  /// longer than a moment. Returns null if the user taps Cancel.
  Future<T?> _withCameraProgress<T>(String message, Future<T> task) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final cancelled = Completer<T?>();
    final route = DialogRoute<void>(
      context: context,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(width: 20),
              Expanded(child: Text(message)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (!cancelled.isCompleted) cancelled.complete(null);
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
    // Short delay so an instant result does not flash a dialog.
    final showTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && !cancelled.isCompleted) unawaited(navigator.push(route));
    });
    try {
      return await Future.any<T?>([task, cancelled.future]);
    } finally {
      showTimer.cancel();
      if (route.isActive) navigator.removeRoute(route);
    }
  }

  Future<List<String>?> _selectConnectedCameraImages(
    List<ConnectedCameraImage> images,
  ) async {
    final selected = <String>{};
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.72,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Connected camera photos'),
                  subtitle: Text('${images.length} photos found on camera'),
                  trailing: TextButton(
                    onPressed: () => setModalState(() {
                      if (selected.length == images.length) {
                        selected.clear();
                      } else {
                        selected
                          ..clear()
                          ..addAll(images.map((image) => image.id));
                      }
                    }),
                    child: Text(
                      selected.length == images.length ? 'Clear' : 'Select all',
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: images.length,
                    itemBuilder: (context, index) {
                      final image = images[index];
                      final checked = selected.contains(image.id);
                      return CheckboxListTile(
                        value: checked,
                        title: Text(image.name),
                        subtitle: image.size > 0
                            ? Text(
                                '${(image.size / 1024 / 1024).toStringAsFixed(1)} MB',
                              )
                            : null,
                        onChanged: (value) => setModalState(() {
                          value == true
                              ? selected.add(image.id)
                              : selected.remove(image.id);
                        }),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () => Navigator.pop(context, selected.toList()),
                      child: Text('Import ${selected.length} selected'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openWifiSettings() async {
    try {
      await DeviceSettings.openWifiSettings();
    } on MissingPluginException {
      AppToast.error('Restart app once to enable Wi-Fi settings');
    } catch (_) {
      AppToast.error('Open phone Wi-Fi settings and join camera Wi-Fi');
    }
  }

  Future<bool> _requestGalleryPermission() async {
    final photos = await Permission.photos.request();
    if (photos.isGranted) return true;
    if (photos.isLimited) {
      AppToast.error(
        'Watch phone gallery needs full photo access so new photos can be detected automatically. Manual photo picking still works with limited access.',
      );
      return false;
    }

    final storage = await Permission.storage.request();
    if (storage.isGranted) return true;
    if (photos.isPermanentlyDenied || storage.isPermanentlyDenied) {
      AppToast.error('Photo access is disabled. Enable it in app settings.');
      await openAppSettings();
    }
    return false;
  }

  Future<List<String>> _uploadFilesBatch(
    List<_SelectedUploadFile> files,
  ) async {
    final formData = FormData.fromMap({
      'files': [
        for (final file in files)
          await MultipartFile.fromFile(file.path, filename: file.name),
      ],
    });
    final response = await DioHelper.post(
      '/image/upload/batch',
      data: formData,
    );
    final urls = response.data['urls'] as List? ?? [];
    return urls
        .map((url) => url.toString())
        .where((url) => url.isNotEmpty)
        .toList();
  }

  Future<bool> _uploadOrQueueFile({
    required EventSummary event,
    required String path,
    required String filename,
    required String source,
    String? cameraId,
  }) async {
    return UploadQueueService.uploadNowOrQueueFile(
      event: event,
      path: path,
      filename: filename,
      isEnhanced: _isEnhanced,
      albumId: _selectedAlbumId,
      source: source,
      cameraId: cameraId,
    );
  }

  String _wirelessFingerprint({
    required EventSummary event,
    required String imageUrl,
    required String signature,
  }) {
    return '${event.id}|wireless|$imageUrl|$signature';
  }

  Future<void> _createEventImages(
    EventSummary event,
    List<String> imageUrls,
  ) async {
    await DioHelper.post(
      '/eventImage/batch',
      data: {
        'eventId': event.id,
        'imageUrls': imageUrls,
        'isEnhanced': _isEnhanced,
        if (_selectedAlbumId != null) 'albumId': _selectedAlbumId,
      },
    );
  }

  Future<void> _loadAlbumsForEvent(EventSummary event) async {
    if (_loadedAlbumEventId == event.id) return;
    _loadedAlbumEventId = event.id;
    _selectedAlbumId = null;

    try {
      final response = await DioHelper.get(
        '/album/get-all',
        queryParameters: {'eventId': event.id},
      );
      final data = response.data['data'] as List? ?? [];
      if (!mounted) return;
      _safeSetState(() {
        _albums = data
            .map((item) => AlbumModel.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      });
    } catch (_) {
      if (!mounted) return;
      _safeSetState(() => _albums = []);
    }
  }

  Future<void> _findAndStartWirelessImport(
    EventSummary event,
    _WirelessImportMode mode,
  ) async {
    if (_wirelessShutdown != null) await _wirelessShutdown;
    if (!mounted ||
        _disposed ||
        _wirelessImporting ||
        ActiveEventStorage.activeEvent.value?.id != event.id) {
      return;
    }
    _beginReceivingSession(event, 'wireless');
    final target = _WirelessCaptureTarget(
      event: event,
      mode: mode,
      isEnhanced: _isEnhanced,
      albumId: _selectedAlbumId,
    );
    final generation = ++_wirelessGeneration;
    final cancellation = CancelToken();
    _wirelessConnectCancellation = cancellation;
    _safeSetState(() {
      _wirelessScanning = true;
      _wirelessStatus = 'Set up the camera CCAPI connection.';
    });
    CanonCcapiCamera? camera;
    try {
      SharedPreferences? preferences;
      try {
        preferences = await SharedPreferences.getInstance();
      } catch (_) {}
      if (!mounted || !_wirelessActive(generation)) return;
      final settings = await showDialog<CanonWirelessSettings>(
        context: context,
        builder: (_) => CanonWirelessSetupDialog(
          initialAddress:
              preferences?.getString('canon_ccapi_address_v1') ?? '',
          cameraHotspot: mode == _WirelessImportMode.cameraHotspot,
        ),
      );
      if (!_wirelessActive(generation)) return;
      if (settings == null) {
        _safeSetState(() => _wirelessStatus = 'Wireless setup cancelled.');
        return;
      }
      _safeSetState(
        () => _wirelessStatus =
            'Connecting to Canon CCAPI. Allow Local Network access if asked...',
      );
      camera = await CanonCcapiCamera.discover(
        [settings.origin],
        exactEndpoint: true,
        cancellation: cancellation,
        timeout: const Duration(seconds: 3),
        username: settings.username,
        password: settings.password,
      );
      if (!_wirelessActive(generation)) {
        await camera?.close();
        return;
      }
      if (camera == null) {
        _safeSetState(
          () => _wirelessStatus =
              'CCAPI did not connect. Check the camera address, port, login and Wi-Fi. '
              'On iPhone, enable AirPix in Settings > Privacy & Security > Local Network. '
              'No other camera mode was attempted.',
        );
        AppToast.error(
          'Canon CCAPI connection failed. Check setup and Local Network access.',
        );
        return;
      }
      _canonCcapiCamera = camera;
      _safeSetState(() {
        _wirelessScanning = false;
        _wirelessFailureCount = 0;
        _wirelessRetryAfter = null;
        _autoImporting = true;
        _wirelessStatus =
            'Canon CCAPI connected. Take a photo with the camera shutter.';
      });
      _wirelessAwakeOwner = 'wireless-$_receiverOwnerId-$generation';
      await TransferScreenAwake.setEnabled(_wirelessAwakeOwner!, true);
      if (!_wirelessActive(generation)) return;
      _wirelessTimer = Timer.periodic(const Duration(milliseconds: 500), (
        timer,
      ) {
        if (!_wirelessActive(generation)) {
          timer.cancel();
          return;
        }
        unawaited(_pollWirelessCamera(target, generation));
      });
      // Discovery can consume an added-photo event; process it immediately.
      unawaited(_pollWirelessCamera(target, generation));
      unawaited(_showTransferSessionPage(event));
      try {
        await preferences?.setString(
          'canon_ccapi_address_v1',
          settings.origin.toString(),
        );
      } catch (_) {
        /* Remembering an address must not interrupt receiving. */
      }
    } catch (_) {
      await camera?.close();
      if (_wirelessActive(generation)) {
        await _stopWirelessImport();
        _safeSetState(
          () => _wirelessStatus =
              'Wireless connection stopped. Check camera setup and try again.',
        );
      }
    } finally {
      if (identical(_wirelessConnectCancellation, cancellation)) {
        _wirelessConnectCancellation = null;
      }
      if (_wirelessActive(generation)) {
        _safeSetState(() => _wirelessScanning = false);
      }
    }
  }

  Future<void> _saveWirelessBytes({
    required _WirelessCaptureTarget target,
    required int generation,
    required Uint8List bytes,
    required String filename,
    required String imageKey,
    required String signature,
    required String source,
    required String? cameraId,
  }) async {
    // A complete in-flight photo belongs to the event/album captured when the
    // session started, even when Stop or an event change happens during its read.
    await UploadQueueService.receiveCameraBytes(
      event: target.event,
      bytes: bytes,
      filename: filename,
      isEnhanced: target.isEnhanced,
      albumId: target.albumId,
      source: '$source-${target.mode.name}',
      cameraId: cameraId,
      fingerprint: _wirelessFingerprint(
        event: target.event,
        imageUrl: imageKey,
        signature: '$signature|${sha256.convert(bytes)}',
      ),
    );
    if (_wirelessActive(generation)) {
      _safeSetState(
        () => _wirelessStatus =
            'Photo received. Cloud upload starts automatically. Keep shooting.',
      );
    }
  }

  Future<bool> _pollCanonCcapiCamera(
    _WirelessCaptureTarget target,
    int generation,
  ) async {
    if (!_wirelessActive(generation)) return true;
    final camera = _canonCcapiCamera;
    if (camera == null) return false;

    final contents = await camera.pollAddedContents();
    if (!_wirelessActive(generation)) return true;
    final fresh = contents;
    if (fresh.isEmpty) {
      _safeSetState(() {
        _wirelessStatus = 'Canon CCAPI connected. Waiting for new photos...';
      });
      return true;
    }

    var downloadFailed = false;
    for (final content in fresh) {
      if (!_wirelessActive(generation)) return true;
      _safeSetState(
        () => _wirelessStatus = 'New Canon photo found. Importing...',
      );
      Uint8List? bytes;
      try {
        bytes = await camera.download(content);
      } catch (_) {
        if (camera.isClosed) rethrow;
        downloadFailed = true;
        continue; // Keep this photo pending and allow later burst photos through.
      }
      if (bytes == null || bytes.isEmpty) {
        downloadFailed = true;
        // The announcement remains pending until a complete file can be read.
        continue;
      }

      await _saveWirelessBytes(
        target: target,
        generation: generation,
        bytes: bytes,
        filename: content.name,
        imageKey: content.url,
        signature: content.url,
        source: 'wireless-canon-ccapi',
        cameraId: camera.sourceUrl,
      );
      camera.acknowledgeContents([content.url]);
      if (!_wirelessActive(generation)) return true;
    }
    if (downloadFailed) {
      throw const SocketException(
        'Camera photo is not ready; retry pending contents',
      );
    }
    return true;
  }

  Future<void> _pollWirelessCamera(
    _WirelessCaptureTarget target,
    int generation,
  ) async {
    if (!_wirelessActive(generation) ||
        _wirelessBusy ||
        _canonCcapiCamera == null) {
      return;
    }
    if (_wirelessRetryAfter?.isAfter(DateTime.now()) == true) return;
    _wirelessBusy = true;
    try {
      await _pollCanonCcapiCamera(target, generation);
      if (_wirelessActive(generation)) {
        _wirelessFailureCount = 0;
        _wirelessRetryAfter = null;
      }
    } catch (_) {
      if (!_wirelessActive(generation)) return;
      if (_canonCcapiCamera?.isClosed != false) {
        await _stopWirelessImport();
        _safeSetState(
          () => _wirelessStatus =
              'Camera connection ended. Check shooting mode and reconnect.',
        );
        return;
      }
      _wirelessFailureCount++;
      final delay = min(5000, 500 * (1 << min(_wirelessFailureCount - 1, 4)));
      _wirelessRetryAfter = DateTime.now().add(Duration(milliseconds: delay));
      _safeSetState(
        () => _wirelessStatus =
            'Camera not responding. Retrying the same CCAPI connection; '
            'received photos remain queued. Check Wi-Fi and Local Network access.',
      );
    } finally {
      if (_wirelessActive(generation)) _wirelessBusy = false;
    }
  }

  Future<void> _pollGallery(EventSummary event, int generation) async {
    if (!_galleryActive(generation) || _galleryBusy) return;

    final sinceMs = _gallerySinceMs;
    if (sinceMs == null) return;

    _safeSetState(() {
      _galleryBusy = true;
      _galleryStatus = 'Checking phone photos...';
    });

    try {
      final images = await GalleryAutoImport.recentImages(
        sinceMs: sinceMs,
        excludeIds: _processedGalleryIds.toList(),
      );
      if (!_galleryActive(generation)) return;

      if (images.isEmpty) {
        _safeSetState(() => _galleryStatus = 'Waiting for new phone photos...');
        return;
      }

      for (final image in images.reversed) {
        if (!_galleryActive(generation)) return;
        if (_processedGalleryIds.contains(image.id)) continue;

        _safeSetState(() => _galleryStatus = 'Importing ${image.name}...');
        final uploaded = await _uploadOrQueueFile(
          event: event,
          path: image.path,
          filename: image.name,
          source: 'gallery',
        );
        if (!_galleryActive(generation)) return;
        _processedGalleryIds.add(image.id);
        await UploadedGalleryStorage.add(id: image.id, name: image.name);

        try {
          await File(image.path).delete();
        } catch (_) {}

        if (!mounted) return;
        _safeSetState(() {
          _galleryStatus = uploaded
              ? 'Uploaded ${image.name}'
              : 'Saved ${image.name}. Upload queued for internet.';
        });
      }
    } on MissingPluginException {
      if (_galleryActive(generation)) {
        _safeSetState(() {
          _galleryStatus = 'Restart app once to enable phone auto-upload';
        });
      }
    } catch (_) {
      if (_galleryActive(generation)) {
        _safeSetState(() {
          _galleryStatus = 'Phone auto-upload failed. Check photo permission.';
        });
      }
    } finally {
      if (_galleryActive(generation)) {
        _safeSetState(() => _galleryBusy = false);
      }
    }
  }

  Future<void> _startGalleryAutoImport(EventSummary event) async {
    final generation = ++_galleryGeneration;
    final allowed = await _requestGalleryPermission();
    if (!_galleryActive(generation)) return;
    if (!allowed) {
      AppToast.error('Photo permission is required');
      return;
    }

    _beginReceivingSession(event, 'gallery');
    _galleryTimer?.cancel();
    _processedGalleryIds.clear();
    _safeSetState(() {
      _galleryImporting = true;
      _gallerySinceMs = DateTime.now().millisecondsSinceEpoch;
      _galleryStatus = 'Phone auto-upload is on';
    });

    _galleryTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!_galleryActive(generation)) {
        timer.cancel();
        return;
      }
      unawaited(_pollGallery(event, generation));
    });
  }

  void _changeUsbUploadMode(LiveCameraUploadMode mode) {
    if (_usbSessionLocked || mode == _usbUploadMode) return;
    // Change the UI immediately. Preference writes are serialized in the
    // background so rapid taps stay responsive and the last tap wins on disk.
    _safeSetState(() => _usbUploadMode = mode);
    _usbModeSaveQueue = _usbModeSaveQueue.then((_) async {
      try {
        await UsbCameraUploadModeStorage.save(mode);
      } catch (error) {
        debugPrint('USB transfer mode preference save failed: $error');
        if (mounted && !_disposed && _usbUploadMode == mode) {
          AppToast.error(
            'Could not remember this transfer mode. It still applies to the next session in this app run.',
          );
        }
      }
    });
  }

  Future<void> _startOtgAutoImport(
    _UsbCaptureTarget target, {
    required int generation,
    LiveCameraTransport? transport,
    String source = 'otg-ptp',
  }) async {
    if (_wirelessShutdown != null) await _wirelessShutdown;
    if (!_usbStartActive(generation, target) || _otgStarting) return;
    final event = target.event;
    _beginReceivingSession(event, 'usb');
    _usbSessionUploadMode = target.uploadMode;
    _usbSessionPhotoCatalogReader = target.photoCatalog;
    _wiredPhotoReceived = false;
    _safeSetState(() {
      _otgStarting = true;
      _otgImporting = true;
      _otgBusy = true;
      _otgStatus = 'Connecting for live shooting...';
    });
    final capture = LiveCameraCapture(
      transport:
          transport ??
          preferredUsbCameraTransport(
            platform: Platform.isIOS
                ? TargetPlatform.iOS
                : TargetPlatform.android,
            uploadMode: target.uploadMode,
            usePhotoCatalog: target.photoCatalog,
          ),
      uploadMode: target.uploadMode,
      // Catalog events wake immediately; rescan gently when an event is absent.
      pollInterval: target.photoCatalog
          ? const Duration(seconds: 3)
          : const Duration(milliseconds: 500),
      onUpdate: (update) {
        if (!_otgActive(generation)) return;
        _safeSetState(() {
          _otgBusy =
              update.phase == LiveCameraPhase.connecting ||
              update.phase == LiveCameraPhase.importing;
          if (_isUsbReleaseError(update.code)) {
            _usbReleaseIssue = update.message;
            _otgImporting = false;
            _otgBusy = false;
          }
          if (update.phase == LiveCameraPhase.disconnected ||
              update.phase == LiveCameraPhase.stopped) {
            _otgImporting = false;
            _otgBusy = false;
            _otgSourceName = null;
          }
          _otgStatus = update.message;
        });
      },
    );
    _liveCamera = capture;
    try {
      final session = await capture.start(
        save: (file, session) async {
          // Save a separate queue copy before native ACK. Internet delivery
          // runs independently so burst shooting is not network-bound.
          await UploadQueueService.receiveCameraFile(
            event: event,
            path: file.path,
            filename: file.name,
            isEnhanced: target.isEnhanced,
            albumId: target.albumId,
            source: source,
            cameraId: session.name,
            fingerprint: '${event.id}|$source|${session.cameraId}|${file.id}',
          );
          if (_otgActive(generation)) {
            _safeSetState(() => _wiredPhotoReceived = true);
          }
          // The durable queue owns its separate copy. Journal deletion of
          // this private camera buffer so a failed delete survives a restart.
          await CameraStagingCleanup.release(file.path);
        },
      );
      if (!_otgActive(generation)) {
        await capture.stop(notify: false);
        return;
      }
      _safeSetState(() {
        _usbReleaseIssue = null;
        _otgSourceName = session.name;
        // Reflect the actual transport when a failed PTP handshake was
        // recovered by the passive catalog without changing USB modes.
        _usbSessionPhotoCatalogReader = session.usesPhotoCatalog;
        _otgBusy = false;
      });
      unawaited(_showTransferSessionPage(event));
    } on MissingPluginException {
      if (_otgActive(generation)) {
        _safeSetState(() {
          _otgImporting = false;
          _otgBusy = false;
          _otgStatus =
              'Install a new native app build to use live USB shooting. '
              'Hot reload cannot add this feature.';
        });
        AppToast.error('Install the new app build for live USB shooting.');
      }
    } on PlatformException catch (error) {
      if (!_otgActive(generation) ||
          error.code == 'LIVE_CAMERA_CANCELLED' ||
          error.code == 'CAMERA_SESSION_CANCELLED') {
        return;
      }
      final advice = UsbCameraGuidance.forStatus(
        error.code,
        message: error.message,
      );
      _safeSetState(() {
        _otgImporting = false;
        _otgBusy = false;
        _otgStatus = '${advice.details} ${advice.nextSteps}';
        if (_isUsbReleaseError(error.code)) _usbReleaseIssue = _otgStatus;
      });
      AppToast.error(advice.title);
      unawaited(
        _showUsbLiveFailure(
          advice,
          error.code,
          modeAdvice: UsbShootingModeAdvice.fromFailure(error),
          diagnosticDetails: error.details,
          onTryPhotoCatalog:
              !target.photoCatalog &&
                  (Platform.isIOS || Platform.isAndroid) &&
                  const {
                    'PTP_INVALID_RESPONSE',
                    'PTP_PASSTHROUGH_UNAVAILABLE',
                    'TETHER_CAMERA_UNSUPPORTED',
                  }.contains(error.code)
              ? () {
                  if (!_otgActive(generation) ||
                      _usbSessionLocked ||
                      ActiveEventStorage.activeEvent.value?.id != event.id) {
                    return;
                  }
                  _safeSetState(() => _usbPhotoCatalogReader = true);
                  unawaited(_toggleOtgAutoUpload(event));
                }
              : null,
        ),
      );
    } catch (error) {
      if (_otgActive(generation)) {
        _safeSetState(() {
          _otgImporting = false;
          _otgBusy = false;
          _otgStatus = 'Live camera connection failed: $error';
        });
      }
    } finally {
      if (_otgActive(generation)) {
        _safeSetState(() => _otgStarting = false);
      }
    }
  }

  Future<void> _stopOtgAutoImport() => _usbShutdown ??= _finishOtgAutoImport()
      .whenComplete(() => _usbShutdown = null);

  Future<void> _finishOtgAutoImport() async {
    final generation = ++_otgGeneration;
    final capture = _liveCamera;
    final hadActiveCapture = capture?.isActive == true;
    _liveCamera = null;
    _liveCameraEventId = null;
    _safeSetState(() {
      _usbStartRequested = false;
      _otgImporting = false;
      _otgBusy = true;
      _otgStarting = true;
      _otgStatus = 'Closing live camera connection...';
    });
    String? releaseIssue;
    var releaseConfirmed = false;
    try {
      await capture?.stop(notify: false);
      releaseConfirmed = hadActiveCapture;
    } catch (error) {
      debugPrint('USB session close: $error');
      final advice = UsbCameraGuidance.forStatus(
        'PTP_CLOSE_FAILED',
        message: error is PlatformException ? error.message : null,
      );
      releaseIssue = '${advice.details} ${advice.nextSteps}';
    } finally {
      if (_otgActive(generation)) {
        _safeSetState(() {
          if (releaseIssue != null) {
            _usbReleaseIssue = releaseIssue;
          } else if (releaseConfirmed) {
            _usbReleaseIssue = null;
          }
          _otgBusy = false;
          _otgStarting = false;
          _otgSourceName = null;
          _otgStatus =
              _usbReleaseIssue ??
              'Live shooting stopped. Received photos continue uploading to cloud.';
        });
        if (releaseIssue != null) {
          AppToast.error('Disconnect USB to release the camera.');
        }
      }
    }
  }

  void _stopGalleryAutoImport() {
    _galleryGeneration += 1;
    _galleryTimer?.cancel();
    _galleryTimer = null;
    _safeSetState(() {
      _galleryImporting = false;
      _galleryBusy = false;
      _gallerySinceMs = null;
      _galleryStatus = 'Phone auto-upload stopped';
    });
  }

  Future<void> _freeUploadedGallerySpace() async {
    final uploaded = UploadedGalleryStorage.getImages();
    if (uploaded.isEmpty) {
      AppToast.error('No uploaded phone images to remove');
      return;
    }

    _safeSetState(() {
      _freeingSpace = true;
      _galleryStatus = 'Removing uploaded phone images...';
    });

    final deletedIds = <String>{};
    for (final image in uploaded) {
      try {
        final deleted = await GalleryAutoImport.deleteImage(image.id);
        if (deleted) {
          deletedIds.add(image.id);
        }
      } catch (_) {}
    }

    await UploadedGalleryStorage.removeIds(deletedIds);

    if (!mounted) return;
    _safeSetState(() {
      _freeingSpace = false;
      _galleryStatus = deletedIds.isEmpty
          ? 'No phone images removed'
          : 'Removed ${deletedIds.length} uploaded images';
    });
  }

  Future<void> _stopWirelessImport() => _wirelessShutdown ??=
      _finishWirelessImport().whenComplete(() => _wirelessShutdown = null);

  Future<void> _finishWirelessImport() async {
    _wirelessGeneration += 1;
    final ftp = _ftpReceiver;
    final awakeOwner = _wirelessAwakeOwner;
    _ftpReceiver = null;
    _ftpConnection = null;
    _ftpStarting = false;
    _wirelessAwakeOwner = null;
    _wirelessTimer?.cancel();
    _wirelessTimer = null;
    _wirelessConnectCancellation?.cancel('Receiving stopped');
    _wirelessConnectCancellation = null;
    _wirelessRetryAfter = null;
    final canonCamera = _canonCcapiCamera;
    _canonCcapiCamera = null;
    _safeSetState(() {
      _autoImporting = false;
      _wirelessScanning = false;
      _wirelessBusy = false;
      _wirelessFailureCount = 0;
      _wirelessStatus =
          'Receiving stopped. Received photos continue uploading to cloud.';
    });
    try {
      if (ftp != null) await ftp.stop();
      if (canonCamera != null) await canonCamera.close();
    } finally {
      if (awakeOwner != null) {
        await TransferScreenAwake.setEnabled(awakeOwner, false);
      }
    }
  }

  Future<void> _togglePhoneAutoUpload(EventSummary event) async {
    if (_usbStartRequested) return;
    if (_wirelessShutdown != null) await _wirelessShutdown;
    if (!mounted || _disposed || _usbStartRequested) return;
    if (_galleryImporting) {
      _stopGalleryAutoImport();
      return;
    }
    if (_liveCamera != null) await _stopOtgAutoImport();
    if (_wirelessImporting) await _stopWirelessImport();
    await _startGalleryAutoImport(event);
  }

  Future<void> _toggleOtgAutoUpload(EventSummary event) async {
    if (_otgImporting) {
      await _stopOtgAutoImport();
      return;
    }
    if (!mounted ||
        _disposed ||
        _otgStarting ||
        _usbStartRequested ||
        _usbPickInProgress ||
        ActiveEventStorage.activeEvent.value?.id != event.id) {
      return;
    }
    // Reserve this exact event and generation before closing another receiver.
    // A pause, event change or stop invalidates it while that await is pending.
    final generation = ++_otgGeneration;
    final target = _UsbCaptureTarget(
      event: event,
      uploadMode: _usbUploadMode,
      photoCatalog: _usbPhotoCatalogReader,
      isEnhanced: _isEnhanced,
      albumId: _selectedAlbumId,
    );
    _safeSetState(() {
      _liveCameraEventId = target.event.id;
      _usbStartRequested = true;
    });
    try {
      if (_galleryImporting) _stopGalleryAutoImport();
      if (_wirelessImporting) await _stopWirelessImport();
      if (!_usbStartActive(generation, target)) return;
      await _startOtgAutoImport(target, generation: generation);
    } finally {
      if (_otgActive(generation)) {
        _safeSetState(() {
          _usbStartRequested = false;
          if (!_otgImporting && !_otgStarting) _liveCameraEventId = null;
        });
      }
    }
  }

  Future<Uri?> _choosePcSimulatorAddress() async {
    if (Platform.isAndroid) {
      // Android uses USB ADB reverse, not a camera/PTP connection.
      return Uri.parse('http://127.0.0.1:8765');
    }
    if (!Platform.isIOS) return null;
    final controller = TextEditingController(
      text: const String.fromEnvironment('AIRPIX_PC_SIMULATOR_URL'),
    );
    try {
      final address = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('PC photo simulator'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Test photo receiving and cloud uploads from your PC. '
                'This does NOT make the PC a USB/PTP camera or prove real '
                'camera cable compatibility.',
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('pc_simulator_address'),
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'PC IP address and port',
                  hintText: '192.168.1.10:8765',
                  helperText:
                      'Same Wi-Fi or iPhone USB Personal Hotspot network',
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Run start-ios.ps1 on your PC first. Use the PC IPv4 address '
                'it displays, not localhost. On iPhone, allow Local Network '
                'access when asked.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('Connect simulator'),
            ),
          ],
        ),
      );
      if (address == null || !mounted) return null;
      return parseDebugPcSimulatorUrl(address);
    } on FormatException catch (error) {
      AppToast.error(error.message);
      return null;
    } finally {
      controller.dispose();
    }
  }

  Future<void> _startPcUsbTestBridge() async {
    if (!mounted || _disposed || !_pcSimulatorEnabled) return;
    final baseUri = await _choosePcSimulatorAddress();
    if (baseUri == null || !mounted || _disposed) return;
    final event = ActiveEventStorage.activeEvent.value;
    if (event == null) {
      AppToast.error('Select an active event first');
      return;
    }
    if (_otgImporting) {
      await _stopOtgAutoImport();
    }
    if (_otgStarting ||
        _usbStartRequested ||
        _usbPickInProgress ||
        ActiveEventStorage.activeEvent.value?.id != event.id) {
      return;
    }

    final generation = ++_otgGeneration;
    final target = _UsbCaptureTarget(
      event: event,
      uploadMode: LiveCameraUploadMode.newShotsOnly,
      isEnhanced: _isEnhanced,
      albumId: _selectedAlbumId,
    );
    _safeSetState(() {
      _liveCameraEventId = event.id;
      _usbStartRequested = true;
      _otgStatus = 'Connecting to the PC camera simulator...';
    });
    try {
      if (_galleryImporting) _stopGalleryAutoImport();
      if (_wirelessImporting) await _stopWirelessImport();
      if (!_usbStartActive(generation, target)) return;
      await _startOtgAutoImport(
        target,
        generation: generation,
        transport: DebugPcCameraTransport(baseUri: baseUri),
        source: Platform.isIOS ? 'pc-network-test' : 'pc-usb-test',
      );
    } finally {
      if (_otgActive(generation)) {
        _safeSetState(() {
          _usbStartRequested = false;
          if (!_otgImporting && !_otgStarting) _liveCameraEventId = null;
        });
      }
    }
  }

  Future<void> _toggleWirelessAutoUpload(EventSummary event) async {
    if (_usbStartRequested) return;
    if (_wirelessImporting) {
      await _stopWirelessImport();
      return;
    }
    if (_galleryImporting) _stopGalleryAutoImport();
    if (_liveCamera != null) await _stopOtgAutoImport();
    await _handleWirelessAction(event);
  }

  Future<void> _handleWirelessAction(EventSummary? event) async {
    if (_wirelessImporting) {
      await _stopWirelessImport();
      return;
    }

    if (event == null) {
      AppToast.error('Select active event first');
      return;
    }

    final choice = await showModalBottomSheet<_WirelessImportMode>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Wireless live shooting: use camera FTP auto-send or Canon CCAPI on supported models. '
                    'Keep the camera in shooting mode and AirPix open. No file-transfer or live-view fallback is used.',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.add_a_photo_outlined),
                  title: const Text('Live shooting with camera FTP'),
                  subtitle: const Text(
                    'For cameras with FTP automatic transfer. Each new photo uploads to your event automatically while you keep shooting.',
                  ),
                  onTap: () =>
                      Navigator.of(context).pop(_WirelessImportMode.ftp),
                ),
                ListTile(
                  leading: const Icon(Icons.router_outlined),
                  title: const Text('Canon CCAPI on shared Wi-Fi'),
                  subtitle: const Text(
                    'For a Canon camera with CCAPI enabled. Enter its address and allow Local Network access. Internet on this Wi-Fi enables immediate uploads.',
                  ),
                  onTap: () => Navigator.of(
                    context,
                  ).pop(_WirelessImportMode.sharedNetwork),
                ),
                ListTile(
                  leading: const Icon(Icons.wifi_tethering_outlined),
                  title: const Text('Canon CCAPI on camera Wi-Fi'),
                  subtitle: const Text(
                    'Enable Canon CCAPI, then join the camera hotspot in phone Wi-Fi settings. Photos queue when this network has no internet.',
                  ),
                  onTap: () => Navigator.of(
                    context,
                  ).pop(_WirelessImportMode.cameraHotspot),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted ||
        _disposed ||
        choice == null ||
        ActiveEventStorage.activeEvent.value?.id != event.id) {
      return;
    }
    if (choice == _WirelessImportMode.ftp) {
      await _startFtpCameraSession(event);
    } else {
      await _findAndStartWirelessImport(event, choice);
    }
  }

  Future<void> _startFtpCameraSession(EventSummary event) async {
    if (_ftpStarting) return;
    if (_wirelessShutdown != null) await _wirelessShutdown;
    if (!mounted ||
        _disposed ||
        _wirelessImporting ||
        ActiveEventStorage.activeEvent.value?.id != event.id) {
      return;
    }
    _beginReceivingSession(event, 'ftp');
    final generation = ++_wirelessGeneration;
    final albumId = _selectedAlbumId;
    final enhanced = _isEnhanced;
    _safeSetState(() {
      _ftpStarting = true;
      _ftpHasReceived = false;
      _wirelessStatus = 'Preparing Wi-Fi photo receiver...';
    });
    CameraFtpReceiver? receiver;
    try {
      final addresses = await CameraFtpReceiver.availableAddresses();
      if (!_wirelessActive(generation)) return;
      if (addresses.isEmpty) {
        throw const SocketException(
          'Connect this phone and your camera to the same Wi-Fi network, then start again.',
        );
      }
      var address = addresses.first;
      if (addresses.length > 1) {
        if (!mounted) return;
        final selected = await showDialog<InternetAddress>(
          context: context,
          builder: (dialogContext) => SimpleDialog(
            title: const Text('Choose your Wi-Fi address'),
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text('Use the network shared by your phone and camera.'),
              ),
              for (final candidate in addresses)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialogContext, candidate),
                  child: Text(candidate.address),
                ),
            ],
          ),
        );
        if (!_wirelessActive(generation)) return;
        if (selected == null) {
          _safeSetState(() => _wirelessStatus = 'Wireless setup cancelled.');
          return;
        }
        address = selected;
      }
      final profile = await CameraFtpProfileStorage.load();
      final temporary = await getTemporaryDirectory();
      if (!_wirelessActive(generation)) return;
      receiver = CameraFtpReceiver(
        stagingDirectory: Directory(
          '${temporary.path}${Platform.pathSeparator}camera_ftp',
        ),
        onFile: (file) async {
          // FTP 226 (accepted) is sent only after this local copy is durable.
          // The camera can send its next shot without waiting for cloud upload.
          await UploadQueueService.receiveCameraFile(
            event: event,
            path: file.localPath,
            filename: file.name,
            isEnhanced: enhanced,
            albumId: albumId,
            source: 'wireless-ftp',
            cameraId: 'Camera FTP',
            fingerprint: '${event.id}|wireless-ftp|${file.fingerprint}',
          );
          // The durable queue owns a separate copy; journal staging cleanup.
          await CameraStagingCleanup.release(file.localPath);
          if (_wirelessActive(generation)) {
            _safeSetState(() {
              _ftpHasReceived = true;
              _wirelessStatus =
                  'Photo received. Cloud upload starts automatically. Keep shooting.';
            });
          }
        },
        onClientAuthenticated: () {
          if (!_wirelessActive(generation)) return;
          _safeSetState(
            () => _wirelessStatus =
                'Camera connected. Enable automatic FTP transfer and take a photo.',
          );
        },
        onClientDisconnected: () {
          if (!_wirelessActive(generation)) return;
          _safeSetState(
            () => _wirelessStatus =
                'Receiver ready. The camera can reconnect for its next photo.',
          );
        },
        onError: (error) {
          if (!_wirelessActive(generation)) return;
          _safeSetState(
            () => _wirelessStatus =
                'Camera transfer interrupted. Waiting for the camera to retry.',
          );
        },
      );
      _ftpReceiver = receiver;
      final connection = await receiver.start(
        address: address,
        port: CameraFtpProfile.port,
        username: profile.username,
        password: profile.password,
      );
      if (!_wirelessActive(generation)) {
        await receiver.stop();
        return;
      }
      _wirelessAwakeOwner = 'wireless-$_receiverOwnerId-$generation';
      await TransferScreenAwake.setEnabled(_wirelessAwakeOwner!, true);
      if (!_wirelessActive(generation)) return;
      _safeSetState(() {
        _ftpConnection = connection;
        _ftpStarting = false;
        _autoImporting = true;
        _wirelessStatus =
            'Receiver ready. Add the settings below to your camera FTP profile.';
      });
      unawaited(_showTransferSessionPage(event));
    } catch (error) {
      await receiver?.stop();
      if (_wirelessActive(generation)) {
        _ftpReceiver = null;
        _ftpConnection = null;
        _safeSetState(() {
          _autoImporting = false;
          _wirelessStatus = error is SocketException
              ? error.message
              : 'Could not start the Wi-Fi receiver. Check local network access and try again.';
        });
        AppToast.error(_wirelessStatus!);
      }
    } finally {
      if (_wirelessActive(generation)) {
        _safeSetState(() => _ftpStarting = false);
      }
    }
  }

  Widget _buildSessionConnectionDetails(BuildContext pageContext) {
    final connection = _ftpConnection;
    if (_sessionKind == 'ftp' && connection != null) {
      final settings = <String, String>{
        'Server / host': connection.host,
        'Port': '${connection.port}',
        'Username': connection.username,
        'Password': connection.password,
        'Passive mode': 'On',
        'Encryption': 'None (FTP)',
        'Folder': '/',
      };
      return Card(
        child: ExpansionTile(
          key: ValueKey(_ftpHasReceived),
          initiallyExpanded: !_ftpHasReceived,
          title: const Text('Camera FTP settings'),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Connect your camera once',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '1. Join the same Wi-Fi network on the camera and phone.\n'
                    '2. Enter these settings in the camera FTP profile.\n'
                    '3. Turn on automatic transfer after each shot, then return to shooting and take a photo.\n'
                    'Sony: Auto Trans When Shot / Auto Transfer. Other models: Automatic FTP transfer / Auto send (names vary).\n'
                    '4. Allow Local Network access if asked. Keep AirPix open while shooting.',
                  ),
                  const SizedBox(height: 12),
                  for (final setting in settings.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 116,
                            child: Text(
                              setting.key,
                              style: const TextStyle(
                                color: AppColors.mutedForeground,
                              ),
                            ),
                          ),
                          Expanded(
                            child: SelectableText(
                              setting.value,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(
                          text: settings.entries
                              .map((entry) => '${entry.key}: ${entry.value}')
                              .join('\n'),
                        ),
                      );
                      if (pageContext.mounted) {
                        ScaffoldMessenger.of(pageContext).showSnackBar(
                          const SnackBar(
                            content: Text('Camera FTP settings copied'),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Copy settings'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Use trusted Wi-Fi: this local FTP connection is unencrypted. '
                    'The camera must support FTP automatic transfer. '
                    'Your login is saved on this phone; only update the server address if your Wi-Fi address changes. '
                    'Keep AirPix open while shooting. Cloud uploads wait when internet is unavailable.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    if (_sessionKind == 'wireless' && _canonCcapiCamera != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Canon CCAPI: photo receiving',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(_canonCcapiCamera!.sourceUrl),
              const Text(
                'Use the camera shutter. AirPix reads new-photo events every 0.5 seconds when idle. '
                'Keep AirPix open and allow Local Network access. Photos wait safely in the upload queue when internet is unavailable.',
              ),
              TextButton.icon(
                onPressed: () async {
                  await _stopWirelessImport();
                  _safeSetState(
                    () => _wirelessStatus =
                        'Connection released. Check camera shooting mode before reconnecting.',
                  );
                },
                icon: const Icon(Icons.link_off),
                label: const Text('Camera cannot shoot? Stop connection'),
              ),
            ],
          ),
        ),
      );
    }
    if (_sessionKind == 'usb' && _otgImporting) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'USB uploads: '
                '${UsbCameraUploadModeSelector.labelFor(_usbSessionUploadMode)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (_usbSessionPhotoCatalogReader)
                const Text(
                  'Compatibility photo reader: checking for new photos every '
                  '3 seconds. On iPhone, photo notifications can wake receiving '
                  'sooner. Take a test shot to verify receipt.',
                  style: TextStyle(fontSize: 12),
                ),
              const SizedBox(height: 8),
              Text(
                _wiredPhotoReceived
                    ? 'Camera photos are arriving and start uploading automatically.'
                    : 'Take a photo using the camera shutter once the connection is ready.',
              ),
              const SizedBox(height: 8),
              const Text(
                'If the camera shows a transfer screen or its shutter is locked, '
                'release this connection and choose the shooting mode supported by your camera model.',
                style: TextStyle(fontSize: 12),
              ),
              TextButton.icon(
                onPressed: () async {
                  await _stopOtgAutoImport();
                  if (mounted && _usbReleaseIssue == null) {
                    await _showLiveCameraSetup();
                  }
                },
                icon: const Icon(Icons.usb_off),
                label: const Text('Camera locked? Release connection'),
              ),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _submit(EventSummary event) async {
    if (_selectedFiles.isEmpty) {
      AppToast.error('Choose images first');
      return;
    }

    final files = List<_SelectedUploadFile>.from(_selectedFiles);

    _safeSetState(() {
      _uploading = true;
      _uploadStatus = 'Uploading ${files.length} images...';
    });

    try {
      final imageUrls = await _uploadFilesBatch(files);
      if (imageUrls.isEmpty) {
        throw Exception('Image upload returned no URLs');
      }

      _safeSetState(() {
        _uploadStatus =
            'Saving ${imageUrls.length} images to ${event.title}...';
      });

      await _createEventImages(event, imageUrls);
      AppToast.success('${imageUrls.length} images uploaded to ${event.title}');
      _safeSetState(() {
        _selectedFiles.clear();
        _isEnhanced = false;
        _uploadStatus = null;
      });
    } on DioException catch (error) {
      AppToast.error(
        error.response?.data?['message']?.toString() ??
            'Failed to upload images',
      );
    } catch (_) {
      AppToast.error('Failed to upload images');
    } finally {
      if (mounted) {
        _safeSetState(() => _uploading = false);
      }
    }
  }

  Future<void> _ensureSoloActiveEvent() async {
    if (_resolvingSoloEvent || _soloEventResolved) return;
    if (ActiveEventStorage.activeEvent.value != null) {
      _soloEventResolved = true;
      return;
    }
    final user = UserStorage.currentUser.value;
    if (!(user?.isPhotographer ?? false) ||
        !(user?.hasPlannerAccess ?? false)) {
      return;
    }

    _safeSetState(() => _resolvingSoloEvent = true);
    try {
      final response = await DioHelper.get(
        '/event/my-events',
        queryParameters: {'workspace': 'planner', 'page': 1, 'limit': 1},
      );
      final rows = response.data is Map ? response.data['data'] : null;
      Map<String, dynamic>? rawEvent;
      if (rows is List && rows.isNotEmpty && rows.first is Map) {
        rawEvent = Map<String, dynamic>.from(rows.first as Map);
      }

      if (rawEvent == null) {
        final created = await DioHelper.post(
          '/event',
          data: {
            'title': 'Solo Workspace',
            'description': 'My photographer delivery workspace',
            'isPublished': true,
          },
        );
        final raw = created.data is Map ? created.data['data'] : null;
        if (raw is Map) rawEvent = Map<String, dynamic>.from(raw);
      }

      if (rawEvent != null) {
        final event = EventSummary.fromJson(rawEvent);
        if (event.id.isNotEmpty) {
          await ActiveEventStorage.saveActiveEvent(event);
        }
      }
    } catch (_) {
      // Keep manual event selection available if the automatic solo workspace fails.
    } finally {
      _soloEventResolved = true;
      _safeSetState(() => _resolvingSoloEvent = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: ActiveEventStorage.activeEvent,
      builder: (context, activeEvent, _) {
        if (activeEvent != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _loadAlbumsForEvent(activeEvent);
          });
        } else if (_loadedAlbumEventId != null) {
          _loadedAlbumEventId = null;
          _selectedAlbumId = null;
          _albums = [];
        }
        if (activeEvent == null &&
            (UserStorage.currentUser.value?.hasPlannerAccess ?? false)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _ensureSoloActiveEvent();
          });
        }

        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 82,
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Upload'),
                SizedBox(height: 3),
                Text(
                  'Capture, sync and deliver',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ],
            ),
            actions: [
              if (activeEvent != null)
                TextButton.icon(
                  onPressed: _connectionPageOpen
                      ? null
                      : () => _showTransferSessionPage(activeEvent),
                  icon: Icon(
                    _liveConnectionActive
                        ? Icons.camera_alt_rounded
                        : Icons.tune_rounded,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  label: const Text('Session'),
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              // ── Active event ──
              if (activeEvent == null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        if (_resolvingSoloEvent)
                          const Padding(
                            padding: EdgeInsets.only(right: 12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            (UserStorage.currentUser.value?.hasPlannerAccess ??
                                    false)
                                ? 'Preparing your solo photographer workspace. You do not need a planner invitation.'
                                : 'No active event selected. Accept an invitation and make an event active first.',
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Card(
                  child: ListTile(
                    dense: true,
                    title: const Text('Active event'),
                    subtitle: Text(activeEvent.title),
                    trailing: IconButton(
                      tooltip: 'Clear active event',
                      onPressed: _uploading ? null : ActiveEventStorage.clear,
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ),
                ),

              // ── Album picker ──
              if (activeEvent != null && _albums.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: DropdownButtonFormField<String?>(
                    initialValue: _selectedAlbumId,
                    isDense: true,
                    decoration: InputDecoration(
                      labelText: 'Upload album',
                      helperText: _otgImporting
                          ? 'Stop live shooting to change the album.'
                          : null,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('No album'),
                      ),
                      ..._albums.map(
                        (album) => DropdownMenuItem<String?>(
                          value: album.id,
                          child: Text(album.title),
                        ),
                      ),
                    ],
                    onChanged:
                        _uploading ||
                            _liveConnectionActive ||
                            _otgStarting ||
                            _usbStartRequested
                        ? null
                        : (value) =>
                              _safeSetState(() => _selectedAlbumId = value),
                  ),
                ),

              const SizedBox(height: 8),

              if (activeEvent != null && _liveConnectionActive) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () => _showTransferSessionPage(activeEvent),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Open live camera session'),
                  ),
                ),
                const SizedBox(height: 10),
              ],

              AppSectionTitle(
                title: 'Camera upload',
                actionLabel: _liveConnectionActive ? 'Live' : 'Ready',
              ),
              const SizedBox(height: 4),
              const Text(
                'Connect your camera, start the session once, then keep shooting. New photos upload automatically.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.mutedForeground,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _showLiveCameraSetup,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: AppColors.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Before USB: select Remote Shooting / PC Remote / '
                          'Tether on the camera. Names vary by brand. '
                          'Tap for your camera’s USB mode and setup.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.mutedForeground,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final usbCard = _cameraConnectionCard(
                    icon: Icons.usb_rounded,
                    title: 'USB / OTG',
                    badge: _usbPhotoCatalogReader
                        ? 'PTP / MTP reader'
                        : 'Tether',
                    subtitle:
                        'Choose the USB shooting mode on your camera first. '
                        'New photos sync automatically. AirPix never switches '
                        'to Mass Storage if connection fails.',
                    detail: _usbUploadMode == LiveCameraUploadMode.newShotsOnly
                        ? 'New shots upload automatically'
                        : 'Existing + new photos upload',
                    active: _otgImporting,
                    busy: _otgBusy || _otgStarting || _usbStartRequested,
                    status: _otgStatus,
                    startLabel: 'Connect & start',
                    stopLabel: 'Stop session',
                    onPressed: activeEvent == null || _uploading
                        ? null
                        : () => _toggleOtgAutoUpload(activeEvent),
                    onMenu: _showUsbCameraOptions,
                  );
                  final wirelessCard = _cameraConnectionCard(
                    icon: Icons.wifi_tethering_rounded,
                    title: 'Wireless',
                    subtitle:
                        'Use camera FTP auto-send or Canon CCAPI on supported models. Keep AirPix open while shooting.',
                    detail: 'New shots upload automatically',
                    active: _wirelessImporting,
                    busy: _wirelessBusy || _wirelessScanning,
                    status: _wirelessStatus,
                    startLabel: 'Start wireless',
                    stopLabel: 'Stop session',
                    onPressed:
                        activeEvent == null || _uploading || _usbStartRequested
                        ? null
                        : () => _toggleWirelessAutoUpload(activeEvent),
                    onMenu: _showWirelessCameraOptions,
                  );
                  if (constraints.maxWidth < 460) {
                    return Column(
                      children: [
                        usbCard,
                        const SizedBox(height: 10),
                        wirelessCard,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: usbCard),
                      const SizedBox(width: 10),
                      Expanded(child: wirelessCard),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                  childrenPadding: const EdgeInsets.only(bottom: 6),
                  leading: const Icon(Icons.add_photo_alternate_outlined),
                  title: const Text(
                    'Other ways to add photos',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Phone photos, phone camera, files and gallery watching',
                    style: TextStyle(fontSize: 11),
                  ),
                  children: [
                    _uploadSourceTile(
                      icon: Icons.photo_library_outlined,
                      title: 'Phone photos',
                      subtitle: 'Choose existing photos from this phone.',
                      onTap: _uploading ? null : _pickPhoneImages,
                    ),
                    _uploadSourceTile(
                      icon: Icons.camera_alt_outlined,
                      title: 'Take a phone photo',
                      subtitle: 'Take one photo with the phone camera.',
                      onTap: _uploading ? null : _pickCameraImage,
                    ),
                    _uploadSourceTile(
                      icon: Icons.sd_storage_outlined,
                      title: 'Files / SD card / USB storage',
                      subtitle: 'Choose stored photos from the Files picker.',
                      onTap: _uploading ? null : _pickOtgFilesFromFiles,
                    ),
                    _uploadSourceTile(
                      icon: _galleryImporting
                          ? Icons.stop_circle_outlined
                          : Icons.phone_android_outlined,
                      title: _galleryImporting
                          ? 'Stop watching phone gallery'
                          : 'Watch phone gallery',
                      subtitle:
                          _galleryStatus ??
                          'Optional: auto-upload new photos saved by this phone.',
                      onTap:
                          activeEvent == null ||
                              _uploading ||
                              _usbStartRequested
                          ? null
                          : () => _togglePhoneAutoUpload(activeEvent),
                    ),
                    if (activeEvent != null)
                      _uploadSourceTile(
                        icon: Icons.image_outlined,
                        title: 'Uploaded photos',
                        subtitle: 'View photos already uploaded to this event.',
                        onTap: () =>
                            context.router.root.push(const EventImagesRoute()),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // ── Section 3: Upload Queue ──
              ValueListenableBuilder(
                valueListenable: UploadQueueStorage.items,
                builder: (context, queued, _) {
                  return ValueListenableBuilder(
                    valueListenable: UploadQueueService.isProcessing,
                    builder: (context, queueBusy, _) {
                      final count = queued.length;
                      return Card(
                        margin: EdgeInsets.zero,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ExpansionTile(
                          initiallyExpanded: count > 0,
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 0,
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            14,
                            0,
                            14,
                            12,
                          ),
                          leading: const Icon(
                            Icons.cloud_upload_outlined,
                            size: 22,
                          ),
                          title: Text(
                            count == 0
                                ? 'Upload Queue'
                                : 'Upload Queue ($count)',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: count == 0 || queueBusy
                                        ? null
                                        : () async {
                                            await UploadQueueService.processQueue();
                                            if (!mounted) return;
                                            final left = UploadQueueStorage
                                                .items
                                                .value
                                                .length;
                                            if (left == 0) {
                                              AppToast.success(
                                                'Queued uploads complete',
                                              );
                                            } else {
                                              AppToast.error(
                                                '$left uploads still waiting',
                                              );
                                            }
                                          },
                                    icon: Icon(
                                      queueBusy
                                          ? Icons.sync
                                          : Icons.cloud_upload_outlined,
                                      size: 18,
                                    ),
                                    label: Text(
                                      queueBusy
                                          ? 'Uploading...'
                                          : count == 0
                                          ? 'No queued'
                                          : 'Upload all ($count)',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  height: 38,
                                  child: OutlinedButton.icon(
                                    onPressed: _freeingSpace
                                        ? null
                                        : _freeUploadedGallerySpace,
                                    icon: const Icon(
                                      Icons.cleaning_services_outlined,
                                      size: 18,
                                    ),
                                    label: Text(
                                      _freeingSpace
                                          ? 'Cleaning...'
                                          : 'Free space',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),

              const SizedBox(height: 4),

              // ── Manual selection controls (only after a secondary method is used) ──
              if (_selectedFiles.isNotEmpty) ...[
                SwitchListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: const Text(
                    'Enhanced image',
                    style: TextStyle(fontSize: 14),
                  ),
                  value: _isEnhanced,
                  onChanged: _uploading
                      ? null
                      : (value) => _safeSetState(() => _isEnhanced = value),
                ),
                Card(
                  child: ListTile(
                    dense: true,
                    title: Text('${_selectedFiles.length} images selected'),
                    subtitle: Text(
                      _selectedFiles
                          .take(3)
                          .map((file) => file.name)
                          .join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: TextButton(
                      onPressed: _uploading
                          ? null
                          : () => _safeSetState(() {
                              _selectedFiles.clear();
                              _uploadStatus = null;
                            }),
                      child: const Text('Clear'),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(_selectedFiles.first.path),
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ],

              if (_uploadStatus != null && _selectedFiles.isNotEmpty) ...[
                const SizedBox(height: 6),
                _statusText(_uploadStatus!),
              ],

              const SizedBox(height: 14),

              // ── Manual upload button appears only after files are selected ──
              if (_selectedFiles.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: activeEvent == null || _uploading
                        ? null
                        : () => _submit(activeEvent),
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: _uploading
                        ? Text('Uploading ${_selectedFiles.length}...')
                        : const Text('Upload selected photos'),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _prepareGuestFaceDelivery(EventSummary event) async {
    if (!RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(event.id.trim())) {
      AppToast.error('This event has an invalid id. Refresh the workspace.');
      return false;
    }

    try {
      await ensureGuestFaceDeliveryEnabled(event.id);
      return true;
    } on DioException catch (error) {
      final responseData = error.response?.data;
      final message = responseData is Map
          ? responseData['message']?.toString()
          : null;
      AppToast.error(message ?? 'Could not prepare guest face delivery');
      return false;
    } catch (_) {
      AppToast.error('Could not prepare guest face delivery');
      return false;
    }
  }

  Future<void> _showGuestQr(EventSummary event) async {
    if (!mounted || _disposed || _guestQrPreparing) return;
    _guestQrPreparing = true;
    try {
      final ready = await runGuestQrPreparation(
        context: context,
        prepare: () => _prepareGuestFaceDelivery(event),
      );
      if (ready && mounted && !_disposed) {
        await _showPreparedGuestQr(event);
      }
    } catch (_) {
      if (mounted && !_disposed) {
        AppToast.error('Could not open the guest QR. Please try again.');
      }
    } finally {
      _guestQrPreparing = false;
    }
  }

  Future<void> _showPreparedGuestQr(EventSummary event) async {
    final payload = GuestQrPayload.encode(event.id);
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Guest face-delivery QR'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: Colors.white),
              child: Padding(
                padding: EdgeInsets.all(12),
                child: IntrinsicQrImage(
                  data: payload,
                  size: 230,
                  errorCorrectionLevel: QrErrorCorrectLevel.Q,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Scan in AirPix. Guests take 2-5 selfies, then receive their matching photos.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: payload));
              AppToast.success('Guest QR link copied');
            },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copy'),
          ),
          TextButton.icon(
            onPressed: () =>
                SharePlus.instance.share(ShareParams(text: payload)),
            icon: const Icon(Icons.share_outlined),
            label: const Text('Share'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  /// A black/locked camera display is the highest-priority failure.
  /// Release our exact PTP owner before giving settings advice; do not
  /// leave the shooting body held by a stalled photo receiver.
  Future<void> _restoreUnusableCameraAndShowSetup() async {
    if (_liveCamera != null || _usbStartRequested) {
      await _stopOtgAutoImport();
    }
    if (mounted) await _showLiveCameraSetup();
  }

  Future<void> _showTransferSessionPage(EventSummary event) async {
    if (!mounted || _connectionPageOpen) return;
    _connectionPageOpen = true;
    _refreshSessionStatus();
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => CameraTransferPage(
            eventId: event.id,
            eventTitle: event.title,
            session: _sessionStatus,
            startedAt: _receivingEventId == event.id ? _sessionStartedAt : null,
            onStop: _stopReceivingSession,
            onShareGuestQr: () => _showGuestQr(event),
            onCameraSetupHelp: _sessionKind == 'usb'
                ? () => unawaited(_restoreUnusableCameraAndShowSetup())
                : null,
            onViewHistory: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => TransferListPage(
                  eventId: event.id,
                  eventTitle: event.title,
                  filter: TransferListFilter.all,
                ),
              ),
            ),
            connectionDetailsBuilder: _buildSessionConnectionDetails,
          ),
        ),
      );
    } finally {
      _connectionPageOpen = false;
    }
  }

  bool get _liveConnectionActive =>
      _otgImporting || _wirelessImporting || _galleryImporting;

  Future<void> _showUsbCameraOptions() async {
    if (!mounted) return;
    var selectedMode = _usbUploadMode;
    var photoCatalog = _usbPhotoCatalogReader;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'USB / OTG options',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text(
                  'New shots only is the default. Change this only when you need older camera photos too.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 16),
                UsbCameraUploadModeSelector(
                  value: selectedMode,
                  sessionLocked: _usbSessionLocked,
                  onChanged: (mode) {
                    if (_usbSessionLocked || mode == selectedMode) return;
                    setSheetState(() => selectedMode = mode);
                    _changeUsbUploadMode(mode);
                  },
                ),
                if (Platform.isIOS || Platform.isAndroid)
                  UsbCameraReaderSelector(
                    value: photoCatalog,
                    onChanged: _usbSessionLocked
                        ? null
                        : (value) {
                            if (_usbSessionLocked) return;
                            setSheetState(() => photoCatalog = value);
                            _safeSetState(() => _usbPhotoCatalogReader = value);
                          },
                  ),
                if (_usbSessionLocked) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Stop the current USB session before changing the transfer mode.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                const Divider(height: 1),
                if (_pcSimulatorEnabled &&
                    (Platform.isAndroid || Platform.isIOS))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.science_outlined),
                    title: const Text('PC camera simulator (test only)'),
                    subtitle: Text(
                      Platform.isAndroid
                          ? 'Simulate photos over the Android USB/ADB test bridge.'
                          : 'Simulate photos over local Wi-Fi or USB hotspot networking. Not a real USB/PTP camera.',
                    ),
                    onTap: _otgBusy || _uploading || _usbStartRequested
                        ? null
                        : () {
                            Navigator.pop(sheetContext);
                            unawaited(_startPcUsbTestBridge());
                          },
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.fact_check_outlined),
                  title: const Text('Test USB connection'),
                  subtitle: const Text(
                    'Check whether AirPix can see and communicate with the camera.',
                  ),
                  onTap: _otgBusy || _uploading || _usbStartRequested
                      ? null
                      : () {
                          Navigator.pop(sheetContext);
                          unawaited(_diagnoseUsbCamera());
                        },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.help_outline_rounded),
                  title: const Text('Camera setup help'),
                  subtitle: const Text(
                    'USB tether mode, black-screen and shutter guidance.',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    unawaited(_showLiveCameraSetup());
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Import camera photos once'),
                  subtitle: const Text(
                    'Manually choose stored photos instead of starting a live session.',
                  ),
                  onTap: _uploading || _otgBusy || _usbStartRequested
                      ? null
                      : () {
                          Navigator.pop(sheetContext);
                          unawaited(_pickOtgFiles());
                        },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.sd_storage_outlined),
                  title: const Text('Browse Files / SD card'),
                  subtitle: const Text(
                    'Choose stored photos with the system Files picker.',
                  ),
                  onTap: _uploading
                      ? null
                      : () {
                          Navigator.pop(sheetContext);
                          unawaited(_pickOtgFilesFromFiles());
                        },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showWirelessCameraOptions() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Wireless options',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Use camera FTP auto-send or Canon CCAPI. Keep both devices on the same Wi-Fi and AirPix open. '
                'On iPhone, check Settings > Privacy & Security > Local Network > AirPix. '
                'Bluetooth pairing alone cannot deliver full photos. Location access is not needed for these connections.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.mutedForeground,
                ),
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.wifi_outlined),
                title: const Text('Open Wi-Fi settings'),
                subtitle: const Text(
                  'Connect this phone to the camera network.',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(_openWifiSettings());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cameraConnectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String detail,
    required bool active,
    required bool busy,
    required String? status,
    required String startLabel,
    required String stopLabel,
    required VoidCallback? onPressed,
    required VoidCallback onMenu,
    String? badge,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final stateText = active
        ? 'Connected'
        : busy
        ? 'Connecting…'
        : detail;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AppIconTile(
                  icon: icon,
                  size: 44,
                  iconSize: 22,
                  background: active
                      ? colorScheme.primaryContainer
                      : AppColors.cream,
                  foreground: active
                      ? colorScheme.onPrimaryContainer
                      : AppColors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.cream,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                badge,
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        stateText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: active
                              ? colorScheme.primary
                              : AppColors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '$title options',
                  onPressed: onMenu,
                  icon: const Icon(Icons.more_vert_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: AppColors.mutedForeground,
              ),
            ),
            if (status != null && status.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                status,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: active
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy && !active ? null : onPressed,
                icon: Icon(
                  active ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  size: 18,
                ),
                label: Text(
                  active
                      ? stopLabel
                      : busy
                      ? 'Connecting…'
                      : startLabel,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _uploadSourceTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return ListTile(
      enabled: onTap != null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: AppIconTile(
        icon: icon,
        size: 42,
        iconSize: 20,
        background: onTap == null ? AppColors.muted : AppColors.cream,
        foreground: onTap == null
            ? AppColors.mutedForeground
            : AppColors.primary,
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.foreground,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          subtitle,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.mutedForeground,
          ),
        ),
      ),
      trailing: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.muted,
          borderRadius: BorderRadius.circular(11),
        ),
        child: const Icon(
          Icons.chevron_right_rounded,
          size: 19,
          color: AppColors.mutedForeground,
        ),
      ),
      onTap: onTap,
    );
  }

  Widget _statusText(String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
      ),
    );
  }
}
