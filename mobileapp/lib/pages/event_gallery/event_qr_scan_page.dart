import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mobileapp/pages/event_gallery/event_gallery_page.dart';
import 'package:mobileapp/utilities/app_toast.dart';

class EventQrScanPage extends StatefulWidget {
  const EventQrScanPage({super.key});

  @override
  State<EventQrScanPage> createState() => _EventQrScanPageState();
}

class _EventQrScanPageState extends State<EventQrScanPage> {
  bool _handled = false;

  String? _extractEventId(String raw) {
    final text = raw.trim();
    final mobileMatch = RegExp(
      r'mobile\s*:\s*([a-fA-F0-9]{24})',
      caseSensitive: false,
    ).firstMatch(text);
    if (mobileMatch != null) return mobileMatch.group(1);

    final objectIdMatch = RegExp(r'[a-fA-F0-9]{24}').firstMatch(text);
    return objectIdMatch?.group(0);
  }

  void _handleCode(String raw) {
    if (_handled) return;
    final eventId = _extractEventId(raw);
    if (eventId == null) {
      AppToast.error('QR code does not include event id');
      return;
    }

    _handled = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => EventGalleryPage(eventId: eventId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR Code')),
      body: MobileScanner(
        onDetect: (capture) {
          final value = capture.barcodes.isEmpty
              ? null
              : capture.barcodes.first.rawValue;
          if (value != null) {
            _handleCode(value);
          }
        },
      ),
    );
  }
}
