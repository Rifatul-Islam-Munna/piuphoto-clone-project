class UsbCameraDeviceDiagnostic {
  const UsbCameraDeviceDiagnostic({
    required this.name,
    required this.sessionOpen,
    required this.catalogReady,
    required this.catalogProgress,
    required this.imageCount,
  });

  final String name;
  final bool sessionOpen;
  final bool catalogReady;
  final int catalogProgress;
  final int imageCount;

  factory UsbCameraDeviceDiagnostic.fromMap(Map<dynamic, dynamic> data) =>
      UsbCameraDeviceDiagnostic(
        name: data['name']?.toString() ?? 'Camera',
        sessionOpen: data['sessionOpen'] == true,
        catalogReady: data['catalogReady'] == true,
        catalogProgress: (data['catalogProgress'] as num?)?.toInt() ?? 0,
        imageCount: (data['imageCount'] as num?)?.toInt() ?? 0,
      );
}

class UsbCameraDiagnostics {
  const UsbCameraDiagnostics({
    required this.status,
    required this.message,
    required this.cameras,
    required this.totalImages,
  });

  final String status;
  final String message;
  final List<UsbCameraDeviceDiagnostic> cameras;
  final int totalImages;

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
      );

  String toSupportReport() {
    final buffer = StringBuffer()
      ..writeln('AirPix wired camera diagnostics')
      ..writeln('Status: $status')
      ..writeln('Message: $message')
      ..writeln('Image count: $totalImages');
    for (final camera in cameras) {
      buffer
        ..writeln('Camera: ${camera.name}')
        ..writeln('USB session open: ${camera.sessionOpen}')
        ..writeln('Catalog ready: ${camera.catalogReady}')
        ..writeln('Catalog progress: ${camera.catalogProgress}%')
        ..writeln('Readable images: ${camera.imageCount}');
    }
    return buffer.toString();
  }
}
