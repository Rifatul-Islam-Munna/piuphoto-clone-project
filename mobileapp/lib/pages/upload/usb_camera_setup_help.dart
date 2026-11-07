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
          const Text(
            '1. On the camera, choose USB remote control / tethered shooting. '
            'It may be called Remote Shooting, PC Remote, or PC(Tether). '
            'Find your brand below for the exact setting.',
          ),
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
            'AirPix checks for new photos every second (up to 5 seconds '
            'for large cards), even without '
            'a shutter event. The camera must expose photos through its '
            'shooting-capable PTP/tether protocol. Ordinary PTP/MTP file '
            'transfer alone does not guarantee that the shutter stays usable.',
          ),
          const SizedBox(height: 10),
          const Text(
            'If the tether driver fails while the camera is still shootable, '
            'open USB / OTG options and enable Compatibility photo reader. '
            'This reads the available PTP/MTP catalog in the same USB mode, '
            'without vendor-control commands. It listens for new-photo events '
            'on iPhone and checks the catalog every 3 seconds. Some shooting '
            'modes expose only a vendor queue and will need the tether driver. '
            'Wait for ready, then take a test shot; no photo catalog can '
            'guarantee the camera controls remain usable.',
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
            'when internet is unavailable. After confirmed cloud upload, the '
            'temporary phone copy is deleted automatically. Camera-card '
            'originals are kept. Check upload progress separately.',
          ),
          const SizedBox(height: 10),
          const Text(
            'No automatic storage-mode fallback',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'If setup fails, AirPix stops receiving and shows setup guidance. '
            'It never selects Mass Storage, Card Reader or USB Streaming. '
            'If the camera screen or shutter becomes unavailable, tap Stop '
            'session, unplug USB, then check the camera setting before retrying. '
            'The camera controls its USB mode and display; compatibility '
            'depends on the model and firmware.',
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
      'Select PC(Tether) and keep a writable memory card inserted. AirPix '
          'checks the LUMIX tether capabilities and confirms SD or SD + PC '
          'recording without changing that setting. New card photos are '
          'checked about every second, even without photo notifications. '
          'PC(Storage) and unsupported tether modes are rejected.',
    ),
    (
      'Olympus / OM SYSTEM',
      'RAW/Control or camera-to-computer control icon',
      'Select RAW/Control (the camera-to-computer control icon on some '
          'models) and camera-card recording. AirPix verifies the OM-D '
          'protocol, opens its PC connection when permitted, and restores '
          'the previous connection mode on Stop. It does not change shooting '
          'settings or start live view. New card photos are checked about '
          'every second. Model and firmware testing is still required.',
    ),
    (
      'Pentax / Ricoh',
      'Limited: physical-shutter capability required',
      'Live receiving is available only when the phone explicitly confirms '
          'physical-shutter support on this connection. PTP/MTP file access '
          'or a desktop tethering app does not confirm iPhone support. '
          'The Pentax SCSI protocol requires Mass Storage and is not used. '
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
      'Sony Alpha 7R IV (ILCE-7RM4)',
      'PC Remote Function > USB',
      'Unplug USB. MENU > Network > Ctrl w/ Smartphone > Off. '
          'Open Network > PC Remote Function: set PC Remote to On, '
          'PC Remote Cnct Method to USB, and Still Img. Save Dest. to '
          'PC+Camera. Use Camera priority where available, keep a writable '
          'card inserted, then reconnect and choose New shots only in AirPix. '
          'This model uses PC Remote Function, unlike the Alpha 7 IV menu. '
          'For quicker JPEG transfer, you can choose JPEG Only for RAW+J PC '
          'Save Img and 2M for PC Save Image Size; 2M reduces upload resolution.',
    ),
    (
      'Sony Alpha 7 IV (ILCE-7M4)',
      'Remote Shooting (NOT Mass Storage)',
      'Unplug the cable first. MENU > Setup > USB > USB Connection Mode > '
          'Remote Shooting (or Sel. When Connect, then Remote Shooting). '
          'MENU > Network > Cnct./Remote Sht. > Remote Shoot Setting > '
          'Still Img. Save Dest. > Dest.+Camera. Set PC Remote priority to '
          'Camera where available. AirPix checks these settings without '
          'changing them. Keep a writable card in '
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
