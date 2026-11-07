import 'package:flutter/material.dart';

/// iPhone defaults to the camera photo catalog; advanced vendor PTP is opt-in.
/// Android keeps its existing vendor tether default.
class UsbCameraReaderSelector extends StatelessWidget {
  const UsbCameraReaderSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  static const explanation =
      'Uses the camera photo catalog (the earlier iPhone connection path), '
      'without requiring a raw vendor PTP handshake. It does not change USB '
      'mode, activate the shutter, or guarantee the physical shutter works. '
      'Take a test shot. If a PC Remote camera exposes new photos only through '
      'its vendor transfer queue, turn this off to try Advanced vendor tether.';

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    title: const Text('Camera photo reader (recommended on iPhone)'),
    subtitle: const Text(explanation),
    value: value,
    onChanged: onChanged,
  );
}
