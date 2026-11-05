import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:auto_route/auto_route.dart';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobileapp/core/guest/guest_qr_payload.dart';
import 'package:mobileapp/core/guest/guest_qr_preparation.dart';
import 'package:mobileapp/core/guest/guest_face_delivery.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/platform/canon_ccapi_camera.dart';
import 'package:mobileapp/core/platform/camera_ftp_receiver.dart';
import 'package:mobileapp/core/platform/transfer_screen_awake.dart';
import 'package:mobileapp/core/platform/device_settings.dart';
import 'package:mobileapp/core/platform/gallery_auto_import.dart';
import 'package:mobileapp/core/platform/live_camera_capture.dart';
import 'package:mobileapp/core/platform/network_camera_discovery.dart';
import 'package:mobileapp/core/platform/otg_file_picker.dart';
import 'package:mobileapp/core/platform/usb_camera_guidance.dart';
import 'package:mobileapp/core/platform/ptp_ip_camera.dart';
import 'package:mobileapp/core/platform/upnp_camera_media.dart';
import 'package:mobileapp/core/router/app_router.dart';
import 'package:mobileapp/core/storage/active_event_storage.dart';
import 'package:mobileapp/core/storage/camera_ftp_profile_storage.dart';
import 'package:mobileapp/core/storage/usb_camera_upload_mode_storage.dart';
import 'package:mobileapp/core/storage/user_storage.dart';
import 'package:mobileapp/core/storage/uploaded_gallery_storage.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/core/upload/upload_queue_service.dart';
import 'package:mobileapp/core/upload/upload_queue_storage.dart';
import 'package:mobileapp/models/album_model.dart';
import 'package:mobileapp/models/event_invitation_model.dart';
import 'package:mobileapp/pages/upload/camera_transfer_page.dart';
import 'package:mobileapp/pages/upload/transfer_list_page.dart';
import 'package:mobileapp/pages/upload/usb_camera_upload_mode_selector.dart';
import 'package:mobileapp/utilities/app_toast.dart';
import 'package:mobileapp/widgets/app_ui.dart';
import 'package:mobileapp/widgets/intrinsic_qr_image.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

class _CameraProbe {
  const _CameraProbe({
    required this.sourceUrl,
    required this.imageUrl,
    required this.signature,
    required this.usesListing,
    this.initialKeys = const <String>{},
  });

  final String sourceUrl;
  final String imageUrl;
  final String signature;
  final bool usesListing;
  final Set<String> initialKeys;
}

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

class _PtpProbe {
  const _PtpProbe(this.camera);

  final PtpIpCamera camera;
}

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
  });

  final EventSummary event;
  final LiveCameraUploadMode uploadMode;
  final bool isEnhanced;
  final String? albumId;
}

enum _UploadMode { quick, auto }

@RoutePage()
class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> with WidgetsBindingObserver {
  final _picker = ImagePicker();
  _UploadMode _uploadMode = _UploadMode.quick;
  final Dio _cameraDio = Dio();
  final List<_SelectedUploadFile> _selectedFiles = [];
  Timer? _wirelessTimer;
  Timer? _galleryTimer;
  LiveCameraCapture? _liveCamera;
  String? _liveCameraEventId;
  Future<void>? _usbShutdown;
  String? _usbReleaseIssue;
  bool _otgStarting = false;
  bool _usbStartRequested = false;
  bool _usbModeSaving = false;
  bool _guestQrPreparing = false;
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
  final Set<String> _processedWirelessIds = {};
  String? _galleryStatus;
  String? _otgStatus;
  String? _uploadStatus;
  String? _wirelessStatus;
  String? _otgSourceName;
  String? _wirelessSourceUrl;
  String? _wirelessImageUrl;
  String? _lastWirelessSignature;
  PtpIpCamera? _ptpIpCamera;
  CanonCcapiCamera? _canonCcapiCamera;
  UpnpCameraMedia? _upnpCameraMedia;
  bool _wirelessUsesListing = false;
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
      mounted && !_disposed && generation == _wirelessGeneration;

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
    _cameraDio.close(force: true);
    final ptpCamera = _ptpIpCamera;
    _ptpIpCamera = null;
    if (ptpCamera != null) {
      unawaited(ptpCamera.close());
    }
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
        'Checking for a connected USB camera…',
        OtgFilePicker.cameraConnectionDiagnostics(),
      );
      if (!mounted || diagnostic == null) return;
      final guidance = UsbCameraGuidance.forStatus(diagnostic.status);

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('USB camera connection'),
          scrollable: true,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                guidance.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(diagnostic.message),
              const SizedBox(height: 12),
              const Text(
                'Connection checklist',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              _usbDiagnosticStep(
                '1. USB accessory',
                diagnostic.usbEnumerationAvailable
                    ? (diagnostic.usbHostSupported == false
                          ? 'USB host / OTG not supported by this phone'
                          : diagnostic.usbDevices.isEmpty
                          ? 'No attached USB peripheral enumerated'
                          : '${diagnostic.usbDevices.length} USB device(s) detected')
                    : 'iOS cannot inspect the adapter separately',
              ),
              _usbDiagnosticStep(
                '2. Camera discovered',
                diagnostic.cameras.isEmpty
                    ? 'No compatible wired camera found'
                    : '${diagnostic.cameras.length} camera(s) found',
              ),
              _usbDiagnosticStep(
                '3. Camera session',
                diagnostic.cameras.any((camera) => camera.sessionOpen)
                    ? 'Existing session is open'
                    : diagnostic.discoveryOnly
                    ? 'Not opened by this check'
                    : 'Not open',
              ),
              _usbDiagnosticStep(
                '4. Camera photos',
                diagnostic.discoveryOnly
                    ? 'Not read by this check'
                    : diagnostic.totalImages > 0
                    ? '${diagnostic.totalImages} currently listed'
                    : diagnostic.status == 'live-ready'
                    ? 'Waiting for new photos'
                    : diagnostic.status == 'catalog-loading'
                    ? 'Catalog still loading'
                    : 'No compatible photos listed',
              ),
              _usbDiagnosticStep(
                '5. Physical shutter',
                diagnostic.cameras.any(
                      (camera) => camera.physicalShutter == 'supported',
                    )
                    ? 'Shooting while connected is advertised; verify with a test shot'
                    : 'Not confirmed. File import does not prove live shooting support',
              ),
              if (diagnostic.connectionNote.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  diagnostic.connectionNote,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
              if (Platform.isIOS) ...[
                const SizedBox(height: 8),
                Text('Photo access: ${diagnostic.contentsAuthorization}'),
                Text(
                  'Camera control access: ${diagnostic.controlAuthorization}',
                ),
              ],
              if (diagnostic.usbDevices.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Attached USB devices',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                for (final device in diagnostic.usbDevices) ...[
                  const SizedBox(height: 7),
                  Text(
                    device.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${device.category} · ${device.usbIdentifier}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    device.cameraCandidate
                        ? (device.hasPermission
                              ? 'Possible camera; USB permission granted'
                              : 'Possible camera; USB permission needed')
                        : 'Not identified as a PTP camera',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (Platform.isAndroid &&
                      !device.cameraCandidate &&
                      device.category.startsWith('Other USB'))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.usb_outlined),
                        label: const Text('Try as PTP camera'),
                        onPressed: () async {
                          try {
                            await OtgFilePicker.useUsbDeviceAsCamera(device.id);
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                            if (mounted) unawaited(_pickOtgFiles());
                          } on PlatformException catch (error) {
                            AppToast.error(
                              UsbCameraGuidance.forStatus(
                                error.code,
                                message: error.message,
                              ).details,
                            );
                          }
                        },
                      ),
                    ),
                ],
              ],
              const SizedBox(height: 12),
              Text('What to do: ${guidance.nextSteps}'),
              const SizedBox(height: 10),
              for (final camera in diagnostic.cameras) ...[
                const Divider(),
                Text(
                  camera.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  'USB session: ${camera.sessionOpen ? "Open" : "Not open"}',
                ),
                Text(
                  'Photo index: ${!camera.sessionOpen
                      ? "Not read by this check"
                      : camera.catalogReady
                      ? "Ready"
                      : "${camera.catalogProgress}% loaded"}',
                ),
                if (camera.sessionOpen)
                  Text('Supported images listed: ${camera.imageCount}'),
                Text(
                  'Live session: ${camera.liveSessionActive ? "Active" : "Stopped"}',
                ),
                if (camera.transportType.isNotEmpty)
                  Text('Transport: ${camera.transportType}'),
                if (Platform.isIOS)
                  Text(
                    camera.wiredConfirmed
                        ? 'Wired USB transport identified'
                        : 'USB transport not independently confirmed',
                  ),
                if (camera.sessionError.isNotEmpty)
                  Text(
                    'Session error: ${camera.sessionError}',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
              ],
              if (diagnostic.cameras.isEmpty) ...[
                const Text(
                  'Use a USB data cable and the camera model’s supported tethered-shooting mode for Live shooting. PTP / Photo Transfer may be limited to importing stored photos on some cameras.',
                ),
              ],
              const SizedBox(height: 8),
              const Text(
                'Phone gallery photos are not counted. This only checks the wired camera.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: diagnostic.toSupportReport()),
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                AppToast.success('Camera diagnostics copied');
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copy report'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } on MissingPluginException {
      AppToast.error('USB diagnostics require a freshly rebuilt app.');
    } on PlatformException catch (error) {
      AppToast.error(error.message ?? 'Unable to check USB camera connection.');
    } catch (error) {
      debugPrint('USB diagnostic failed: $error');
      AppToast.error('Could not check USB camera connection.');
    }
  }

  Widget _usbDiagnosticStep(String title, String details) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 155,
          child: Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: Text(details, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );

  Future<void> _showLiveCameraSetup() => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Camera screen black or shutter locked?'),
      scrollable: true,
      content: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'A USB file-transfer connection can put a camera into playback '
            'or transfer-only mode. Reading the card does not mean the camera '
            'can keep taking photos.',
          ),
          SizedBox(height: 14),
          Text('1. Stop the live session and disconnect the USB cable.'),
          SizedBox(height: 8),
          Text(
            '2. Check your camera manual for shooting while connected. '
            'The option may be called PC Remote, Remote Shooting or USB '
            'Tether Shooting. Do not choose Mass Storage, Card Reader or '
            'USB Streaming for this photo workflow.',
          ),
          SizedBox(height: 8),
          Text(
            '3. Reconnect, start Live shooting, wait for the photo index to '
            'finish, then press the shutter on the camera. Keep this app '
            'open. A successful new shot will appear in the transfer list.',
          ),
          SizedBox(height: 14),
          Text(
            'AirPix sets up supported Canon EOS, Nikon and Sony shooting '
            'connections automatically. On Sony, choose Camera priority and '
            'PC + Camera for still-image storage. If the shutter stays locked, use Test '
            'wired camera connection and copy the report with your exact '
            'camera model, phone model and selected USB mode.',
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Got it'),
        ),
      ],
    ),
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
    if (photos.isGranted || photos.isLimited) return true;

    final storage = await Permission.storage.request();
    return storage.isGranted;
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

  String _signatureForBytes(Uint8List bytes) {
    var hash = 2166136261;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * 16777619) & 0xffffffff;
    }
    return '${bytes.length}:$hash';
  }

  String _filenameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final segment = uri?.pathSegments.isNotEmpty ?? false
        ? uri!.pathSegments.last
        : '';
    if (segment.contains('.')) {
      return segment;
    }
    return 'wireless-${DateTime.now().millisecondsSinceEpoch}.jpg';
  }

  bool _looksLikeImage(Uint8List bytes) {
    if (bytes.length < 4) return false;
    final isJpeg = bytes[0] == 0xff && bytes[1] == 0xd8;
    final isPng = bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4e;
    final isGif = bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46;
    final isWebp =
        bytes.length > 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
    return isJpeg || isPng || isGif || isWebp;
  }

  List<String> _wirelessCameraHosts() => const [
    'http://192.168.0.1',
    'http://192.168.0.10',
    'http://192.168.0.100',
    'http://192.168.1.1',
    'http://192.168.1.2',
    'http://192.168.1.10',
    'http://192.168.1.100',
    'http://192.168.1.254',
    'http://192.168.2.1',
    'http://192.168.3.1',
    'http://192.168.4.1',
    'http://192.168.5.1',
    'http://192.168.8.1',
    'http://192.168.42.1',
    'http://192.168.49.1',
    'http://192.168.100.1',
    'http://192.168.122.1',
    'http://192.168.137.1',
    'http://10.0.0.1',
    'http://10.0.0.10',
    'http://10.0.1.1',
    'http://172.16.0.1',
    'http://172.20.10.1',
  ];

  List<String> _wirelessCameraCandidates() {
    final hosts = _wirelessCameraHosts();
    const paths = [
      '/',
      '/index.html',
      '/DCIM/',
      '/DCIM/100CANON/',
      '/DCIM/101CANON/',
      '/DCIM/100EOS/',
      '/DCIM/101EOS/',
      '/DCIM/100NIKON/',
      '/DCIM/101NIKON/',
      '/DCIM/100MSDCF/',
      '/DCIM/101MSDCF/',
      '/DCIM/100_FUJI/',
      '/DCIM/101_FUJI/',
      '/DCIM/100_PANA/',
      '/DCIM/101_PANA/',
      '/DCIM/100PENTX/',
      '/DCIM/101PENTX/',
      '/DCIM/100OLYMP/',
      '/DCIM/101OLYMP/',
      '/DCIM/100RICOH/',
      '/DCIM/101RICOH/',
      '/DCIM/100LEICA/',
      '/DCIM/101LEICA/',
      '/DCIM/100HASBL/',
      '/DCIM/101HASBL/',
      '/DCIM/100GOPRO/',
      '/DCIM/101GOPRO/',
      '/DCIM/100MEDIA/',
      '/DCIM/101MEDIA/',
      '/DCIM/100APPLE/',
      '/DCIM/100ANDRO/',
      '/sd/DCIM/',
      '/latest.jpg',
      '/latest.jpeg',
      '/image.jpg',
      '/photo.jpg',
      '/capture',
      '/snapshot',
      '/shot.jpg',
      '/view.jpg',
      '/live.jpg',
      '/live',
      '/api/v1/photos/latest',
    ];

    return [
      for (final host in hosts)
        for (final path in paths) '$host$path',
    ];
  }

  List<String> _candidateUrlsForDiscovery(DiscoveredCameraService service) {
    final parsed = Uri.tryParse(service.url);
    if (parsed == null) return [service.url];

    final base = parsed.removeFragment().replace(query: '').toString();
    final origin = parsed
        .replace(path: '/', query: '', fragment: '')
        .toString();
    final urls = <String>{base, origin};

    const extraPaths = [
      '/latest.jpg',
      '/latest.jpeg',
      '/image.jpg',
      '/photo.jpg',
      '/capture',
      '/snapshot',
      '/shot.jpg',
      '/DCIM/',
    ];

    for (final path in extraPaths) {
      urls.add(parsed.replace(path: path, query: '', fragment: '').toString());
      urls.add(Uri.parse(origin).resolve(path).toString());
    }

    return urls.toList(growable: false);
  }

  bool _looksLikeCameraListing(
    String body,
    String sourceUrl,
    List<String> imageLinks,
  ) {
    final haystack = '${sourceUrl.toLowerCase()}\n${body.toLowerCase()}';
    const hints = [
      'camera',
      'dcim',
      'canon',
      'eos',
      'nikon',
      'sony',
      'alpha',
      'fujifilm',
      'fuji',
      'lumix',
      'panasonic',
      'olympus',
      'om system',
      'pentax',
      'ricoh',
      'leica',
      'hasselblad',
      'ptp',
      'image capture',
    ];
    if (hints.any(haystack.contains)) return true;

    final cameraName = RegExp(
      r'(?:^|[/_-])(?:img|dsc|dscn|dscf|pict|_mg|pxl)[_-]?\d+',
      caseSensitive: false,
    );
    return imageLinks.any((url) {
      final path = Uri.tryParse(url)?.path ?? url;
      return cameraName.hasMatch(path);
    });
  }

  List<String> _extractImageLinks(String body, String sourceUrl) {
    final matches = RegExp(
      r'''(?:href|src)\s*=\s*["']([^"']+\.(?:jpe?g|png|gif|webp|heic))(?:\?[^"']*)?["']''',
      caseSensitive: false,
    ).allMatches(body);

    final results = <String>[];
    for (final match in matches) {
      final raw = match.group(1);
      if (raw == null || raw.isEmpty) continue;
      final resolved = Uri.parse(sourceUrl).resolve(raw).toString();
      if (!results.contains(resolved)) {
        results.add(resolved);
      }
    }
    return results;
  }

  Future<Uint8List?> _downloadImageBytes(String url) async {
    final response = await _cameraDio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 3),
        sendTimeout: const Duration(seconds: 3),
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    final contentType = response.headers.value(Headers.contentTypeHeader) ?? '';
    final bytes = Uint8List.fromList(response.data ?? []);
    final returnsImage =
        contentType.toLowerCase().startsWith('image/') ||
        (contentType.isEmpty && _looksLikeImage(bytes));
    if (bytes.isEmpty || !returnsImage) return null;
    return bytes;
  }

  Future<_CameraProbe?> _probeCameraUrl(String url) async {
    try {
      final response = await _cameraDio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 2),
          sendTimeout: const Duration(seconds: 2),
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final contentType =
          response.headers.value(Headers.contentTypeHeader) ?? '';
      final bytes = Uint8List.fromList(response.data ?? []);
      final returnsImage =
          contentType.toLowerCase().startsWith('image/') ||
          (contentType.isEmpty && _looksLikeImage(bytes));

      if (bytes.isNotEmpty && returnsImage) {
        return _CameraProbe(
          sourceUrl: url,
          imageUrl: url,
          signature: _signatureForBytes(bytes),
          usesListing: false,
        );
      }

      final body = utf8.decode(bytes, allowMalformed: true);
      if (body.isEmpty) return null;
      final imageLinks = _extractImageLinks(body, url);
      if (imageLinks.isEmpty ||
          !_looksLikeCameraListing(body, url, imageLinks)) {
        return null;
      }

      final latestImageUrl = imageLinks.last;
      final imageBytes = await _downloadImageBytes(latestImageUrl);
      if (imageBytes == null) return null;

      return _CameraProbe(
        sourceUrl: url,
        imageUrl: latestImageUrl,
        signature: _signatureForBytes(imageBytes),
        usesListing: true,
        initialKeys: imageLinks.length <= 500
            ? imageLinks.toSet()
            : imageLinks.sublist(imageLinks.length - 500).toSet(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> _localPtpIpHosts() async {
    final hosts = <String>{};
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final parts = address.address.split('.');
          if (parts.length != 4) continue;
          final octets = parts.map(int.tryParse).toList();
          if (octets.any((value) => value == null)) continue;
          final a = octets[0]!;
          final b = octets[1]!;
          final isPrivate =
              a == 10 ||
              (a == 172 && b >= 16 && b <= 31) ||
              (a == 192 && b == 168);
          if (!isPrivate) continue;
          final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
          for (var host = 1; host <= 254; host++) {
            if (host.toString() == parts[3]) continue;
            hosts.add('$prefix.$host');
          }
        }
      }
    } catch (_) {}
    return hosts.toList(growable: false);
  }

  Future<List<Uri>> _localHttpCameraOrigins() async {
    final hosts = await _localPtpIpHosts();
    if (hosts.isEmpty) return const [];
    final limitedHosts = hosts.take(508).toList(growable: false);
    final origins = <Uri>{};
    var cursor = 0;

    Future<void> worker() async {
      while (cursor < limitedHosts.length) {
        final host = limitedHosts[cursor++];
        for (final port in const [80, 8080]) {
          Socket? socket;
          try {
            socket = await Socket.connect(
              host,
              port,
              timeout: const Duration(milliseconds: 180),
            );
            origins.add(Uri(scheme: 'http', host: host, port: port, path: '/'));
          } catch (_) {
          } finally {
            socket?.destroy();
          }
        }
      }
    }

    final workerCount = limitedHosts.length < 48 ? limitedHosts.length : 48;
    await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);
    return origins.toList(growable: false);
  }

  Future<_PtpProbe?> _discoverPtpIpCamera(
    List<DiscoveredCameraService> discovered,
  ) async {
    final primaryTargets = <MapEntry<String, int>>[];
    final seen = <String>{};

    void addPrimary(String host, int port) {
      if (host.isEmpty) return;
      final key = '$host|$port';
      if (seen.add(key)) primaryTargets.add(MapEntry(host, port));
    }

    for (final service in discovered) {
      final uri = Uri.tryParse(service.url);
      if (uri == null || uri.host.isEmpty) continue;
      final description = service.description?.toLowerCase() ?? '';
      final ptpPort = description.contains('ptp')
          ? uri.port
          : PtpIpCamera.defaultPort;
      addPrimary(uri.host, ptpPort);
      if (ptpPort != PtpIpCamera.defaultPort) {
        addPrimary(uri.host, PtpIpCamera.defaultPort);
      }
    }

    for (final url in _wirelessCameraHosts()) {
      final uri = Uri.tryParse(url);
      if (uri != null && uri.host.isNotEmpty) {
        addPrimary(uri.host, PtpIpCamera.defaultPort);
      }
    }

    Future<_PtpProbe?> probeTargets(
      List<MapEntry<String, int>> targets, {
      required int batchSize,
      required Duration connectTimeout,
    }) async {
      for (var start = 0; start < targets.length; start += batchSize) {
        final end = (start + batchSize < targets.length)
            ? start + batchSize
            : targets.length;
        final batch = targets.sublist(start, end);
        final attempts = await Future.wait(
          batch.map((target) async {
            final camera = await PtpIpCamera.connect(
              target.key,
              port: target.value,
              timeout: connectTimeout,
            );
            if (camera == null) return null;
            try {
              await camera.establishLiveBaseline();
              return _PtpProbe(camera);
            } catch (_) {
              await camera.close();
              return null;
            }
          }),
        );

        _PtpProbe? winner;
        for (final attempt in attempts) {
          if (attempt != null) {
            winner = attempt;
            break;
          }
        }
        if (winner != null) {
          for (final attempt in attempts.whereType<_PtpProbe>()) {
            if (!identical(attempt.camera, winner.camera)) {
              unawaited(attempt.camera.close());
            }
          }
          debugPrint(
            '[Camera] PTP/IP connected ${winner.camera.host}:${winner.camera.port}',
          );
          return winner;
        }
      }
      return null;
    }

    final primary = await probeTargets(
      primaryTargets,
      batchSize: 8,
      connectTimeout: const Duration(milliseconds: 800),
    );
    if (primary != null) return primary;

    final localHosts = await _localPtpIpHosts();
    final subnetTargets = <MapEntry<String, int>>[];
    for (final host in localHosts) {
      final key = '$host|${PtpIpCamera.defaultPort}';
      if (seen.add(key)) {
        subnetTargets.add(MapEntry(host, PtpIpCamera.defaultPort));
      }
    }
    if (subnetTargets.isNotEmpty) {
      debugPrint(
        '[Camera] Fast PTP/IP subnet scan: ${subnetTargets.length} hosts',
      );
    }
    return probeTargets(
      subnetTargets,
      batchSize: 32,
      connectTimeout: const Duration(milliseconds: 300),
    );
  }

  Future<_CameraProbe?> _discoverWirelessCamera(int generation) async {
    final oldPtpCamera = _ptpIpCamera;
    _ptpIpCamera = null;
    final oldCanonCamera = _canonCcapiCamera;
    _canonCcapiCamera = null;
    if (oldCanonCamera != null) unawaited(oldCanonCamera.close());
    _upnpCameraMedia = null;
    if (oldPtpCamera != null) {
      unawaited(oldPtpCamera.close());
    }

    final discovered = await NetworkCameraDiscovery.discover(
      timeout: const Duration(seconds: 3),
    );
    if (!_wirelessActive(generation)) return null;

    final ptpProbe = await _discoverPtpIpCamera(discovered);
    if (!_wirelessActive(generation)) {
      if (ptpProbe != null) unawaited(ptpProbe.camera.close());
      return null;
    }
    if (ptpProbe != null) {
      _ptpIpCamera = ptpProbe.camera;
      final source = 'ptpip://${ptpProbe.camera.host}:${ptpProbe.camera.port}/';
      return _CameraProbe(
        sourceUrl: source,
        imageUrl: source,
        signature: 'ptpip-ready',
        usesListing: false,
      );
    }

    final localHttpOrigins = await _localHttpCameraOrigins();
    if (!_wirelessActive(generation)) return null;
    if (localHttpOrigins.isNotEmpty) {
      debugPrint(
        '[Camera] Reachable local HTTP camera candidates: ${localHttpOrigins.length}',
      );
    }

    final canonOrigins = <Uri>{...localHttpOrigins};
    for (final service in discovered) {
      final uri = Uri.tryParse(service.url);
      if (uri != null) canonOrigins.add(uri);
    }
    for (final host in _wirelessCameraHosts()) {
      final uri = Uri.tryParse(host);
      if (uri != null) canonOrigins.add(uri);
    }
    final canon = await CanonCcapiCamera.discover(
      canonOrigins,
      timeout: const Duration(milliseconds: 800),
    );
    if (!_wirelessActive(generation)) {
      await canon?.close();
      return null;
    }
    if (canon != null) {
      _canonCcapiCamera = canon;
      return _CameraProbe(
        sourceUrl: canon.sourceUrl,
        imageUrl: canon.sourceUrl,
        signature: 'canon-ccapi-ready',
        usesListing: false,
      );
    }

    final upnpLocations = discovered
        .where((service) => service.source == 'ssdp')
        .map((service) => Uri.tryParse(service.url))
        .whereType<Uri>();
    final upnp = await UpnpCameraMedia.discover(
      upnpLocations,
      timeout: const Duration(milliseconds: 900),
    );
    if (!_wirelessActive(generation)) return null;
    if (upnp != null) {
      final images = await upnp
          .recentImages(limit: 50)
          .timeout(const Duration(seconds: 8), onTimeout: () => const []);
      if (!_wirelessActive(generation)) return null;
      _upnpCameraMedia = upnp;
      return _CameraProbe(
        sourceUrl: upnp.sourceUrl,
        imageUrl: upnp.sourceUrl,
        signature: images.isEmpty ? 'upnp-ready' : images.first.fingerprint,
        usesListing: false,
        initialKeys: {for (final image in images) image.fingerprint},
      );
    }

    final candidates = <String>{
      for (final service in discovered) ..._candidateUrlsForDiscovery(service),
      for (final origin in localHttpOrigins)
        ..._candidateUrlsForDiscovery(
          DiscoveredCameraService(url: origin.toString(), source: 'subnet'),
        ),
      ..._wirelessCameraCandidates(),
    }.toList(growable: false);
    if (candidates.isEmpty) return null;
    final completer = Completer<_CameraProbe?>();
    var cursor = 0;
    var workersLeft = candidates.length < 16 ? candidates.length : 16;

    Future<void> worker() async {
      while (!completer.isCompleted && cursor < candidates.length) {
        final url = candidates[cursor++];
        final probe = await _probeCameraUrl(url);
        if (probe != null && !completer.isCompleted) {
          completer.complete(probe);
          return;
        }
      }
      workersLeft -= 1;
      if (workersLeft == 0 && !completer.isCompleted) {
        completer.complete(null);
      }
    }

    for (var i = 0; i < workersLeft; i++) {
      unawaited(worker());
    }
    return completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => null,
    );
  }

  Future<void> _findAndStartWirelessImport(
    EventSummary event,
    _WirelessImportMode mode,
  ) async {
    if (_wirelessShutdown != null) await _wirelessShutdown;
    _beginReceivingSession(event, 'wireless');
    final target = _WirelessCaptureTarget(
      event: event,
      mode: mode,
      isEnhanced: _isEnhanced,
      albumId: _selectedAlbumId,
    );
    _wirelessTimer?.cancel();
    final generation = ++_wirelessGeneration;
    _safeSetState(() {
      _wirelessScanning = true;
      _wirelessBusy = false;
      _autoImporting = false;
      _wirelessSourceUrl = null;
      _wirelessImageUrl = null;
      _wirelessUsesListing = false;
      _wirelessStatus = mode == _WirelessImportMode.cameraHotspot
          ? 'Searching for camera hotspot image feed...'
          : 'Searching for shared-network camera...';
    });

    final probe = await _discoverWirelessCamera(generation);
    if (!_wirelessActive(generation)) return;

    if (probe == null) {
      _safeSetState(() {
        _wirelessScanning = false;
        _wirelessStatus = mode == _WirelessImportMode.cameraHotspot
            ? 'No camera hotspot feed found. Connect phone to camera Wi-Fi and try again.'
            : 'No shared-network camera found. Put phone and camera on same network.';
      });
      return;
    }

    _processedWirelessIds
      ..clear()
      ..addAll(probe.initialKeys);
    _safeSetState(() {
      _wirelessScanning = false;
      _wirelessFailureCount = 0;
      _wirelessSourceUrl = probe.sourceUrl;
      _wirelessImageUrl = probe.imageUrl;
      _wirelessUsesListing = probe.usesListing;
      _lastWirelessSignature = probe.signature;
      _autoImporting = true;
      _wirelessStatus = mode == _WirelessImportMode.cameraHotspot
          ? 'Camera hotspot connected. New photos upload to cloud when internet is available.'
          : 'Camera connected. Waiting for new photos...';
    });

    _wirelessAwakeOwner = 'wireless-$_receiverOwnerId-$generation';
    await TransferScreenAwake.setEnabled(_wirelessAwakeOwner!, true);
    if (!_wirelessActive(generation)) return;
    _wirelessTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!_wirelessActive(generation)) {
        timer.cancel();
        return;
      }
      unawaited(_pollWirelessCamera(target, generation));
    });
    unawaited(_showTransferSessionPage(event));
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

  Future<bool> _pollPtpIpCamera(
    _WirelessCaptureTarget target,
    int generation,
  ) async {
    if (!_wirelessActive(generation)) return true;
    final camera = _ptpIpCamera;
    if (camera == null) return false;
    final images = await camera.pendingImages();
    if (!_wirelessActive(generation)) return true;
    if (images.isEmpty) {
      _safeSetState(
        () =>
            _wirelessStatus = 'PTP/IP camera connected. Waiting for a photo...',
      );
      return true;
    }

    // All new objects remain pending until their local queue copy is saved.
    for (final image in images) {
      if (!_wirelessActive(generation)) return true;
      _safeSetState(
        () => _wirelessStatus = 'New camera photo found. Importing...',
      );
      final bytes = await camera.downloadImage(
        image.handle,
        expectedSize: image.size,
      );
      if (bytes == null || bytes.isEmpty) {
        // Keep this handle pending without blocking newer frames in the burst.
        continue;
      }

      final imageKey =
          'ptpip://${camera.host}:${camera.port}/${image.handle}/${Uri.encodeComponent(image.name)}';
      await _saveWirelessBytes(
        target: target,
        generation: generation,
        bytes: bytes,
        filename: image.name,
        imageKey: imageKey,
        signature: image.fingerprint,
        source: 'wireless-ptpip',
        cameraId: 'PTP/IP ${camera.host}:${camera.port}',
      );
      camera.acknowledgeImages([image.handle]);
      if (!_wirelessActive(generation)) return true;
      _lastWirelessSignature = image.fingerprint;
      _wirelessImageUrl = imageKey;
    }
    _wirelessFailureCount = 0;
    return true;
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

    for (final content in fresh) {
      if (!_wirelessActive(generation)) return true;
      _safeSetState(
        () => _wirelessStatus = 'New Canon photo found. Importing...',
      );
      final bytes = await camera.download(content);
      if (bytes == null || bytes.isEmpty) {
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
      _lastWirelessSignature = content.url;
      _wirelessImageUrl = content.url;
    }
    _wirelessFailureCount = 0;
    return true;
  }

  Future<bool> _pollUpnpCamera(
    _WirelessCaptureTarget target,
    int generation,
  ) async {
    if (!_wirelessActive(generation)) return true;
    final camera = _upnpCameraMedia;
    if (camera == null) return false;

    final images = await camera
        .recentImages(limit: 50)
        .timeout(const Duration(seconds: 10));
    if (!_wirelessActive(generation)) return true;
    if (images.isEmpty) {
      _safeSetState(() {
        _wirelessStatus = 'UPnP/DLNA camera connected. Waiting for photos...';
      });
      return true;
    }

    final fresh = images
        .where((image) => !_processedWirelessIds.contains(image.fingerprint))
        .toList(growable: false);
    if (fresh.isEmpty) {
      _safeSetState(
        () => _wirelessStatus = 'Camera connected. No new photo yet.',
      );
      return true;
    }

    for (final image in fresh.reversed) {
      if (!_wirelessActive(generation)) return true;
      _safeSetState(
        () => _wirelessStatus = 'New network camera photo found. Importing...',
      );
      final bytes = await camera
          .download(image)
          .timeout(const Duration(seconds: 60));
      if (bytes == null || bytes.isEmpty) {
        throw const SocketException('UPnP camera returned an empty image');
      }

      await _saveWirelessBytes(
        target: target,
        generation: generation,
        bytes: bytes,
        filename: image.name,
        imageKey: image.url,
        signature: image.fingerprint,
        source: 'wireless-upnp',
        cameraId: camera.sourceUrl,
      );
      if (!_wirelessActive(generation)) return true;
      _processedWirelessIds.add(image.fingerprint);
      _lastWirelessSignature = image.fingerprint;
      _wirelessImageUrl = image.url;
    }
    _wirelessFailureCount = 0;
    return true;
  }

  Future<void> _pollWirelessCamera(
    _WirelessCaptureTarget target,
    int generation,
  ) async {
    if (!_wirelessActive(generation) || _wirelessBusy) return;

    final sourceUrl = _wirelessSourceUrl;
    if (sourceUrl == null) {
      _safeSetState(() => _wirelessStatus = 'Connect a wireless camera first');
      return;
    }

    _safeSetState(() {
      _wirelessBusy = true;
      _wirelessStatus = 'Checking camera...';
    });

    try {
      if (await _pollPtpIpCamera(target, generation)) {
        return;
      }
      if (await _pollCanonCcapiCamera(target, generation)) {
        return;
      }
      if (await _pollUpnpCamera(target, generation)) {
        return;
      }

      var imageUrl = _wirelessImageUrl ?? sourceUrl;

      if (_wirelessUsesListing) {
        final listingResponse = await _cameraDio.get<List<int>>(
          sourceUrl,
          options: Options(responseType: ResponseType.bytes),
        );
        if (!_wirelessActive(generation)) return;
        final listingBytes = Uint8List.fromList(listingResponse.data ?? []);
        final body = utf8.decode(listingBytes, allowMalformed: true);
        final imageLinks = _extractImageLinks(body, sourceUrl);
        if (imageLinks.isEmpty) {
          _safeSetState(
            () => _wirelessStatus = 'Camera folder page has no image links',
          );
          return;
        }

        final freshLinks = imageLinks
            .where((url) => !_processedWirelessIds.contains(url))
            .toList(growable: false);
        if (freshLinks.isEmpty) {
          _safeSetState(() => _wirelessStatus = 'No new image yet');
          return;
        }

        for (final url in freshLinks) {
          if (!_wirelessActive(generation)) return;
          final bytes = await _downloadImageBytes(url);
          if (bytes == null) continue;
          final signature = _signatureForBytes(bytes);
          _safeSetState(
            () => _wirelessStatus = 'New camera image found. Importing...',
          );
          await _saveWirelessBytes(
            target: target,
            generation: generation,
            bytes: bytes,
            filename: _filenameFromUrl(url),
            imageKey: url,
            signature: signature,
            source: 'wireless-http',
            cameraId: sourceUrl,
          );
          if (!_wirelessActive(generation)) return;
          _processedWirelessIds.add(url);
          _wirelessImageUrl = url;
          _lastWirelessSignature = signature;
        }
        _wirelessFailureCount = 0;
        return;
      }

      final bytes = await _downloadImageBytes(imageUrl);
      if (!_wirelessActive(generation)) return;
      if (bytes == null) {
        _safeSetState(
          () => _wirelessStatus = 'Camera source did not return an image',
        );
        return;
      }

      _wirelessImageUrl = imageUrl;
      final signature = _signatureForBytes(bytes);
      if (signature == _lastWirelessSignature) {
        _safeSetState(() => _wirelessStatus = 'No new image yet');
        return;
      }

      _safeSetState(() => _wirelessStatus = 'New image found. Importing...');
      await _saveWirelessBytes(
        target: target,
        generation: generation,
        bytes: bytes,
        filename: _filenameFromUrl(imageUrl),
        imageKey: imageUrl,
        signature: signature,
        source: 'wireless-http',
        cameraId: sourceUrl,
      );
      _lastWirelessSignature = signature;
      _wirelessFailureCount = 0;
    } catch (_) {
      if (!_wirelessActive(generation)) return;
      if (_ptpIpCamera?.isClosed == true ||
          _canonCcapiCamera?.isClosed == true) {
        await _stopWirelessImport();
        _safeSetState(
          () => _wirelessStatus =
              'The camera connection ended. Start a new session before shooting again.',
        );
        return;
      }
      _safeSetState(() {
        _wirelessFailureCount += 1;
        _wirelessStatus = _wirelessFailureCount >= 3
            ? 'Wireless import unstable. Keeping session, retrying automatically.'
            : 'Camera transfer failed. Checking Wi-Fi and retrying...';
      });
    } finally {
      if (_wirelessActive(generation)) {
        _safeSetState(() => _wirelessBusy = false);
      }
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

  Future<void> _changeUsbUploadMode(LiveCameraUploadMode mode) async {
    if (_usbSessionLocked || _usbModeSaving || mode == _usbUploadMode) return;
    final previous = _usbUploadMode;
    _safeSetState(() {
      _usbUploadMode = mode;
      _usbModeSaving = true;
    });
    try {
      await UsbCameraUploadModeStorage.save(mode);
    } catch (_) {
      _safeSetState(() => _usbUploadMode = previous);
      if (mounted && !_disposed) {
        AppToast.error('Could not save the photo selection. Please try again.');
      }
    } finally {
      _safeSetState(() => _usbModeSaving = false);
    }
  }

  Future<void> _startOtgAutoImport(
    _UsbCaptureTarget target, {
    required int generation,
  }) async {
    if (_wirelessShutdown != null) await _wirelessShutdown;
    if (!_usbStartActive(generation, target) || _otgStarting) return;
    final event = target.event;
    _beginReceivingSession(event, 'usb');
    _usbSessionUploadMode = target.uploadMode;
    _wiredPhotoReceived = false;
    _safeSetState(() {
      _otgStarting = true;
      _otgImporting = true;
      _otgBusy = true;
      _otgStatus = 'Connecting for live shooting...';
    });
    final capture = LiveCameraCapture(
      uploadMode: target.uploadMode,
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
            source: 'otg-ptp',
            cameraId: session.name,
            fingerprint: '${event.id}|otg-ptp|${session.cameraId}|${file.id}',
          );
          if (_otgActive(generation)) {
            _safeSetState(() => _wiredPhotoReceived = true);
          }
          try {
            await File(file.path).delete();
          } catch (_) {}
        },
      );
      if (!_otgActive(generation)) {
        await capture.stop(notify: false);
        return;
      }
      _safeSetState(() {
        _usbReleaseIssue = null;
        _otgSourceName = session.name;
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
    final ptpCamera = _ptpIpCamera;
    _ptpIpCamera = null;
    final canonCamera = _canonCcapiCamera;
    _canonCcapiCamera = null;
    _upnpCameraMedia = null;
    _processedWirelessIds.clear();
    _safeSetState(() {
      _autoImporting = false;
      _wirelessScanning = false;
      _wirelessBusy = false;
      _wirelessFailureCount = 0;
      _wirelessSourceUrl = null;
      _wirelessImageUrl = null;
      _wirelessUsesListing = false;
      _lastWirelessSignature = null;
      _wirelessStatus =
          'Receiving stopped. Received photos continue uploading to cloud.';
    });
    try {
      if (ftp != null) await ftp.stop();
      if (ptpCamera != null) await ptpCamera.close();
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
        _usbModeSaving ||
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.add_a_photo_outlined),
                title: const Text('Live shooting with camera FTP'),
                subtitle: const Text(
                  'For cameras with FTP automatic transfer. Each new photo uploads to your event automatically while you keep shooting.',
                ),
                onTap: () => Navigator.of(context).pop(_WirelessImportMode.ftp),
              ),
              ListTile(
                leading: const Icon(Icons.router_outlined),
                title: const Text('Find an existing camera Wi-Fi feed'),
                subtitle: const Text(
                  'Use when phone + camera are on the same router. Uploads can go online immediately.',
                ),
                onTap: () => Navigator.of(
                  context,
                ).pop(_WirelessImportMode.sharedNetwork),
              ),
              ListTile(
                leading: const Icon(Icons.wifi_tethering_outlined),
                title: const Text('Connect to a camera hotspot feed'),
                subtitle: const Text(
                  'A camera hotspot may have no internet. Photos upload automatically whenever internet access is available.',
                ),
                onTap: () => Navigator.of(
                  context,
                ).pop(_WirelessImportMode.cameraHotspot),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || choice == null) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (choice == _WirelessImportMode.ftp) {
      await _startFtpCameraSession(event);
    } else {
      await _findAndStartWirelessImport(event, choice);
    }
  }

  Future<void> _startFtpCameraSession(EventSummary event) async {
    if (_ftpStarting) return;
    if (_wirelessShutdown != null) await _wirelessShutdown;
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
                    '3. Turn on automatic transfer after each shot, then take a photo.',
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
                title: 'Choose upload method',
                actionLabel: _uploadMode == _UploadMode.quick
                    ? 'Manual'
                    : 'Automatic',
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<_UploadMode>(
                  segments: const [
                    ButtonSegment(
                      value: _UploadMode.quick,
                      icon: Icon(Icons.add_photo_alternate_outlined, size: 18),
                      label: Text('Add photos'),
                    ),
                    ButtonSegment(
                      value: _UploadMode.auto,
                      icon: Icon(Icons.sync_rounded, size: 18),
                      label: Text('Auto sync'),
                    ),
                  ],
                  selected: {_uploadMode},
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    side: const WidgetStatePropertyAll(
                      BorderSide(color: AppColors.border),
                    ),
                    textStyle: const WidgetStatePropertyAll(
                      TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                  onSelectionChanged: _uploading
                      ? null
                      : (selection) =>
                            _safeSetState(() => _uploadMode = selection.first),
                ),
              ),
              const SizedBox(height: 12),

              // ── Add photos once ──
              if (_uploadMode == _UploadMode.quick)
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Add photos once',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Choose existing photos now, then tap Upload to active event.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      _uploadSourceTile(
                        icon: Icons.photo_library_outlined,
                        title: 'Phone photos',
                        subtitle: 'Pick existing photos from this phone.',
                        onTap: _uploading ? null : _pickPhoneImages,
                      ),
                      _uploadSourceTile(
                        icon: Icons.camera_alt_outlined,
                        title: 'Take a phone photo',
                        subtitle: 'Open the phone camera and take one photo.',
                        onTap: _uploading ? null : _pickCameraImage,
                      ),
                      _uploadSourceTile(
                        icon: Icons.usb_outlined,
                        title: 'Connected camera (USB / OTG)',
                        subtitle:
                            'Read directly from a compatible USB/PTP camera. Not iPhone photos.',
                        onTap: _uploading || _otgBusy || _usbStartRequested
                            ? null
                            : _pickOtgFiles,
                      ),
                      _uploadSourceTile(
                        icon: Icons.fact_check_outlined,
                        title: 'Test USB camera connection',
                        subtitle:
                            'Check camera name, cable connection, photo index and file count.',
                        onTap: _uploading ? null : _diagnoseUsbCamera,
                      ),
                      _uploadSourceTile(
                        icon: Icons.sd_storage_outlined,
                        title: 'SD card / USB storage (Files)',
                        subtitle:
                            'Choose photos from a connected drive under Locations in Files.',
                        onTap: _uploading ? null : _pickOtgFilesFromFiles,
                      ),
                      if (activeEvent != null)
                        _uploadSourceTile(
                          icon: Icons.image_outlined,
                          title: 'Uploaded photos',
                          subtitle:
                              'View photos already uploaded to this event.',
                          onTap: () => context.router.root.push(
                            const EventImagesRoute(),
                          ),
                        ),
                    ],
                  ),
                ),

              const SizedBox(height: 10),

              // ── Automatic external-camera upload ──
              if (_uploadMode == _UploadMode.auto)
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Camera auto-upload',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Connect the camera, wait for the ready message, then use its shutter. Each new photo starts uploading to your cloud event automatically. Keep AirPix open while shooting.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      _autoUploadTile(
                        icon: Icons.usb_outlined,
                        title: 'Live shooting (USB / OTG)',
                        startLabel: 'Start live shooting',
                        stopLabel: 'Stop live shooting',
                        subtitle:
                            'Automatic photo transfer for compatible Canon EOS, Nikon and Sony cameras. Wait for the ready message, then use the camera shutter.',
                        flowText:
                            _usbUploadMode == LiveCameraUploadMode.newShotsOnly
                            ? 'Camera shutter → automatic cloud upload'
                            : 'Existing photos + camera shutter → automatic cloud upload',
                        configuration: UsbCameraUploadModeSelector(
                          value: _usbUploadMode,
                          sessionLocked: _usbSessionLocked,
                          isSaving: _usbModeSaving,
                          onChanged: (mode) =>
                              unawaited(_changeUsbUploadMode(mode)),
                        ),
                        active: _otgImporting,
                        busy: _otgBusy || _usbStartRequested,
                        status: _otgStatus,
                        onPressed:
                            activeEvent == null || _uploading || _usbModeSaving
                            ? null
                            : () => _toggleOtgAutoUpload(activeEvent),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextButton.icon(
                          onPressed: _showLiveCameraSetup,
                          icon: const Icon(Icons.help_outline, size: 18),
                          label: const Text('Camera screen black?'),
                        ),
                      ),
                      _uploadSourceTile(
                        icon: Icons.fact_check_outlined,
                        title: 'Test wired camera connection',
                        subtitle:
                            'Check the camera session and whether physical-shutter shooting is advertised.',
                        onTap: _otgBusy || _uploading || _usbStartRequested
                            ? null
                            : _diagnoseUsbCamera,
                      ),
                      _autoUploadTile(
                        icon: Icons.wifi_tethering,
                        title: 'Wireless camera',
                        subtitle:
                            'Automatic FTP transfer while you shoot, or an existing camera Wi-Fi feed. Availability depends on the camera.',
                        flowText: 'Camera shutter → automatic cloud upload',
                        active: _wirelessImporting,
                        busy: _wirelessBusy || _wirelessScanning,
                        status: _wirelessStatus,
                        onPressed:
                            activeEvent == null ||
                                _uploading ||
                                _usbStartRequested
                            ? null
                            : () => _toggleWirelessAutoUpload(activeEvent),
                        secondaryAction: _wirelessImporting
                            ? null
                            : _openWifiSettings,
                      ),
                      ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                        title: const Text(
                          'Phone-only auto-upload',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text(
                          'Only for photos saved by the phone itself. OTG and wireless cameras do not use this.',
                          style: TextStyle(fontSize: 11),
                        ),
                        children: [
                          _autoUploadTile(
                            icon: Icons.phone_android_outlined,
                            title: 'Watch phone gallery',
                            subtitle:
                                'Optional: auto-upload new photos that appear in this phone gallery.',
                            flowText: 'Phone gallery → app → backend',
                            active: _galleryImporting,
                            busy: _galleryBusy,
                            status: _galleryStatus,
                            onPressed:
                                activeEvent == null ||
                                    _uploading ||
                                    _usbStartRequested
                                ? null
                                : () => _togglePhoneAutoUpload(activeEvent),
                          ),
                        ],
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

              // ── Enhanced toggle ──
              if (_uploadMode == _UploadMode.quick)
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

              // ── Selected files preview ──
              if (_uploadMode == _UploadMode.quick &&
                  _selectedFiles.isNotEmpty) ...[
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

              if (_uploadMode == _UploadMode.quick &&
                  _uploadStatus != null) ...[
                const SizedBox(height: 6),
                _statusText(_uploadStatus!),
              ],

              const SizedBox(height: 14),

              // ── Upload button ──
              if (_uploadMode == _UploadMode.quick)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: activeEvent == null || _uploading
                        ? null
                        : () => _submit(activeEvent),
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: _uploading
                        ? Text('Uploading ${_selectedFiles.length}...')
                        : const Text('Upload to active event'),
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

  Widget _autoUploadTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String flowText,
    required bool active,
    required bool busy,
    required String? status,
    required VoidCallback? onPressed,
    Widget? configuration,
    VoidCallback? secondaryAction,
    String startLabel = 'Start auto-upload',
    String stopLabel = 'Stop auto-upload',
  }) {
    final actionText = active
        ? stopLabel
        : busy
        ? 'Connecting…'
        : startLabel;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(subtitle, style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      flowText,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (configuration != null) ...[
            const SizedBox(height: 12),
            configuration,
          ],
          if (status != null && status.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              status,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: active
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy && !active ? null : onPressed,
              icon: Icon(
                active ? Icons.stop_rounded : Icons.play_arrow_rounded,
              ),
              label: Text(actionText),
            ),
          ),
          if (secondaryAction != null) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: secondaryAction,
                icon: const Icon(Icons.wifi_outlined, size: 16),
                label: const Text('Open Wi-Fi settings'),
              ),
            ),
          ],
        ],
      ),
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
