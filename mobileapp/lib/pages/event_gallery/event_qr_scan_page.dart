import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mobileapp/core/guest/guest_qr_payload.dart';
import 'package:mobileapp/pages/event_gallery/event_gallery_page.dart';
import 'package:mobileapp/utilities/app_toast.dart';
import 'package:permission_handler/permission_handler.dart';

enum _CameraAccess { checking, granted, denied, permanentlyDenied }

class EventQrScanPage extends StatefulWidget {
  const EventQrScanPage({super.key});

  @override
  State<EventQrScanPage> createState() => _EventQrScanPageState();
}

class _EventQrScanPageState extends State<EventQrScanPage>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
  );
  _CameraAccess _cameraAccess = _CameraAccess.checking;
  bool _handled = false;
  String? _scanError;
  DateTime? _lastInvalidScanAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshCameraPermission(request: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshCameraPermission());
    } else if (_cameraAccess == _CameraAccess.granted) {
      unawaited(_controller.stop().catchError((_) {}));
    }
  }

  Future<void> _refreshCameraPermission({bool request = false}) async {
    var status = await Permission.camera.status;
    if (request && !status.isGranted) {
      status = await Permission.camera.request();
    }
    if (!mounted) return;
    final access = status.isGranted
        ? _CameraAccess.granted
        : status.isPermanentlyDenied || status.isRestricted
        ? _CameraAccess.permanentlyDenied
        : _CameraAccess.denied;
    setState(() => _cameraAccess = access);
  }

  Future<void> _handleCapture(BarcodeCapture capture) async {
    if (_handled) return;

    GuestQrData? guestQr;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.trim().isEmpty) continue;
      guestQr = GuestQrPayload.decode(raw);
      if (guestQr != null) break;
    }

    if (guestQr == null) {
      final now = DateTime.now();
      if (_lastInvalidScanAt == null ||
          now.difference(_lastInvalidScanAt!) > const Duration(seconds: 2)) {
        _lastInvalidScanAt = now;
        if (mounted) {
          setState(() => _scanError = 'This is not an AirPix event QR.');
        }
        AppToast.error('QR code does not include a valid event');
      }
      return;
    }

    _handled = true;
    await _controller.stop();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => EventGalleryPage(
          eventId: guestQr!.eventId,
          publicAccess: true,
          faceEnrollment: guestQr.faceEnrollment,
        ),
      ),
    );
  }

  Widget _permissionBody() {
    if (_cameraAccess == _CameraAccess.checking) {
      return const Center(child: CircularProgressIndicator());
    }

    final permanentlyDenied = _cameraAccess == _CameraAccess.permanentlyDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, size: 54),
            const SizedBox(height: 16),
            Text(
              permanentlyDenied
                  ? 'Camera permission is turned off'
                  : 'Camera permission is required',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Allow camera access so AirPix can scan the guest event QR.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: permanentlyDenied
                  ? () async {
                      await openAppSettings();
                    }
                  : () => _refreshCameraPermission(request: true),
              icon: Icon(
                permanentlyDenied ? Icons.settings_outlined : Icons.camera_alt,
              ),
              label: Text(permanentlyDenied ? 'Open settings' : 'Allow camera'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scannerBody() {
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _controller,
          fit: BoxFit.cover,
          onDetect: _handleCapture,
        ),
        IgnorePointer(
          child: Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
        Positioned(
          top: 18,
          right: 16,
          child: Row(
            children: [
              _ScannerControlButton(
                tooltip: 'Flashlight',
                icon: Icons.flashlight_on_outlined,
                onPressed: _controller.toggleTorch,
              ),
              const SizedBox(width: 10),
              _ScannerControlButton(
                tooltip: 'Switch camera',
                icon: Icons.cameraswitch_outlined,
                onPressed: _controller.switchCamera,
              ),
            ],
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 28,
          child: SafeArea(
            top: false,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _scanError == null
                    ? Colors.black.withValues(alpha: 0.72)
                    : Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _scanError ?? 'Place the AirPix guest QR inside the frame.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _scanError == null
                        ? Colors.white
                        : Theme.of(context).colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Guest QR')),
      body: _cameraAccess == _CameraAccess.granted
          ? _scannerBody()
          : _permissionBody(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller.dispose());
    super.dispose();
  }
}

class _ScannerControlButton extends StatelessWidget {
  const _ScannerControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}
