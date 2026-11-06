import 'package:flutter/material.dart';

class CanonWirelessSettings {
  const CanonWirelessSettings({
    required this.origin,
    required this.username,
    required this.password,
  });
  final Uri origin;
  final String username;
  final String password;
}

/// Accept the camera's displayed CCAPI address, never a guessed control URL.
Uri parseCanonWirelessAddress(String input) {
  final text = input.trim();
  final uri = Uri.tryParse(text.contains('://') ? text : 'http://$text');
  if (uri == null ||
      !const ['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.port < 1 ||
      uri.port > 65535 ||
      !const ['', '/', '/ccapi', '/ccapi/'].contains(uri.path)) {
    throw const FormatException(
      'Enter the camera CCAPI address and port, for example http://192.168.1.10:8080.',
    );
  }
  return uri.replace(path: '/', query: null, fragment: null);
}

class CanonWirelessSetupDialog extends StatefulWidget {
  const CanonWirelessSetupDialog({
    super.key,
    this.initialAddress = '',
    this.cameraHotspot = false,
  });
  final String initialAddress;
  final bool cameraHotspot;

  @override
  State<CanonWirelessSetupDialog> createState() =>
      _CanonWirelessSetupDialogState();
}

class _CanonWirelessSetupDialogState extends State<CanonWirelessSetupDialog> {
  final _form = GlobalKey<FormState>();
  late final _address = TextEditingController(text: widget.initialAddress);
  final _username = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _address.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Canon CCAPI setup'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'For Canon models with Camera Control API enabled. '
                'Some models require Canon\'s one-time CCAPI activation.',
              ),
              const SizedBox(height: 12),
              Text(
                widget.cameraHotspot
                    ? '1. Enable Camera Control API on the camera and join its Wi-Fi network on this phone.'
                    : '1. Enable Camera Control API on the camera. Join the same Wi-Fi network on the camera and phone.',
              ),
              const Text(
                '2. Copy the HTTP or HTTPS address and port shown in the camera CCAPI settings.',
              ),
              const Text(
                '3. Allow Local Network access if asked. Return the camera to shooting, then press its physical shutter.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                decoration: const InputDecoration(
                  labelText: 'Camera CCAPI address',
                  hintText: 'http://192.168.1.10:8080',
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
                validator: (value) {
                  try {
                    parseCanonWirelessAddress(value ?? '');
                    return null;
                  } on FormatException catch (error) {
                    return error.message;
                  }
                },
              ),
              TextFormField(
                controller: _username,
                decoration: const InputDecoration(
                  labelText: 'Camera username (if enabled)',
                ),
                autocorrect: false,
              ),
              TextFormField(
                controller: _password,
                decoration: const InputDecoration(
                  labelText: 'Camera password (if enabled)',
                ),
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
              ),
              const SizedBox(height: 12),
              const Text(
                'AirPix reads photo events and image files only. '
                'It does not start live view, press the shutter, change shooting settings, '
                'or switch to a file-transfer connection. If the camera cannot shoot '
                'in this mode, stop and use camera FTP auto-send if supported.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Keep AirPix open. A camera hotspot may have no internet; '
                'received photos stay queued until internet returns. '
                'Use trusted Wi-Fi. Passwords are kept only for this connection.',
              ),
            ],
          ),
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
          if (_form.currentState!.validate()) {
            Navigator.pop(
              context,
              CanonWirelessSettings(
                origin: parseCanonWirelessAddress(_address.text),
                username: _username.text.trim(),
                password: _password.text,
              ),
            );
          }
        },
        child: const Text('Connect'),
      ),
    ],
  );
}
