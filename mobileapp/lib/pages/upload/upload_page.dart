import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:auto_route/auto_route.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/platform/device_settings.dart';
import 'package:mobileapp/core/platform/gallery_auto_import.dart';
import 'package:mobileapp/core/platform/otg_file_picker.dart';
import 'package:mobileapp/core/router/app_router.dart';
import 'package:mobileapp/core/storage/active_event_storage.dart';
import 'package:mobileapp/core/storage/uploaded_gallery_storage.dart';
import 'package:mobileapp/core/upload/upload_queue_service.dart';
import 'package:mobileapp/core/upload/upload_queue_storage.dart';
import 'package:mobileapp/models/album_model.dart';
import 'package:mobileapp/models/event_invitation_model.dart';
import 'package:mobileapp/utilities/app_toast.dart';
import 'package:permission_handler/permission_handler.dart';

class _CameraProbe {
  const _CameraProbe({
    required this.sourceUrl,
    required this.imageUrl,
    required this.signature,
    required this.usesListing,
  });

  final String sourceUrl;
  final String imageUrl;
  final String signature;
  final bool usesListing;
}

class _SelectedUploadFile {
  const _SelectedUploadFile({
    required this.path,
    required this.name,
  });

  final String path;
  final String name;
}

enum _WirelessImportMode {
  sharedNetwork,
  cameraHotspot,
}

@RoutePage()
class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final _picker = ImagePicker();
  final List<_SelectedUploadFile> _selectedFiles = [];
  Timer? _wirelessTimer;
  Timer? _galleryTimer;
  Timer? _otgTimer;
  bool _isEnhanced = false;
  bool _uploading = false;
  bool _galleryImporting = false;
  bool _galleryBusy = false;
  bool _otgImporting = false;
  bool _otgBusy = false;
  bool _freeingSpace = false;
  bool _autoImporting = false;
  bool _wirelessScanning = false;
  bool _wirelessBusy = false;
  int? _gallerySinceMs;
  final Set<String> _processedGalleryIds = {};
  final Set<String> _processedOtgIds = {};
  String? _galleryStatus;
  String? _otgStatus;
  String? _uploadStatus;
  String? _wirelessStatus;
  _WirelessImportMode? _wirelessMode;
  String? _otgSourceName;
  String? _wirelessSourceUrl;
  String? _wirelessImageUrl;
  String? _lastWirelessSignature;
  bool _wirelessUsesListing = false;
  String? _loadedAlbumEventId;
  String? _selectedAlbumId;
  List<AlbumModel> _albums = [];

  bool get _wirelessImporting => _wirelessScanning || _autoImporting;

  @override
  void dispose() {
    _wirelessTimer?.cancel();
    _galleryTimer?.cancel();
    _otgTimer?.cancel();
    super.dispose();
  }

  void _addSelectedFiles(List<_SelectedUploadFile> files) {
    if (files.isEmpty) return;

    final existingPaths = _selectedFiles.map((file) => file.path).toSet();
    final freshFiles =
        files.where((file) => !existingPaths.contains(file.path)).toList();
    if (freshFiles.isEmpty) return;

    setState(() {
      _selectedFiles.addAll(freshFiles);
    });
  }

  Future<void> _pickPhoneImages() async {
    final images = await _picker.pickMultiImage(imageQuality: 92);
    if (images.isEmpty) return;

    _addSelectedFiles(
      images
          .map((image) => _SelectedUploadFile(path: image.path, name: image.name))
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
    try {
      final files = await OtgFilePicker.pickImages();
      if (files.isEmpty) return;

      _addSelectedFiles(
        files
            .map((file) => _SelectedUploadFile(path: file.path, name: file.name))
            .toList(),
      );
    } on MissingPluginException {
      AppToast.error('Rebuild app once to enable OTG picker');
    } catch (_) {
      AppToast.error('Failed to open OTG file picker');
    }
  }

  Future<void> _handleOtgAction(EventSummary? event) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.usb_outlined),
                title: const Text('Pick OTG images'),
                subtitle: const Text('Choose images one time'),
                onTap: () => Navigator.of(context).pop('pick'),
              ),
              ListTile(
                leading: Icon(
                  _otgImporting ? Icons.pause_circle_outline : Icons.folder_open,
                ),
                title: Text(
                  _otgImporting ? 'Stop source auto-upload' : 'Select source folder',
                ),
                subtitle: Text(
                  _otgImporting
                      ? (_otgSourceName == null
                          ? 'Stop current OTG source'
                          : 'Stop watching $_otgSourceName')
                      : 'Choose camera folder, then new images upload automatically',
                ),
                onTap: () => Navigator.of(context).pop('source'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || choice == null) return;

    if (choice == 'pick') {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await _pickOtgFiles();
      return;
    }

    if (_otgImporting) {
      _stopOtgAutoImport();
      return;
    }

    if (event == null) {
      AppToast.error('Select active event first');
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 200));
    await _startOtgAutoImport(event);
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

  Future<String> _uploadFile({
    required String path,
    required String filename,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        path,
        filename: filename,
      ),
    });
    final response = await DioHelper.post('/image/upload', data: formData);
    return response.data['url']?.toString() ?? '';
  }

  Future<List<String>> _uploadFilesBatch(List<_SelectedUploadFile> files) async {
    final formData = FormData.fromMap({
      'files': [
        for (final file in files)
          await MultipartFile.fromFile(
            file.path,
            filename: file.name,
          ),
      ],
    });
    final response = await DioHelper.post('/image/upload/batch', data: formData);
    final urls = response.data['urls'] as List? ?? [];
    return urls.map((url) => url.toString()).where((url) => url.isNotEmpty).toList();
  }

  Future<String> _uploadBytes({
    required Uint8List bytes,
    required String filename,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
      ),
    });
    final response = await DioHelper.post('/image/upload', data: formData);
    return response.data['url']?.toString() ?? '';
  }

  Future<bool> _uploadOrQueueFile({
    required EventSummary event,
    required String path,
    required String filename,
    required String source,
  }) async {
    return UploadQueueService.uploadNowOrQueueFile(
      event: event,
      path: path,
      filename: filename,
      isEnhanced: _isEnhanced,
      albumId: _selectedAlbumId,
      source: source,
    );
  }

  Future<bool> _uploadOrQueueBytes({
    required EventSummary event,
    required Uint8List bytes,
    required String filename,
    required String source,
  }) async {
    return UploadQueueService.uploadNowOrQueueBytes(
      event: event,
      bytes: bytes,
      filename: filename,
      isEnhanced: _isEnhanced,
      albumId: _selectedAlbumId,
      source: source,
    );
  }

  Future<void> _queueBytesOnly({
    required EventSummary event,
    required Uint8List bytes,
    required String filename,
    required String source,
    String? lastError,
  }) async {
    await UploadQueueService.queueBytesOnly(
      event: event,
      bytes: bytes,
      filename: filename,
      isEnhanced: _isEnhanced,
      albumId: _selectedAlbumId,
      source: source,
      lastError: lastError,
    );
  }

  Future<void> _createEventImage(EventSummary event, String imageUrl) async {
    await DioHelper.post(
      '/eventImage',
      data: {
        'eventId': event.id,
        'imageUrl': imageUrl,
        'isEnhanced': _isEnhanced,
        if (_selectedAlbumId != null) 'albumId': _selectedAlbumId,
      },
    );
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
      setState(() {
        _albums = data
            .map((item) => AlbumModel.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _albums = []);
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
    final isPng =
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4e;
    final isGif =
        bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46;
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

  List<String> _wirelessCameraCandidates() {
    const hosts = [
      'http://192.168.0.1',
      'http://192.168.1.1',
      'http://192.168.1.2',
      'http://192.168.1.10',
      'http://192.168.4.1',
      'http://192.168.42.1',
      'http://192.168.49.1',
      'http://10.0.0.1',
      'http://10.0.0.10',
      'http://172.20.10.1',
    ];
    const paths = [
      '/',
      '/index.html',
      '/DCIM/',
      '/DCIM/100CANON/',
      '/DCIM/101CANON/',
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
      '/latest.jpg',
      '/latest.jpeg',
      '/image.jpg',
      '/photo.jpg',
      '/capture',
      '/snapshot',
      '/shot.jpg',
    ];

    return [
      for (final host in hosts)
        for (final path in paths) '$host$path',
    ];
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
    final response = await DioHelper.dio.get<List<int>>(
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
    final returnsImage = contentType.toLowerCase().startsWith('image/') ||
        (contentType.isEmpty && _looksLikeImage(bytes));
    if (bytes.isEmpty || !returnsImage) return null;
    return bytes;
  }

  Future<_CameraProbe?> _probeCameraUrl(String url) async {
    try {
      final response = await DioHelper.dio.get<List<int>>(
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
      final returnsImage = contentType.toLowerCase().startsWith('image/') ||
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
      if (imageLinks.isEmpty) return null;

      final latestImageUrl = imageLinks.last;
      final imageBytes = await _downloadImageBytes(latestImageUrl);
      if (imageBytes == null) return null;

      return _CameraProbe(
        sourceUrl: url,
        imageUrl: latestImageUrl,
        signature: _signatureForBytes(imageBytes),
        usesListing: true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<_CameraProbe?> _discoverWirelessCamera() async {
    final candidates = _wirelessCameraCandidates();
    final completer = Completer<_CameraProbe?>();
    var pending = candidates.length;

    for (final url in candidates) {
      _probeCameraUrl(url).then((probe) {
        if (probe != null && !completer.isCompleted) {
          completer.complete(probe);
          return;
        }

        pending -= 1;
        if (pending == 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      });
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
    _wirelessTimer?.cancel();
    setState(() {
      _wirelessScanning = true;
      _autoImporting = false;
      _wirelessSourceUrl = null;
      _wirelessMode = mode;
      _wirelessImageUrl = null;
      _wirelessUsesListing = false;
      _wirelessStatus = mode == _WirelessImportMode.cameraHotspot
          ? 'Searching for camera hotspot image feed...'
          : 'Searching for shared-network camera...';
    });

    final probe = await _discoverWirelessCamera();
    if (!mounted) return;

    if (probe == null) {
      setState(() {
        _wirelessScanning = false;
        _wirelessStatus =
            mode == _WirelessImportMode.cameraHotspot
                ? 'No camera hotspot feed found. Connect phone to camera Wi-Fi and try again.'
                : 'No shared-network camera found. Put phone and camera on same network.';
      });
      return;
    }

    setState(() {
      _wirelessScanning = false;
      _wirelessSourceUrl = probe.sourceUrl;
      _wirelessImageUrl = probe.imageUrl;
      _wirelessUsesListing = probe.usesListing;
      _lastWirelessSignature = probe.signature;
      _autoImporting = true;
      _wirelessStatus = mode == _WirelessImportMode.cameraHotspot
          ? 'Camera hotspot connected. New photos will save to queue.'
          : 'Camera connected. Waiting for new photos...';
    });

    _wirelessTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _pollWirelessCamera(event),
    );
  }

  Future<void> _pollWirelessCamera(EventSummary event) async {
    if (_wirelessBusy) return;

    final sourceUrl = _wirelessSourceUrl;
    if (sourceUrl == null) {
      setState(() => _wirelessStatus = 'Connect a wireless camera first');
      return;
    }

    setState(() {
      _wirelessBusy = true;
      _wirelessStatus = 'Checking camera...';
    });

    try {
      var imageUrl = _wirelessImageUrl ?? sourceUrl;
      Uint8List? bytes;

      if (_wirelessUsesListing) {
        final listingResponse = await DioHelper.dio.get<List<int>>(
          sourceUrl,
          options: Options(responseType: ResponseType.bytes),
        );
        final listingBytes = Uint8List.fromList(listingResponse.data ?? []);
        final body = utf8.decode(listingBytes, allowMalformed: true);
        final imageLinks = _extractImageLinks(body, sourceUrl);
        if (imageLinks.isEmpty) {
          setState(() => _wirelessStatus = 'Camera folder page has no image links');
          return;
        }
        imageUrl = imageLinks.last;
        bytes = await _downloadImageBytes(imageUrl);
      } else {
        bytes = await _downloadImageBytes(imageUrl);
      }

      if (bytes == null) {
        setState(() => _wirelessStatus = 'Camera source did not return an image');
        return;
      }

      _wirelessImageUrl = imageUrl;
      final signature = _signatureForBytes(bytes);
      if (signature == _lastWirelessSignature) {
        setState(() => _wirelessStatus = 'No new image yet');
        return;
      }

      _lastWirelessSignature = signature;
      setState(() => _wirelessStatus = 'New image found. Importing...');

      final filename = _filenameFromUrl(imageUrl);
      if (_wirelessMode == _WirelessImportMode.cameraHotspot) {
        await _queueBytesOnly(
          event: event,
          bytes: bytes,
          filename: filename,
          source: 'wireless-hotspot',
          lastError: 'Waiting for internet connection',
        );
        setState(() {
          _wirelessStatus = 'Saved latest camera image. Upload queued.';
        });
      } else {
        final uploaded = await _uploadOrQueueBytes(
          event: event,
          bytes: bytes,
          filename: filename,
          source: 'wireless-shared-network',
        );
        setState(() {
          _wirelessStatus = uploaded
              ? 'Uploaded latest camera image'
              : 'Saved latest camera image. Waiting for internet upload.';
        });
      }
    } catch (_) {
      setState(() {
        _wirelessStatus =
            'Wireless import failed. Check camera Wi-Fi and internet.';
      });
    } finally {
      if (mounted) {
        setState(() => _wirelessBusy = false);
      }
    }
  }

  Future<void> _pollGallery(EventSummary event) async {
    if (_galleryBusy) return;

    final sinceMs = _gallerySinceMs;
    if (sinceMs == null) return;

    setState(() {
      _galleryBusy = true;
      _galleryStatus = 'Checking phone photos...';
    });

    try {
      final images = await GalleryAutoImport.recentImages(
        sinceMs: sinceMs,
        excludeIds: _processedGalleryIds.toList(),
      );

      if (images.isEmpty) {
        setState(() => _galleryStatus = 'Waiting for new phone photos...');
        return;
      }

      for (final image in images.reversed) {
        if (_processedGalleryIds.contains(image.id)) continue;

        setState(() => _galleryStatus = 'Importing ${image.name}...');
        final uploaded = await _uploadOrQueueFile(
          event: event,
          path: image.path,
          filename: image.name,
          source: 'gallery',
        );
        _processedGalleryIds.add(image.id);
        await UploadedGalleryStorage.add(id: image.id, name: image.name);

        try {
          await File(image.path).delete();
        } catch (_) {}

        if (!mounted) return;
        setState(() {
          _galleryStatus = uploaded
              ? 'Uploaded ${image.name}'
              : 'Saved ${image.name}. Upload queued for internet.';
        });
      }
    } on MissingPluginException {
      setState(() {
        _galleryStatus = 'Restart app once to enable phone auto-upload';
      });
    } catch (_) {
      setState(() {
        _galleryStatus = 'Phone auto-upload failed. Check photo permission.';
      });
    } finally {
      if (mounted) {
        setState(() => _galleryBusy = false);
      }
    }
  }

  Future<void> _startGalleryAutoImport(EventSummary event) async {
    final allowed = await _requestGalleryPermission();
    if (!allowed) {
      AppToast.error('Photo permission is required');
      return;
    }

    _galleryTimer?.cancel();
    _processedGalleryIds.clear();
    setState(() {
      _galleryImporting = true;
      _gallerySinceMs = DateTime.now().millisecondsSinceEpoch;
      _galleryStatus = 'Phone auto-upload is on';
    });

    _galleryTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _pollGallery(event),
    );
  }

  Future<void> _pollOtgSource(EventSummary event) async {
    if (_otgBusy) return;

    setState(() {
      _otgBusy = true;
      _otgStatus = 'Checking OTG source...';
    });

    try {
      final images = await OtgFilePicker.recentSourceImages(
        excludeIds: _processedOtgIds.toList(),
      );

      if (images.isEmpty) {
        setState(() {
          _otgStatus = _otgSourceName == null
              ? 'Waiting for OTG source...'
              : 'Waiting for new images in $_otgSourceName...';
        });
        return;
      }

      for (final image in images.reversed) {
        if (_processedOtgIds.contains(image.id)) continue;

        setState(() => _otgStatus = 'Importing ${image.name} from OTG...');
        final uploaded = await _uploadOrQueueFile(
          event: event,
          path: image.path,
          filename: image.name,
          source: 'otg',
        );
        _processedOtgIds.add(image.id);

        if (!mounted) return;
        setState(() {
          _otgStatus = uploaded
              ? 'Uploaded ${image.name} from OTG'
              : 'Saved ${image.name} from OTG. Upload queued.';
        });
      }
    } on MissingPluginException {
      setState(() => _otgStatus = 'Restart app once to enable OTG auto-upload');
    } catch (_) {
      setState(() {
        _otgStatus = 'OTG auto-upload failed. Reconnect source, keep app open.';
      });
    } finally {
      if (mounted) {
        setState(() => _otgBusy = false);
      }
    }
  }

  Future<void> _startOtgAutoImport(EventSummary event) async {
    try {
      final source = await OtgFilePicker.pickSource();
      if (source == null) {
        setState(() => _otgStatus = 'OTG source selection cancelled');
        return;
      }

      _otgTimer?.cancel();
      _processedOtgIds.clear();
      setState(() {
        _otgImporting = true;
        _otgSourceName = source.name;
        _otgStatus = 'OTG source ${source.name} connected. Waiting for images...';
      });

      _otgTimer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => _pollOtgSource(event),
      );
      await _pollOtgSource(event);
    } on MissingPluginException {
      setState(() => _otgStatus = 'Restart app once to enable OTG auto-upload');
      AppToast.error('Restart app once to enable OTG auto-upload');
    } on PlatformException catch (error) {
      final message = error.message?.trim();
      final readable = switch (error.code) {
        'NO_FOLDER_PICKER' =>
          'Phone file picker cannot open folder selection on this device',
        'NO_OTG_SOURCE' =>
          'No OTG source found. Connect camera/storage in file transfer mode',
        _ => message?.isNotEmpty == true ? message! : 'Failed to open source folder picker',
      };
      setState(() => _otgStatus = readable);
      AppToast.error(readable);
    } catch (_) {
      setState(() => _otgStatus = 'Failed to start OTG auto-upload');
      AppToast.error('Failed to start OTG auto-upload');
    }
  }

  void _stopOtgAutoImport() {
    _otgTimer?.cancel();
    _otgTimer = null;
    setState(() {
      _otgImporting = false;
      _otgBusy = false;
      _otgSourceName = null;
      _otgStatus = 'OTG auto-upload stopped';
    });
  }

  void _stopGalleryAutoImport() {
    _galleryTimer?.cancel();
    _galleryTimer = null;
    setState(() {
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

    setState(() {
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
    setState(() {
      _freeingSpace = false;
      _galleryStatus = deletedIds.isEmpty
          ? 'No phone images removed'
          : 'Removed ${deletedIds.length} uploaded images';
    });
  }

  void _stopWirelessImport() {
    _wirelessTimer?.cancel();
    _wirelessTimer = null;
    setState(() {
      _autoImporting = false;
      _wirelessScanning = false;
      _wirelessMode = null;
      _wirelessSourceUrl = null;
      _wirelessImageUrl = null;
      _wirelessUsesListing = false;
      _lastWirelessSignature = null;
      _wirelessStatus = 'Wireless camera disconnected';
    });
  }

  Future<void> _handleWirelessAction(EventSummary? event) async {
    if (_wirelessImporting) {
      _stopWirelessImport();
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
                leading: const Icon(Icons.router_outlined),
                title: const Text('Shared network live upload'),
                subtitle: const Text(
                  'Phone and camera on same internet network',
                ),
                onTap: () => Navigator.of(context).pop(
                  _WirelessImportMode.sharedNetwork,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.wifi_tethering_outlined),
                title: const Text('Camera hotspot import'),
                subtitle: const Text(
                  'Phone joins camera Wi-Fi, save now and upload later',
                ),
                onTap: () => Navigator.of(context).pop(
                  _WirelessImportMode.cameraHotspot,
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || choice == null) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await _findAndStartWirelessImport(event, choice);
  }

  Future<void> _submit(EventSummary event) async {
    if (_selectedFiles.isEmpty) {
      AppToast.error('Choose images first');
      return;
    }

    final files = List<_SelectedUploadFile>.from(_selectedFiles);

    setState(() {
      _uploading = true;
      _uploadStatus = 'Uploading ${files.length} images...';
    });

    try {
      final imageUrls = await _uploadFilesBatch(files);
      if (imageUrls.isEmpty) {
        throw Exception('Image upload returned no URLs');
      }

      setState(() {
        _uploadStatus = 'Saving ${imageUrls.length} images to ${event.title}...';
      });

      await _createEventImages(event, imageUrls);
      AppToast.success('${imageUrls.length} images uploaded to ${event.title}');
      setState(() {
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
        setState(() => _uploading = false);
      }
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

        return Scaffold(
          appBar: AppBar(title: const Text('Upload')),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (activeEvent == null)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No active event selected. Accept an invitation and make an event active first.',
                    ),
                  ),
                )
              else
                Card(
                  child: ListTile(
                    title: const Text('Active event'),
                    subtitle: Text(activeEvent.title),
                    trailing: IconButton(
                      tooltip: 'Clear active event',
                      onPressed: _uploading ? null : ActiveEventStorage.clear,
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
              if (activeEvent != null && _albums.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: _selectedAlbumId,
                  decoration: const InputDecoration(
                    labelText: 'Upload album',
                    border: OutlineInputBorder(),
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
                  onChanged: _uploading
                      ? null
                      : (value) => setState(() => _selectedAlbumId = value),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _uploading ? null : _pickPhoneImages,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Phone'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _uploading ? null : _pickCameraImage,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Camera'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _uploading || _otgBusy
                        ? null
                        : () => _handleOtgAction(activeEvent),
                    icon: Icon(
                      _otgImporting ? Icons.sync : Icons.usb_outlined,
                    ),
                    label: Text(_otgImporting ? 'OTG on' : 'OTG'),
                  ),
                  if (activeEvent != null)
                    OutlinedButton.icon(
                      onPressed: () =>
                          context.router.root.push(const EventImagesRoute()),
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Uploads'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: activeEvent == null || _uploading || _galleryBusy
                      ? null
                      : _galleryImporting
                          ? _stopGalleryAutoImport
                          : () => _startGalleryAutoImport(activeEvent),
                  icon: Icon(
                    _galleryImporting
                        ? Icons.pause_circle_outline
                        : Icons.autorenew,
                  ),
                  label: Text(
                    _galleryImporting
                        ? 'Stop phone photos auto-upload'
                        : 'Auto upload from phone photos',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          activeEvent == null || _uploading || _wirelessBusy
                              ? null
                              : _wirelessImporting
                                  ? _stopWirelessImport
                                  : () => _handleWirelessAction(activeEvent),
                      icon: Icon(
                        _wirelessImporting
                            ? Icons.pause_circle_outline
                            : Icons.wifi_tethering,
                      ),
                      label: Text(
                        _wirelessImporting
                            ? 'Stop wireless import'
                            : 'Wireless import',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _openWifiSettings,
                    icon: const Icon(Icons.wifi_outlined),
                    label: const Text('Wi-Fi'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder(
                valueListenable: UploadQueueStorage.items,
                builder: (context, queued, _) {
                  return ValueListenableBuilder(
                    valueListenable: UploadQueueService.isProcessing,
                    builder: (context, queueBusy, __) {
                      final count = queued.length;
                      return SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: count == 0 || queueBusy
                              ? null
                              : () async {
                                  await UploadQueueService.processQueue();
                                  if (!mounted) return;
                                  final left = UploadQueueStorage.items.value.length;
                                  if (left == 0) {
                                    AppToast.success('Queued uploads complete');
                                  } else {
                                    AppToast.error('$left uploads still waiting');
                                  }
                                },
                          icon: Icon(
                            queueBusy
                                ? Icons.sync
                                : Icons.cloud_upload_outlined,
                          ),
                          label: Text(
                            queueBusy
                                ? 'Uploading queued...'
                                : count == 0
                                    ? 'No queued uploads'
                                    : 'Upload queued ($count)',
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _freeingSpace ? null : _freeUploadedGallerySpace,
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: Text(_freeingSpace ? 'Cleaning...' : 'Free space'),
                ),
              ),
              if (_galleryStatus != null) ...[
                const SizedBox(height: 6),
                Text(
                  _galleryStatus!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (_wirelessStatus != null) ...[
                const SizedBox(height: 6),
                Text(
                  _wirelessStatus!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (_otgStatus != null) ...[
                const SizedBox(height: 6),
                Text(
                  _otgStatus!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enhanced image'),
                value: _isEnhanced,
                onChanged: _uploading
                    ? null
                    : (value) => setState(() => _isEnhanced = value),
              ),
              if (_selectedFiles.isNotEmpty) ...[
                Card(
                  child: ListTile(
                    title: Text('${_selectedFiles.length} images selected'),
                    subtitle: Text(
                      _selectedFiles
                          .take(3)
                          .map((file) => file.name)
                          .join(', '),
                    ),
                    trailing: TextButton(
                      onPressed: _uploading
                          ? null
                          : () => setState(() {
                                _selectedFiles.clear();
                                _uploadStatus = null;
                              }),
                      child: const Text('Clear'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(_selectedFiles.first.path),
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
              if (_uploadStatus != null) ...[
                const SizedBox(height: 8),
                Text(
                  _uploadStatus!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 24),
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
            ],
          ),
        );
      },
    );
  }
}
