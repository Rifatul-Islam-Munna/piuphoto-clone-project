import 'package:flutter/material.dart';

class PtpIpCameraAddress {
  const PtpIpCameraAddress(this.host, this.port);
  final String host;
  final int port;

  static PtpIpCameraAddress? parse(String input) {
    final uri = Uri.tryParse('ptpip://${input.trim()}');
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.path.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment)
      return null;
    final int port;
    try {
      // A custom URI scheme normalizes an explicit :0 to its default port.
      // Preserve the user's numeric suffix so invalid port zero is rejected.
      final explicitPort = RegExp(r':([0-9]+)$').firstMatch(input.trim());
      port = explicitPort == null ? 15740 : int.tryParse(explicitPort[1]!) ?? 0;
    } on FormatException {
      return null;
    }
    if (port < 1 || port > 65535) return null;
    return PtpIpCameraAddress(uri.host, port);
  }
}

class PtpIpSetupDialog extends StatefulWidget {
  const PtpIpSetupDialog({super.key, this.initialAddress = ''});
  final String initialAddress;

  @override
  State<PtpIpSetupDialog> createState() => _PtpIpSetupDialogState();
}

class _PtpIpSetupDialogState extends State<PtpIpSetupDialog> {
  late final _address = TextEditingController(text: widget.initialAddress);
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nikon Wi-Fi camera'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enable camera Wi-Fi, then join its network on this phone. '
              'Use a model that allows shooting while connected. SnapBridge-only '
              'pairing is not supported. Keep AirPix open; photos queue offline.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _address,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Camera address',
                hintText: '192.168.1.1',
              ),
              validator: (value) =>
                  PtpIpCameraAddress.parse(value ?? '') == null
                  ? 'Enter a camera IP or host, optionally followed by :port.'
                  : null,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate())
            Navigator.pop(context, _address.text.trim());
        },
        child: const Text('Connect & start'),
      ),
    ],
  );
}
