import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/platform/canon_ccapi_camera.dart';
import 'package:mobileapp/core/platform/device_settings.dart';
import 'package:mobileapp/core/platform/gallery_auto_import.dart';
import 'package:mobileapp/core/platform/network_camera_discovery.dart';
import 'package:mobileapp/core/platform/otg_file_picker.dart';
import 'package:mobileapp/core/platform/ptp_ip_camera.dart';
import 'package:mobileapp/core/platform/upnp_camera_media.dart';
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

class _PtpProbe {
  const _PtpProbe(this.camera, this.images);

  final PtpIpCamera camera;
  final List<PtpIpImage> images;
}

enum _WirelessImportMode { sharedNetwork, cameraHotspot }

@RoutePage()
class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final _picker = ImagePicker();
  final Dio _cameraDio = Dio();
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
  bool _otgNativeCameraMode = false;
  bool _freeingSpace = false;
  bool _autoImporting = false;
  bool _wirelessScanning = false;
  bool _wirelessBusy = false;
  bool _disposed = false;
  int _wirelessGeneration = 0;
  int _otgGeneration = 0;
  int _galleryGeneration = 0;
  int _wirelessFailureCount = 0;
  int? _gallerySinceMs;
  final Set<String> _processedGalleryIds = {};
  final Set<String> _processedOtgIds = {};
  final Set<String> _processedWirelessIds = {};
  String? _galleryStatus;
  String? _otgStatus;
  String? _uploadStatus;
  String? _wirelessStatus;
  _WirelessImportMode? _wirelessMode;
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

  bool get _wirelessImporting => _wirelessScanning || _autoImporting;

  void _safeSetState(VoidCallback update) {
    if (!mounted || _disposed) return;
    setState(update);
  }

  bool _wirelessActive(int generation) =>
      mounted && !_disposed && generation == _wirelessGeneration;

  bool _otgActive(int generation) =>
      mounted && !_disposed && generation == _otgGeneration;

  bool _galleryActive(int generation) =>
      mounted && !_disposed && generation == _galleryGeneration;

  @override
  void dispose() {
    _disposed = true;
    _wirelessGeneration += 1;
    _otgGeneration += 1;
    _galleryGeneration += 1;
    _wirelessTimer?.cancel();
    _galleryTimer?.cancel();
    _otgTimer?.cancel();
    _wirelessTimer = null;
    _galleryTimer = null;
    _otgTimer = null;
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
    try {
      List<ConnectedCameraImage> cameraImages = const [];
      try {
        cameraImages = await OtgFilePicker.connectedCameraImages();
      } on MissingPluginException {
        cameraImages = const [];
      } on PlatformException {
        cameraImages = const [];
      }

      if (cameraImages.isNotEmpty && mounted) {
        final selectedIds = await _selectConnectedCameraImages(cameraImages);
        if (selectedIds != null && selectedIds.isNotEmpty) {
          final files = await OtgFilePicker.importConnectedCameraImages(
            selectedIds,
          );
          _addSelectedFiles(
            files
                .map(
                  (file) =>
                      _SelectedUploadFile(path: file.path, name: file.name),
                )
                .toList(),
          );
          return;
        }
      }

      final files = await OtgFilePicker.pickImages();
      if (files.isEmpty) return;
      _addSelectedFiles(
        files
            .map(
              (file) => _SelectedUploadFile(path: file.path, name: file.name),
            )
            .toList(),
      );
    } on MissingPluginException {
      AppToast.error('Rebuild app once to enable OTG picker');
    } catch (error) {
      AppToast.error('Failed to read connected camera: $error');
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

  String _wirelessFingerprint({
    required EventSummary event,
    required String imageUrl,
    required String signature,
  }) {
    return '${event.id}|wireless|$imageUrl|$signature';
  }

  Future<void> _queueBytesOnly({
    required EventSummary event,
    required Uint8List bytes,
    required String filename,
    required String source,
    String? fingerprint,
    String? lastError,
  }) async {
    await UploadQueueService.queueBytesOnly(
      event: event,
      bytes: bytes,
      filename: filename,
      isEnhanced: _isEnhanced,
      albumId: _selectedAlbumId,
      source: source,
      fingerprint: fingerprint,
      lastError: lastError,
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
              final images = await camera
                  .recentImages(limit: 50)
                  .timeout(const Duration(seconds: 6));
              return _PtpProbe(camera, images);
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
    _canonCcapiCamera = null;
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
        signature: ptpProbe.images.isEmpty
            ? 'ptpip-ready'
            : ptpProbe.images.first.fingerprint,
        usesListing: false,
        initialKeys: {
          for (final image in ptpProbe.images)
            '${ptpProbe.camera.host}:${ptpProbe.camera.port}:${image.handle}',
        },
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
    if (!_wirelessActive(generation)) return null;
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
    _wirelessTimer?.cancel();
    final generation = ++_wirelessGeneration;
    _safeSetState(() {
      _wirelessScanning = true;
      _wirelessBusy = false;
      _autoImporting = false;
      _wirelessSourceUrl = null;
      _wirelessMode = mode;
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
          ? 'Camera hotspot connected. New photos will save to queue.'
          : 'Camera connected. Waiting for new photos...';
    });

    _wirelessTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!_wirelessActive(generation)) {
        timer.cancel();
        return;
      }
      unawaited(_pollWirelessCamera(event, generation));
    });
  }

  Future<void> _saveWirelessBytes({
    required EventSummary event,
    required int generation,
    required Uint8List bytes,
    required String filename,
    required String imageKey,
    required String signature,
    required String source,
  }) async {
    if (!_wirelessActive(generation)) return;
    if (_wirelessMode == _WirelessImportMode.cameraHotspot) {
      await _queueBytesOnly(
        event: event,
        bytes: bytes,
        filename: filename,
        source: '$source-hotspot',
        fingerprint: _wirelessFingerprint(
          event: event,
          imageUrl: imageKey,
          signature: signature,
        ),
        lastError: 'Waiting for internet connection',
      );
      if (mounted) {
        _safeSetState(
          () => _wirelessStatus = 'Saved new camera photo. Upload queued.',
        );
      }
      return;
    }

    final uploaded = await UploadQueueService.importBytesLocalFirst(
      event: event,
      bytes: bytes,
      filename: filename,
      isEnhanced: _isEnhanced,
      albumId: _selectedAlbumId,
      source: '$source-shared-network',
      fingerprint: _wirelessFingerprint(
        event: event,
        imageUrl: imageKey,
        signature: signature,
      ),
      tryUploadNow: true,
    );
    if (mounted) {
      _safeSetState(() {
        _wirelessStatus = uploaded
            ? 'Saved and uploaded new camera photo'
            : 'Saved new camera photo. Waiting for internet upload.';
      });
    }
  }

  Future<bool> _pollPtpIpCamera(EventSummary event, int generation) async {
    if (!_wirelessActive(generation)) return true;
    final camera = _ptpIpCamera;
    if (camera == null) return false;
    final images = await camera
        .recentImages(limit: 50)
        .timeout(const Duration(seconds: 8));
    if (!_wirelessActive(generation)) return true;
    if (images.isEmpty) {
      _safeSetState(
        () =>
            _wirelessStatus = 'PTP/IP camera connected. Waiting for a photo...',
      );
      return true;
    }

    String keyFor(PtpIpImage image) =>
        '${camera.host}:${camera.port}:${image.handle}';
    final fresh = images
        .where((image) => !_processedWirelessIds.contains(keyFor(image)))
        .toList(growable: false);
    if (fresh.isEmpty) {
      _safeSetState(
        () => _wirelessStatus = 'Camera connected. No new photo yet.',
      );
      return true;
    }

    // recentImages is newest-first. Upload older unseen frames first so bursts
    // arrive at the backend in shooting order.
    for (final image in fresh.reversed) {
      if (!_wirelessActive(generation)) return true;
      _safeSetState(
        () => _wirelessStatus = 'New camera photo found. Importing...',
      );
      final bytes = await camera
          .downloadImage(image.handle)
          .timeout(const Duration(seconds: 60));
      if (!_wirelessActive(generation)) return true;
      if (bytes == null || bytes.isEmpty) {
        throw const SocketException('Camera returned an empty PTP object');
      }

      final imageKey =
          'ptpip://${camera.host}:${camera.port}/${image.handle}/${Uri.encodeComponent(image.name)}';
      await _saveWirelessBytes(
        event: event,
        generation: generation,
        bytes: bytes,
        filename: image.name,
        imageKey: imageKey,
        signature: image.fingerprint,
        source: 'wireless-ptpip',
      );
      _processedWirelessIds.add(keyFor(image));
      _lastWirelessSignature = image.fingerprint;
      _wirelessImageUrl = imageKey;
    }
    _wirelessFailureCount = 0;
    return true;
  }

  Future<bool> _pollCanonCcapiCamera(EventSummary event, int generation) async {
    if (!_wirelessActive(generation)) return true;
    final camera = _canonCcapiCamera;
    if (camera == null) return false;

    final contents = await camera.pollAddedContents().timeout(
      const Duration(seconds: 5),
    );
    if (!_wirelessActive(generation)) return true;
    final fresh = contents
        .where((content) => !_processedWirelessIds.contains(content.url))
        .toList(growable: false);
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
      final bytes = await camera
          .download(content)
          .timeout(const Duration(seconds: 60));
      if (!_wirelessActive(generation)) return true;
      if (bytes == null || bytes.isEmpty) {
        throw const SocketException('Canon CCAPI returned an empty image');
      }

      await _saveWirelessBytes(
        event: event,
        generation: generation,
        bytes: bytes,
        filename: content.name,
        imageKey: content.url,
        signature: content.url,
        source: 'wireless-canon-ccapi',
      );
      _processedWirelessIds.add(content.url);
      _lastWirelessSignature = content.url;
      _wirelessImageUrl = content.url;
    }
    _wirelessFailureCount = 0;
    return true;
  }

  Future<bool> _pollUpnpCamera(EventSummary event, int generation) async {
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
      if (!_wirelessActive(generation)) return true;
      if (bytes == null || bytes.isEmpty) {
        throw const SocketException('UPnP camera returned an empty image');
      }

      await _saveWirelessBytes(
        event: event,
        generation: generation,
        bytes: bytes,
        filename: image.name,
        imageKey: image.url,
        signature: image.fingerprint,
        source: 'wireless-upnp',
      );
      _processedWirelessIds.add(image.fingerprint);
      _lastWirelessSignature = image.fingerprint;
      _wirelessImageUrl = image.url;
    }
    _wirelessFailureCount = 0;
    return true;
  }

  Future<void> _pollWirelessCamera(EventSummary event, int generation) async {
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
      if (await _pollPtpIpCamera(event, generation)) {
        return;
      }
      if (await _pollCanonCcapiCamera(event, generation)) {
        return;
      }
      if (await _pollUpnpCamera(event, generation)) {
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

        final recentLinks = imageLinks.length <= 500
            ? imageLinks
            : imageLinks.sublist(imageLinks.length - 500);
        final freshLinks = recentLinks
            .where((url) => !_processedWirelessIds.contains(url))
            .toList(growable: false);
        if (freshLinks.isEmpty) {
          _safeSetState(() => _wirelessStatus = 'No new image yet');
          return;
        }

        for (final url in freshLinks) {
          if (!_wirelessActive(generation)) return;
          final bytes = await _downloadImageBytes(url);
          if (!_wirelessActive(generation)) return;
          if (bytes == null) continue;
          final signature = _signatureForBytes(bytes);
          _safeSetState(
            () => _wirelessStatus = 'New camera image found. Importing...',
          );
          await _saveWirelessBytes(
            event: event,
            generation: generation,
            bytes: bytes,
            filename: _filenameFromUrl(url),
            imageKey: url,
            signature: signature,
            source: 'wireless-http',
          );
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
        event: event,
        generation: generation,
        bytes: bytes,
        filename: _filenameFromUrl(imageUrl),
        imageKey: imageUrl,
        signature: signature,
        source: 'wireless-http',
      );
      _lastWirelessSignature = signature;
      _wirelessFailureCount = 0;
    } catch (_) {
      if (!_wirelessActive(generation)) return;
      _safeSetState(() {
        _wirelessFailureCount += 1;
        _wirelessStatus = _wirelessFailureCount >= 3
            ? 'Wireless import unstable. Keeping session, retrying automatically.'
            : 'Wireless import failed. Check camera Wi-Fi and internet.';
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

  Future<void> _pollOtgSource(EventSummary event, int generation) async {
    if (!_otgActive(generation) || _otgBusy) return;

    _safeSetState(() {
      _otgBusy = true;
      _otgStatus = 'Checking OTG source...';
    });

    try {
      if (_otgNativeCameraMode) {
        final cameraImages = await OtgFilePicker.connectedCameraImages(
          limit: 500,
        );
        if (!_otgActive(generation)) return;
        if (cameraImages.isEmpty) {
          if (mounted) {
            _safeSetState(() {
              _otgStatus =
                  'USB camera session active. Waiting for camera/photos...';
            });
          }
          return;
        }

        final fresh = cameraImages
            .where((image) => !_processedOtgIds.contains(image.id))
            .toList();
        if (fresh.isEmpty) {
          if (mounted) {
            _safeSetState(() {
              _otgStatus = 'USB camera connected. Waiting for new photos...';
            });
          }
          return;
        }

        // Native results are newest-first; upload older unseen shots first.
        for (final image in fresh.reversed) {
          if (!mounted) return;
          _safeSetState(() {
            _otgStatus = 'Importing ${image.name} from connected camera...';
          });
          final imported = await OtgFilePicker.importConnectedCameraImages([
            image.id,
          ]);
          if (!_otgActive(generation)) return;
          if (imported.isEmpty) continue;
          for (final file in imported) {
            final uploaded = await UploadQueueService.importFileLocalFirst(
              event: event,
              path: file.path,
              filename: file.name,
              isEnhanced: _isEnhanced,
              albumId: _selectedAlbumId,
              source: 'otg-ptp',
              fingerprint: '${event.id}|otg-ptp|${file.id ?? image.id}',
              tryUploadNow: true,
            );
            if (!_otgActive(generation)) return;
            try {
              await File(file.path).delete();
            } catch (_) {}
            if (!mounted) return;
            _safeSetState(() {
              _otgStatus = uploaded
                  ? 'Uploaded ${file.name} from camera'
                  : 'Saved ${file.name}. Upload queued.';
            });
          }
          _processedOtgIds.add(image.id);
        }
        return;
      }

      final images = await OtgFilePicker.recentSourceImages(
        excludeIds: _processedOtgIds.toList(),
      );
      if (!_otgActive(generation)) return;

      if (images.isEmpty) {
        _safeSetState(() {
          _otgStatus = _otgSourceName == null
              ? 'Waiting for OTG source...'
              : 'Waiting for new images in $_otgSourceName...';
        });
        return;
      }

      for (final image in images.reversed) {
        if (!_otgActive(generation)) return;
        if (_processedOtgIds.contains(image.id)) continue;

        _safeSetState(() => _otgStatus = 'Importing ${image.name} from OTG...');
        final uploaded = await _uploadOrQueueFile(
          event: event,
          path: image.path,
          filename: image.name,
          source: 'otg',
        );
        _processedOtgIds.add(image.id);

        if (!mounted) return;
        _safeSetState(() {
          _otgStatus = uploaded
              ? 'Uploaded ${image.name} from OTG'
              : 'Saved ${image.name} from OTG. Upload queued.';
        });
      }
    } on MissingPluginException {
      if (_otgActive(generation)) {
        _safeSetState(
          () => _otgStatus = 'Restart app once to enable OTG auto-upload',
        );
      }
    } catch (_) {
      if (_otgActive(generation)) {
        _safeSetState(() {
          _otgStatus =
              'OTG auto-upload failed. Reconnect source, keep app open.';
        });
      }
    } finally {
      if (_otgActive(generation)) {
        _safeSetState(() => _otgBusy = false);
      }
    }
  }

  Future<void> _startOtgAutoImport(EventSummary event) async {
    final generation = ++_otgGeneration;
    try {
      List<ConnectedCameraDevice> devices = const [];
      List<ConnectedCameraImage> connected = const [];
      try {
        devices = await OtgFilePicker.connectedCameraDevices();
        if (devices.isNotEmpty) {
          connected = await OtgFilePicker.connectedCameraImages(limit: 500);
          if (!_otgActive(generation)) return;
          // Permission may have just been granted; probe the transport again.
          devices = await OtgFilePicker.connectedCameraDevices();
        }
        if (!_otgActive(generation)) return;
      } on PlatformException catch (error) {
        if (error.code == 'USB_PERMISSION_DENIED') rethrow;
      } on MissingPluginException {
        devices = const [];
        connected = const [];
      }

      final directDevices = devices
          .where((device) => device.directSupported)
          .toList(growable: false);
      if (directDevices.isNotEmpty) {
        _otgTimer?.cancel();
        _processedOtgIds
          ..clear()
          ..addAll(connected.map((image) => image.id));
        final cameraLabel = directDevices.length == 1
            ? directDevices.first.name
            : '${directDevices.length} USB/PTP cameras';
        _safeSetState(() {
          _otgNativeCameraMode = true;
          _otgImporting = true;
          _otgSourceName = cameraLabel;
          _otgStatus = connected.isEmpty
              ? '$cameraLabel connected. Waiting for first photo...'
              : '$cameraLabel connected. Existing photos skipped; new photos will auto-upload.';
        });
        _otgTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
          if (!_otgActive(generation)) {
            timer.cancel();
            return;
          }
          unawaited(_pollOtgSource(event, generation));
        });
        return;
      }

      final source = await OtgFilePicker.pickSource();
      if (!_otgActive(generation)) return;
      if (source == null) {
        _safeSetState(() => _otgStatus = 'OTG source selection cancelled');
        return;
      }

      _otgTimer?.cancel();
      _processedOtgIds.clear();
      _safeSetState(() {
        _otgNativeCameraMode = false;
        _otgImporting = true;
        _otgSourceName = source.name;
        _otgStatus =
            'OTG source ${source.name} connected. Waiting for images...';
      });

      _otgTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
        if (!_otgActive(generation)) {
          timer.cancel();
          return;
        }
        unawaited(_pollOtgSource(event, generation));
      });
      await _pollOtgSource(event, generation);
    } on MissingPluginException {
      _safeSetState(
        () => _otgStatus = 'Restart app once to enable OTG auto-upload',
      );
      AppToast.error('Restart app once to enable OTG auto-upload');
    } on PlatformException catch (error) {
      final message = error.message?.trim();
      final readable = switch (error.code) {
        'NO_FOLDER_PICKER' =>
          'No direct USB camera detected. This phone cannot watch an OTG folder automatically; connect the camera in PTP/MTP mode, or use USB / OTG camera above to select photos manually.',
        'NO_OTG_SOURCE' =>
          'No OTG source found. Connect camera/storage in file transfer mode',
        _ =>
          message?.isNotEmpty == true
              ? message!
              : 'Failed to open source folder picker',
      };
      _safeSetState(() => _otgStatus = readable);
      AppToast.error(readable);
    } catch (_) {
      _safeSetState(() => _otgStatus = 'Failed to start OTG auto-upload');
      AppToast.error('Failed to start OTG auto-upload');
    }
  }

  void _stopOtgAutoImport() {
    _otgGeneration += 1;
    _otgTimer?.cancel();
    _otgTimer = null;
    _safeSetState(() {
      _otgImporting = false;
      _otgBusy = false;
      _otgNativeCameraMode = false;
      _otgSourceName = null;
      _otgStatus = 'OTG auto-upload stopped';
    });
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

  void _stopWirelessImport() {
    _wirelessGeneration += 1;
    _wirelessTimer?.cancel();
    _wirelessTimer = null;
    final ptpCamera = _ptpIpCamera;
    _ptpIpCamera = null;
    _canonCcapiCamera = null;
    _upnpCameraMedia = null;
    _processedWirelessIds.clear();
    if (ptpCamera != null) {
      unawaited(ptpCamera.close());
    }
    _safeSetState(() {
      _autoImporting = false;
      _wirelessScanning = false;
      _wirelessBusy = false;
      _wirelessFailureCount = 0;
      _wirelessMode = null;
      _wirelessSourceUrl = null;
      _wirelessImageUrl = null;
      _wirelessUsesListing = false;
      _lastWirelessSignature = null;
      _wirelessStatus = 'Wireless camera disconnected';
    });
  }

  Future<void> _togglePhoneAutoUpload(EventSummary event) async {
    if (_galleryImporting) {
      _stopGalleryAutoImport();
      return;
    }
    if (_otgImporting) _stopOtgAutoImport();
    if (_wirelessImporting) _stopWirelessImport();
    await _startGalleryAutoImport(event);
  }

  Future<void> _toggleOtgAutoUpload(EventSummary event) async {
    if (_otgImporting) {
      _stopOtgAutoImport();
      return;
    }
    if (_galleryImporting) _stopGalleryAutoImport();
    if (_wirelessImporting) _stopWirelessImport();
    await _startOtgAutoImport(event);
  }

  Future<void> _toggleWirelessAutoUpload(EventSummary event) async {
    if (_wirelessImporting) {
      _stopWirelessImport();
      return;
    }
    if (_galleryImporting) _stopGalleryAutoImport();
    if (_otgImporting) _stopOtgAutoImport();
    await _handleWirelessAction(event);
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
                title: const Text('Same Wi-Fi network'),
                subtitle: const Text(
                  'Use when phone + camera are on the same router. Uploads can go online immediately.',
                ),
                onTap: () => Navigator.of(
                  context,
                ).pop(_WirelessImportMode.sharedNetwork),
              ),
              ListTile(
                leading: const Icon(Icons.wifi_tethering_outlined),
                title: const Text('Camera Wi-Fi / hotspot'),
                subtitle: const Text(
                  'Use when the phone connects directly to the camera Wi-Fi. Photos save locally and upload when internet returns.',
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
    await _findAndStartWirelessImport(event, choice);
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // ── Active event ──
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
                    decoration: const InputDecoration(
                      labelText: 'Upload album',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
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
                    onChanged: _uploading
                        ? null
                        : (value) =>
                              _safeSetState(() => _selectedAlbumId = value),
                  ),
                ),

              const SizedBox(height: 8),

              // ── Add photos once ──
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
                      title: 'USB / OTG camera',
                      subtitle:
                          'Connect a camera by cable and select photos from it.',
                      onTap: _uploading || _otgBusy ? null : _pickOtgFiles,
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

              // ── Automatic external-camera upload ──
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
                            'Start one camera connection. Existing camera photos are skipped; every new shot is imported automatically and sent to the backend.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    _autoUploadTile(
                      icon: Icons.usb_outlined,
                      title: 'USB / OTG camera',
                      subtitle:
                          'Cable connection using direct PTP/MTP first. No phone-gallery step.',
                      flowText: 'Camera → app private cache → backend',
                      active: _otgImporting,
                      busy: _otgBusy,
                      status: _otgStatus,
                      onPressed: activeEvent == null || _uploading
                          ? null
                          : () => _toggleOtgAutoUpload(activeEvent),
                    ),
                    _autoUploadTile(
                      icon: Icons.wifi_tethering,
                      title: 'Wireless camera',
                      subtitle:
                          'Camera Wi-Fi / PTP-IP / supported network camera protocol.',
                      flowText: 'Camera → app → backend (or queue if offline)',
                      active: _wirelessImporting,
                      busy: _wirelessBusy || _wirelessScanning,
                      status: _wirelessStatus,
                      onPressed: activeEvent == null || _uploading
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
                          onPressed: activeEvent == null || _uploading
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
              if (_selectedFiles.isNotEmpty) ...[
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

              if (_uploadStatus != null) ...[
                const SizedBox(height: 6),
                _statusText(_uploadStatus!),
              ],

              const SizedBox(height: 14),

              // ── Upload button ──
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

  Widget _uploadSourceTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return ListTile(
      enabled: onTap != null,
      dense: true,
      leading: Icon(icon, size: 22),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, size: 20),
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
    VoidCallback? secondaryAction,
  }) {
    final actionText = active
        ? 'Stop auto-upload'
        : busy
        ? 'Connecting…'
        : 'Start auto-upload';

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
