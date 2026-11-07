import 'package:flutter/material.dart';

/// Shooting-mode vendor PTP is the default on iPhone and Android.
/// The photo catalog is only an explicit compatibility/stored-file choice.
class UsbCameraReaderSelector extends StatelessWidget {
  const UsbCameraReaderSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  static const explanation =
      'OFF (recommended for live shooting): use the camera’s supported vendor '
      'tether protocol to receive new shots. ON: use ImageCaptureCore/PTP/MTP '
      'photo catalog for compatibility. Catalog access can make some cameras '
      'show a computer icon and disable the physical shutter, even though '
      'the camera is connected. Stop receiving before switching readers. '
      'Always confirm the camera screen and physical shutter work.';

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    title: const Text('Compatibility photo catalog (may lock shutter)'),
    subtitle: const Text(explanation),
    value: value,
    onChanged: onChanged,
  );
}
