/// What the Android USB host sees, before AirPix tries any camera protocol.
/// An attached USB accessory is not proof that it is a PTP camera.
class UsbAttachedDeviceDiagnostic {
  const UsbAttachedDeviceDiagnostic({
    required this.id,
    required this.name,
    required this.category,
    required this.vendorId,
    required this.productId,
    required this.usbClass,
    required this.interfaceClasses,
    required this.hasPermission,
    required this.cameraCandidate,
  });

  final String id;
  final String name;
  final String category;
  final int vendorId;
  final int productId;
  final int usbClass;
  final List<int> interfaceClasses;
  final bool hasPermission;
  final bool cameraCandidate;

  factory UsbAttachedDeviceDiagnostic.fromMap(Map<dynamic, dynamic> data) =>
      UsbAttachedDeviceDiagnostic(
        id: data['id']?.toString() ?? '',
        name: data['name']?.toString() ?? 'USB device',
        category: data['category']?.toString() ?? 'Unknown USB accessory',
        vendorId: (data['vendorId'] as num?)?.toInt() ?? 0,
        productId: (data['productId'] as num?)?.toInt() ?? 0,
        usbClass: (data['usbClass'] as num?)?.toInt() ?? 0,
        interfaceClasses: (data['interfaceClasses'] as List<dynamic>? ?? [])
            .whereType<num>()
            .map((value) => value.toInt())
            .toList(growable: false),
        hasPermission: data['hasPermission'] == true,
        cameraCandidate: data['cameraCandidate'] == true,
      );

  String get usbIdentifier =>
      'VID ${vendorId.toRadixString(16).padLeft(4, '0').toUpperCase()} · '
      'PID ${productId.toRadixString(16).padLeft(4, '0').toUpperCase()}';
}

class UsbCameraDeviceDiagnostic {
  const UsbCameraDeviceDiagnostic({
    required this.name,
    required this.sessionOpen,
    required this.catalogReady,
    required this.catalogProgress,
    required this.imageCount,
    this.sessionError = '',
    this.transportType = '',
    this.usbVendorId = 0,
    this.usbProductId = 0,
    this.wiredConfirmed = false,
  });

  final String name;
  final bool sessionOpen;
  final bool catalogReady;
  final int catalogProgress;
  final int imageCount;
  final String sessionError;
  final String transportType;
  final int usbVendorId;
  final int usbProductId;
  final bool wiredConfirmed;

  factory UsbCameraDeviceDiagnostic.fromMap(Map<dynamic, dynamic> data) =>
      UsbCameraDeviceDiagnostic(
        name: data['name']?.toString() ?? 'Camera',
        sessionOpen: data['sessionOpen'] == true,
        catalogReady: data['catalogReady'] == true,
        catalogProgress: (data['catalogProgress'] as num?)?.toInt() ?? 0,
        imageCount: (data['imageCount'] as num?)?.toInt() ?? 0,
        sessionError: data['sessionError']?.toString() ?? '',
        transportType: data['transportType']?.toString() ?? '',
        usbVendorId: (data['usbVendorId'] as num?)?.toInt() ?? 0,
        usbProductId: (data['usbProductId'] as num?)?.toInt() ?? 0,
        wiredConfirmed: data['wiredConfirmed'] == true,
      );
}

class UsbCameraDiagnostics {
  const UsbCameraDiagnostics({
    required this.status,
    required this.message,
    required this.cameras,
    required this.totalImages,
    this.usbEnumerationAvailable = false,
    this.usbHostSupported,
    this.usbDevices = const [],
    this.connectionNote = '',
  });

  final String status;
  final String message;
  final List<UsbCameraDeviceDiagnostic> cameras;
  final int totalImages;

  /// Android can inspect all USB peripherals. iOS only exposes compatible cameras.
  final bool usbEnumerationAvailable;
  final bool? usbHostSupported;
  final List<UsbAttachedDeviceDiagnostic> usbDevices;
  final String connectionNote;

  bool get canImport => status == 'ready' && totalImages > 0;

  factory UsbCameraDiagnostics.fromMap(Map<dynamic, dynamic> data) =>
      UsbCameraDiagnostics(
        status: data['status']?.toString() ?? 'unknown',
        message: data['message']?.toString() ?? 'Camera status unavailable',
        cameras: (data['cameras'] as List<dynamic>? ?? [])
            .whereType<Map<dynamic, dynamic>>()
            .map(UsbCameraDeviceDiagnostic.fromMap)
            .toList(growable: false),
        totalImages: (data['totalImages'] as num?)?.toInt() ?? 0,
        usbEnumerationAvailable: data['usbEnumerationAvailable'] == true,
        usbHostSupported: data['usbHostSupported'] is bool
            ? data['usbHostSupported'] as bool
            : null,
        usbDevices: (data['usbDevices'] as List<dynamic>? ?? [])
            .whereType<Map<dynamic, dynamic>>()
            .map(UsbAttachedDeviceDiagnostic.fromMap)
            .toList(growable: false),
        connectionNote: data['connectionNote']?.toString() ?? '',
      );

  String toSupportReport() {
    final buffer = StringBuffer()
      ..writeln('AirPix wired camera diagnostics')
      ..writeln('Status: $status')
      ..writeln('Message: $message')
      ..writeln('Image count: $totalImages')
      ..writeln('Can enumerate all USB accessories: $usbEnumerationAvailable')
      ..writeln(
        'USB host supported: ${usbHostSupported ?? "Unavailable on iOS"}',
      )
      ..writeln('Attached USB device count: ${usbDevices.length}')
      ..writeln('USB visibility note: $connectionNote');
    for (final device in usbDevices) {
      buffer
        ..writeln('Attached USB: ${device.name}')
        ..writeln('Category: ${device.category}')
        ..writeln('Device ID: ${device.id}')
        ..writeln('Identifiers: ${device.usbIdentifier}')
        ..writeln('USB class: ${device.usbClass}')
        ..writeln('Interface classes: ${device.interfaceClasses.join(", ")}')
        ..writeln('USB permission: ${device.hasPermission}')
        ..writeln('Possible camera: ${device.cameraCandidate}');
    }
    for (final camera in cameras) {
      buffer
        ..writeln('Camera: ${camera.name}')
        ..writeln('USB session open: ${camera.sessionOpen}')
        ..writeln('Catalog ready: ${camera.catalogReady}')
        ..writeln('Catalog progress: ${camera.catalogProgress}%')
        ..writeln('Readable images: ${camera.imageCount}')
        ..writeln(
          'Session error: ${camera.sessionError.isEmpty ? "None" : camera.sessionError}',
        )
        ..writeln('Camera transport: ${camera.transportType}')
        ..writeln('Confirmed wired USB camera: ${camera.wiredConfirmed}')
        ..writeln('Camera USB VID: ${camera.usbVendorId}')
        ..writeln('Camera USB PID: ${camera.usbProductId}');
    }
    return buffer.toString();
  }
}
