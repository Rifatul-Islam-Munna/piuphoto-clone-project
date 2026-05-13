import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:auto_route/auto_route.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/platform/otg_file_picker.dart';
import 'package:mobileapp/core/router/app_router.dart';
import 'package:mobileapp/core/storage/active_event_storage.dart';
import 'package:mobileapp/models/event_invitation_model.dart';
import 'package:mobileapp/utilities/app_toast.dart';

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
  bool _isEnhanced = false;
  bool _uploading = false;
  bool _autoImporting = false;
  bool _wirelessScanning = false;
  bool _wirelessBusy = false;
  String? _wirelessStatus;
  String? _wirelessImageUrl;
  String? _lastWirelessSignature;
  String? _selectedFilePath;
  String? _selectedFileName;

  @override
  void dispose() {
    _wirelessTimer?.cancel();
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
              if (activeEvent != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        context.router.root.push(const EventImagesRoute()),
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('View uploaded images'),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _uploading ? null : () => _pick(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Phone'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _uploading ? null : () => _pick(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Camera'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _uploading ? null : _pickOtgFile,
                  icon: const Icon(Icons.usb_outlined),
                  label: const Text('OTG / external file'),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: activeEvent == null ||
                              _uploading ||
                              _wirelessScanning
                          ? null
                          : _autoImporting
                              ? _stopWirelessImport
                              : () => _findAndStartWirelessImport(activeEvent),
                      icon: Icon(
                        _autoImporting
                            ? Icons.link_off
                            : Icons.wifi_find_outlined,
                      ),
                      label: Text(
                        _wirelessScanning
                            ? 'Searching...'
                            : _autoImporting
                                ? 'Disconnect camera'
                                : 'Find wireless camera',
                      ),
                    ),
                  ),
                ],
              ),
              if (_wirelessStatus != null) ...[
                const SizedBox(height: 8),
                Text(_wirelessStatus!),
              ],
              const SizedBox(height: 12),
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
