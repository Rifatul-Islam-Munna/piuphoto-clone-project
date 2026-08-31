import 'package:flutter/services.dart';

class OtgPickedFile {
  const OtgPickedFile({required this.path, required this.name, this.id});

  final String path;
  final String name;
  final String? id;
}

class ConnectedCameraDevice {
  const ConnectedCameraDevice({
    required this.id,
    required this.name,
    required this.hasPermission,
    required this.directSupported,
  });

  final String id;
  final String name;
  final bool hasPermission;
  final bool directSupported;

  factory ConnectedCameraDevice.fromMap(Map<Object?, Object?> map) {
    bool asBool(Object? value) => value == true || value?.toString() == 'true';
    return ConnectedCameraDevice(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Connected camera',
      hasPermission: asBool(map['hasPermission']),
      directSupported: asBool(map['directSupported']),
    );
  }
}

class OtgSourceImage {
  const OtgSourceImage({
    required this.id,
    required this.path,
    required this.name,
  });

  final String id;
  final String path;
  final String name;

  factory OtgSourceImage.fromMap(Map<Object?, Object?> map) {
    return OtgSourceImage(
      id: map['id']?.toString() ?? '',
      path: map['path']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
    );
  }
}

class ConnectedCameraImage {
  const ConnectedCameraImage({
    required this.id,
    required this.name,
    this.size = 0,
  });

  final String id;
  final String name;
  final int size;

  factory ConnectedCameraImage.fromMap(Map<Object?, Object?> map) {
    return ConnectedCameraImage(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'camera-image.jpg',
      size: int.tryParse(map['size']?.toString() ?? '') ?? 0,
    );
  }
}

class OtgSourceSelection {
  const OtgSourceSelection({required this.id, required this.name});

  final String id;
  final String name;

  factory OtgSourceSelection.fromMap(Map<Object?, Object?> map) {
    return OtgSourceSelection(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
    );
  }
}

class OtgFilePicker {
  OtgFilePicker._();

  static const _channel = MethodChannel('piuphoto/otg_picker');

  static Future<OtgPickedFile?> pickImage() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('pickImage');
    if (result == null) return null;

    final path = result['path']?.toString();
    final name = result['name']?.toString();
    if (path == null || name == null) return null;

    return OtgPickedFile(path: path, name: name);
  }

  static Future<List<OtgPickedFile>> pickImages() async {
    final result = await _channel.invokeMethod<List<dynamic>>('pickImages');
    if (result == null) return const [];

    return result
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (item) => OtgPickedFile(
            path: item['path']?.toString() ?? '',
            name: item['name']?.toString() ?? '',
            id: item['id']?.toString(),
          ),
        )
        .where((file) => file.path.isNotEmpty && file.name.isNotEmpty)
        .toList();
  }

  static Future<List<ConnectedCameraDevice>> connectedCameraDevices() async {
    final result = await _channel.invokeListMethod<Object?>(
      'connectedCameraDevices',
    );
    return (result ?? [])
        .whereType<Map<Object?, Object?>>()
        .map(ConnectedCameraDevice.fromMap)
        .where((device) => device.id.isNotEmpty)
        .toList();
  }

  static Future<List<ConnectedCameraImage>> connectedCameraImages({
    int? limit,
  }) async {
    final arguments = <String, Object?>{};
    if (limit != null) arguments['limit'] = limit;
    final result = await _channel.invokeListMethod<Object?>(
      'connectedCameraImages',
      arguments,
    );
    return (result ?? [])
        .whereType<Map<Object?, Object?>>()
        .map(ConnectedCameraImage.fromMap)
        .where((image) => image.id.isNotEmpty)
        .toList();
  }

  static Future<List<OtgPickedFile>> importConnectedCameraImages(
    List<String> ids,
  ) async {
    final result = await _channel.invokeListMethod<Object?>(
      'importConnectedCameraImages',
      {'ids': ids},
    );
    return (result ?? [])
        .whereType<Map<Object?, Object?>>()
        .map(
          (item) => OtgPickedFile(
            path: item['path']?.toString() ?? '',
            name: item['name']?.toString() ?? '',
            id: item['id']?.toString(),
          ),
        )
        .where((file) => file.path.isNotEmpty && file.name.isNotEmpty)
        .toList();
  }

  static Future<OtgSourceSelection?> pickSource() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'pickSource',
    );
    if (result == null) return null;

    final source = OtgSourceSelection.fromMap(result);
    if (source.id.isEmpty || source.name.isEmpty) return null;
    return source;
  }

  static Future<List<OtgSourceImage>> recentSourceImages({
    required List<String> excludeIds,
  }) async {
    final result = await _channel.invokeListMethod<Object?>(
      'recentSourceImages',
      {'excludeIds': excludeIds},
    );

    return (result ?? [])
        .whereType<Map<Object?, Object?>>()
        .map(OtgSourceImage.fromMap)
        .where((image) => image.id.isNotEmpty && image.path.isNotEmpty)
        .toList();
  }
}
