import 'package:flutter/services.dart';
import 'package:mobileapp/core/platform/otg_file_picker.dart';

/// A native transport owns one USB/PTP session. Vendor protocols live above this
/// boundary; Android MtpDevice and raw USB must never own the same interface.
abstract interface class PtpTetherLink {
  Stream<Map<Object?, Object?>> events(String sessionId);
  Future<PtpTetherConnection> open(String sessionId);
  Future<PtpTetherResponse> command(
    String sessionId,
    int opcode, {
    List<int> params = const [],
    Uint8List? outData,
  });
  Future<OtgPickedFile> download(
    String sessionId, {
    required String transferId,
    required int handle,
    required String name,
    required int expectedSize,
    int? partialOpcode,
  });
  Future<void> acknowledge(String sessionId, List<String> ids);
  Future<void> close(String sessionId);
}

class PtpTetherConnection {
  const PtpTetherConnection({
    required this.sessionId,
    required this.cameraId,
    required this.name,
    this.vendorId = 0,
    this.productId = 0,
    this.physicalShutter = 'unknown',
  });

  final String sessionId;
  final String cameraId;
  final String name;
  final int vendorId;
  final int productId;
  final String physicalShutter;
}

class PtpTetherResponse {
  PtpTetherResponse({
    required this.responseCode,
    this.parameters = const [],
    Uint8List? data,
  }) : data = data ?? Uint8List(0);

  final int responseCode;
  final List<int> parameters;
  final Uint8List data;
  bool get succeeded => responseCode == 0x2001;
}

class MethodChannelPtpTetherLink implements PtpTetherLink {
  static const _methods = MethodChannel('airpix/otg_picker');
  static const _events = EventChannel('airpix/otg_live');

  @override
  Stream<Map<Object?, Object?>> events(String sessionId) => _events
      .receiveBroadcastStream({'sessionId': sessionId})
      .where((event) => event is Map)
      .map((event) => Map<Object?, Object?>.from(event as Map));

  @override
  Future<PtpTetherConnection> open(String sessionId) async {
    final result = await _methods.invokeMapMethod<Object?, Object?>(
      'openPtpTetherSession',
      {'sessionId': sessionId},
    );
    if (result == null || result['sessionId'] != sessionId) {
      throw PlatformException(code: 'LIVE_CAMERA_INVALID_SESSION');
    }
    return PtpTetherConnection(
      sessionId: sessionId,
      cameraId: result['cameraId']?.toString() ?? '',
      name: result['name']?.toString() ?? 'USB camera',
      vendorId: (result['vendorId'] as num?)?.toInt() ?? 0,
      productId: (result['productId'] as num?)?.toInt() ?? 0,
      physicalShutter: result['physicalShutter'] == 'supported'
          ? 'supported'
          : 'unknown',
    );
  }

  @override
  Future<PtpTetherResponse> command(
    String sessionId,
    int opcode, {
    List<int> params = const [],
    Uint8List? outData,
  }) async {
    final result = await _methods
        .invokeMapMethod<Object?, Object?>('sendPtpTetherCommand', {
          'sessionId': sessionId,
          'opcode': opcode,
          'params': params,
          'outData': ?outData,
        });
    final code = result?['responseCode'];
    final data = result?['data'];
    final parameters = result?['parameters'];
    if (code is! int ||
        code < 0x2000 ||
        code > 0xffff ||
        (data != null && data is! Uint8List) ||
        (parameters != null &&
            (parameters is! List ||
                parameters.any((value) => value is! int)))) {
      throw PlatformException(
        code: 'PTP_INVALID_RESPONSE',
        message: 'The USB transport returned an invalid camera response.',
      );
    }
    return PtpTetherResponse(
      responseCode: code,
      parameters: parameters == null
          ? const []
          : List<int>.from(parameters as List),
      data: data as Uint8List?,
    );
  }

  @override
  Future<OtgPickedFile> download(
    String sessionId, {
    required String transferId,
    required int handle,
    required String name,
    required int expectedSize,
    int? partialOpcode,
  }) async {
    final result = await _methods
        .invokeMapMethod<Object?, Object?>('downloadPtpTetherObject', {
          'sessionId': sessionId,
          'transferId': transferId,
          'handle': handle,
          'name': name,
          'expectedSize': expectedSize,
          'partialOpcode': ?partialOpcode,
        });
    final path = result?['path']?.toString() ?? '';
    final returnedSize = (result?['size'] as num?)?.toInt();
    if (path.isEmpty || returnedSize != expectedSize || expectedSize <= 0) {
      throw PlatformException(
        code: 'CAMERA_IMPORT_FAILED',
        message: 'The camera did not provide the complete photo.',
      );
    }
    return OtgPickedFile(path: path, name: name, id: transferId);
  }

  @override
  Future<void> acknowledge(String sessionId, List<String> ids) =>
      _methods.invokeMethod<void>('acknowledgePtpTetherFiles', {
        'sessionId': sessionId,
        'ids': ids,
      });

  @override
  Future<void> close(String sessionId) => _methods.invokeMethod<void>(
    'closePtpTetherSession',
    {'sessionId': sessionId},
  );
}
