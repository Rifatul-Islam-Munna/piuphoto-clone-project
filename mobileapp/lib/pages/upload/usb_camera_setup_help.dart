import 'package:flutter/material.dart';

/// Model-specific USB setup; detection alone never proves physical shooting.
class UsbCameraSetupHelpDialog extends StatelessWidget {
  const UsbCameraSetupHelpDialog({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Shoot on camera. Receive on phone.'),
    scrollable: true,
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('1. Choose the camera’s shooting USB mode below.'),
          const SizedBox(height: 10),
          const Text('2. Connect a data cable, then tap Connect & start.'),
          const SizedBox(height: 10),
          const Text(
            '3. Take a new photo with the camera’s physical shutter. Check '
            'that its screen and controls still work and the photo appears '
            'in Camera transfers.',
          ),
          const SizedBox(height: 10),
          const Text(
            'AirPix checks for new photos about once a second, even without '
            'a shutter event. The camera must expose photos through its '
            'shooting-capable PTP/tether protocol. Ordinary PTP/MTP file '
            'transfer alone does not guarantee that the shutter stays usable.',
          ),
          const SizedBox(height: 16),
          const Text(
            'Camera setup',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          for (final guide in _guides)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 12),
              title: Text(guide.$1),
              subtitle: Text(guide.$2),
              children: [
                Align(alignment: Alignment.centerLeft, child: Text(guide.$3)),
              ],
            ),
          const SizedBox(height: 12),
          const Text(
            'Keep AirPix open and the phone unlocked while shooting. Received '
            'photos enter the upload queue automatically; cloud uploads wait '
            'when internet is unavailable. Check upload progress separately.',
          ),
          const SizedBox(height: 10),
          const Text(
            'If the camera screen or shutter locks, release the connection '
            'and check its USB mode. Support depends on model and firmware; '
            'a successful connection is not a completed shooting test.',
          ),
        ],
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );

  static const _guides = <(String, String, String)>[
    (
      'Panasonic / LUMIX',
      'PC(Tether)',
      'Select the model’s PC(Tether) shooting connection, not PC(Storage), '
          'and keep a writable memory card inserted. This build has no '
          'dedicated LUMIX vendor-mode adapter yet. It can only monitor '
          'the body when iOS exposes physical-shutter support and standard '
          'PTP card-object commands in a shooting-capable mode. Otherwise '
          'use a supported camera FTP route; do not use storage mode.',
    ),
    (
      'Olympus / OM SYSTEM',
      'RAW/Control or camera-to-computer control icon',
      'Choose the shooting/control USB mode in your camera manual and '
          'insert a writable card, not Storage/MTP mode. This build does '
          'not implement OM-D vendor PC-control negotiation. Generic live '
          'PTP is used only when iOS explicitly reports physical-shutter '
          'support and standard card-object commands. An unsupported model '
          'will be rejected instead of forcing a file-transfer session.',
    ),
    (
      'Pentax / Ricoh',
      'Limited: physical-shutter capability required',
      'Live receiving is available only when the phone explicitly confirms '
          'physical-shutter support on this connection. PTP/MTP file access '
          'or a desktop tethering app does not confirm iPhone support. '
          'Otherwise use manual import for stored photos or camera FTP when '
          'available. Do not switch to Mass Storage for Live shooting.',
    ),
    (
      'Canon EOS',
      'Photo Import / Remote Control',
      'On newer Canon bodies, including EOS R6 Mark II, open Choose USB '
          'connection app and select Photo Import/Remote Control. Some '
          'older EOS bodies disable USB while camera Wi-Fi is enabled; '
          'turn camera Wi-Fi off, then reconnect. Keep a writable card '
          'inserted. Ordinary Mass Storage is not the live shooting path.',
    ),
    (
      'Nikon',
      'PTP / MTP or model-specific tether mode',
      'Many Nikon cameras have no separate USB mode selector: their normal '
          'PTP/MTP connection is correct for camera communication. AirPix '
          'must still negotiate the Nikon shooting protocol and verify '
          'the physical shutter works. Use a data cable and writable card; '
          'file-import capability alone is not proof of live shooting.',
    ),
    (
      'Sony Alpha 7 IV (ILCE-7M4)',
      'Remote Shooting (NOT Mass Storage)',
      'Unplug the cable first. MENU > Setup > USB > USB Connection Mode > '
          'Remote Shooting (or Sel. When Connect, then Remote Shooting). '
          'MENU > Network > Cnct./Remote Sht. > Remote Shoot Setting > '
          'Still Img. Save Dest. > Dest.+Camera. Keep a writable card in '
          'the camera, use a USB data cable, and choose New shots only '
          'in AirPix. Do not select Mass Storage/MTP or USB Streaming. '
          'A working camera screen and a newly transferred test shot are '
          'still required to confirm compatibility on this iPhone.',
    ),
    (
      'Other Sony Alpha models',
      'PC Remote / Remote Shooting',
      'Use the shooting-capable USB connection supported by the model. '
          'On older bodies, set PC Remote, PC+Camera recording and Camera '
          'priority where available. New shots only is supported by the '
          'current AirPix Sony adapter; stored files require manual import.',
    ),
    (
      'Fujifilm',
      'USB TETHER SHOOTING AUTO/FIXED',
      'Select New shots only. Use USB TETHER SHOOTING AUTO/FIXED '
          'with a writable card. AirPix uses read-only PTP card polling '
          'when exposed by this tether mode; otherwise it uses the '
          'camera’s supported new-photo notifications. If neither is '
          'available, the app rejects this mode. Card Reader, RAW '
          'conversion and Webcam modes cannot keep live shooting.',
    ),
  ];
}

class UsbCameraReceiveStatus extends StatelessWidget {
  const UsbCameraReceiveStatus({super.key, required this.photoReceived});

  final bool photoReceived;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        photoReceived ? Icons.photo_outlined : Icons.camera_alt_outlined,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              photoReceived
                  ? 'Photo received on phone'
                  : 'Ready for a test photo',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              photoReceived
                  ? 'Check Camera transfers for cloud upload progress. To '
                        'verify shooting, take a new photo with the camera shutter '
                        'and check that its screen and controls still work.'
                  : 'Press the camera’s physical shutter and check that the '
                        'new photo appears in Camera transfers. Keep AirPix open.',
            ),
          ],
        ),
      ),
    ],
  );
}
