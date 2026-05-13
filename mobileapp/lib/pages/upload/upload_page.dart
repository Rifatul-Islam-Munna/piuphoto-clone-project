import 'dart:async';
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
import 'package:mobileapp/models/event_invitation_model.dart';
import 'package:mobileapp/utilities/app_toast.dart';
import 'package:permission_handler/permission_handler.dart';

class _CameraProbe {
  const _CameraProbe({
    required this.url,
    required this.signature,
  });

  final String url;
  final String signature;
}

@RoutePage()
class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final _picker = ImagePicker();
  Timer? _wirelessTimer;
  Timer? _galleryTimer;
  bool _isEnhanced = false;
  bool _uploading = false;
  bool _galleryImporting = false;
  bool _galleryBusy = false;
  bool _freeingSpace = false;
  bool _autoImporting = false;
  bool _wirelessScanning = false;
  bool _wirelessBusy = false;
  int? _gallerySinceMs;
  final Set<String> _processedGalleryIds = {};
  String? _galleryStatus;
  String? _wirelessStatus;
  String? _wirelessImageUrl;
  String? _lastWirelessSignature;
  String? _selectedFilePath;
  String? _selectedFileName;

  @override
  void dispose() {
    _wirelessTimer?.cancel();
    _galleryTimer?.cancel();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final image = await _picker.pickImage(
      source: source,
      imageQuality: 92,
    );
    if (image == null) return;
    setState(() {
      _selectedFilePath = image.path;
      _selectedFileName = image.name;
    });
  }

  Future<void> _pickOtgFile() async {
    try {
      final file = await OtgFilePicker.pickImage();
      if (file == null) return;
      setState(() {
        _selectedFilePath = file.path;
        _selectedFileName = file.name;
      });
    } on MissingPluginException {
      AppToast.error('Rebuild the app once to enable OTG picker');
    } catch (_) {
      AppToast.error('Failed to open OTG file picker');
    }
  }

  Future<void> _openWifiSettings() async {
    try {
      await DeviceSettings.openWifiSettings();
    } on MissingPluginException {
      AppToast.error('Restart the app once to enable Wi-Fi settings');
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

  Future<void> _createEventImage(EventSummary event, String imageUrl) async {
    await DioHelper.post(
      '/eventImage',
      data: {
        'eventId': event.id,
        'imageUrl': imageUrl,
        'isEnhanced': _isEnhanced,
      },
    );
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
      'http://192.168.4.1',
      'http://192.168.42.1',
      'http://192.168.49.1',
      'http://10.0.0.1',
      'http://172.20.10.1',
    ];
    const paths = [
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

      if (bytes.isEmpty || !returnsImage) return null;
      return _CameraProbe(url: url, signature: _signatureForBytes(bytes));
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

  Future<void> _findAndStartWirelessImport(EventSummary event) async {
    _wirelessTimer?.cancel();
    setState(() {
      _wirelessScanning = true;
      _autoImporting = false;
      _wirelessImageUrl = null;
      _wirelessStatus = 'Searching for wireless camera...';
    });

    final probe = await _discoverWirelessCamera();
    if (!mounted) return;

    if (probe == null) {
      setState(() {
        _wirelessScanning = false;
        _wirelessStatus =
            'No camera found. Connect phone to camera Wi-Fi and try again.';
      });
      return;
    }

    setState(() {
      _wirelessScanning = false;
      _wirelessImageUrl = probe.url;
      _lastWirelessSignature = probe.signature;
      _autoImporting = true;
      _wirelessStatus = 'Camera connected. Waiting for new photos...';
    });

    _wirelessTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _pollWirelessCamera(event),
    );
  }

  Future<void> _pollWirelessCamera(EventSummary event) async {
    if (_wirelessBusy) return;

    final url = _wirelessImageUrl;
    if (url == null) {
      setState(() => _wirelessStatus = 'Connect a wireless camera first');
      return;
    }

    setState(() {
      _wirelessBusy = true;
      _wirelessStatus = 'Checking camera...';
    });

    try {
      final response = await DioHelper.dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final contentType =
          response.headers.value(Headers.contentTypeHeader) ?? '';
      final bytes = Uint8List.fromList(response.data ?? []);
      final returnsImage = contentType.toLowerCase().startsWith('image/') ||
          (contentType.isEmpty && _looksLikeImage(bytes));

      if (bytes.isEmpty || !returnsImage) {
        setState(() {
          _wirelessStatus = 'Camera URL did not return an image';
        });
        return;
      }

      final signature = _signatureForBytes(bytes);
      if (signature == _lastWirelessSignature) {
        setState(() => _wirelessStatus = 'No new image yet');
        return;
      }

      _lastWirelessSignature = signature;
      setState(() => _wirelessStatus = 'New image found. Uploading...');

      final imageUrl = await _uploadBytes(
        bytes: bytes,
        filename: _filenameFromUrl(url),
      );
      if (imageUrl.isEmpty) {
        throw Exception('Image upload returned no URL');
      }

      await _createEventImage(event, imageUrl);
      setState(() => _wirelessStatus = 'Uploaded latest camera image');
    } catch (error) {
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

        setState(() => _galleryStatus = 'Uploading ${image.name}...');
        final imageUrl = await _uploadFile(
          path: image.path,
          filename: image.name,
        );
        if (imageUrl.isEmpty) {
          throw Exception('Image upload returned no URL');
        }

        await _createEventImage(event, imageUrl);
        _processedGalleryIds.add(image.id);
        await UploadedGalleryStorage.add(id: image.id, name: image.name);

        try {
          await File(image.path).delete();
        } catch (_) {}

        if (!mounted) return;
        setState(() {
          _galleryStatus = 'Uploaded ${image.name}';
        });
      }
    } on MissingPluginException {
      setState(() {
        _galleryStatus = 'Restart the app once to enable phone auto-upload';
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
      _wirelessImageUrl = null;
      _lastWirelessSignature = null;
      _wirelessStatus = 'Wireless camera disconnected';
    });
  }

  Future<void> _submit(EventSummary event) async {
    final filePath = _selectedFilePath;
    final fileName = _selectedFileName;
    if (filePath == null || fileName == null) {
      AppToast.error('Choose an image first');
      return;
    }

    setState(() => _uploading = true);
    try {
      final imageUrl = await _uploadFile(path: filePath, filename: fileName);
      if (imageUrl.isEmpty) {
        throw Exception('Image upload returned no URL');
      }

      await _createEventImage(event, imageUrl);
      AppToast.success('Image uploaded to ${event.title}');
      setState(() {
        _selectedFilePath = null;
        _selectedFileName = null;
        _isEnhanced = false;
      });
    } catch (_) {
      AppToast.error('Failed to upload image');
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
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        _uploading ? null : () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Phone'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        _uploading ? null : () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Camera'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _uploading ? null : _pickOtgFile,
                    icon: const Icon(Icons.usb_outlined),
                    label: const Text('OTG'),
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
                        ? 'Stop camera auto-upload'
                        : 'Auto upload from camera',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed:
                      _freeingSpace ? null : _freeUploadedGallerySpace,
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
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enhanced image'),
                value: _isEnhanced,
                onChanged: _uploading
                    ? null
                    : (value) => setState(() => _isEnhanced = value),
              ),
              if (_selectedFilePath != null) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(_selectedFilePath!),
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
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
                      ? const Text('Uploading...')
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
