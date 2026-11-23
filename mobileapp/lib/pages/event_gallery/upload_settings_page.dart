import 'package:flutter/material.dart';
import 'package:mobileapp/core/platform/live_camera_types.dart';
import 'package:mobileapp/core/storage/usb_camera_upload_mode_storage.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/pages/upload/usb_camera_upload_mode_selector.dart';
import 'package:mobileapp/utilities/app_toast.dart';

class UploadSettingsPage extends StatefulWidget {
  const UploadSettingsPage({super.key});

  @override
  State<UploadSettingsPage> createState() => _UploadSettingsPageState();
}

class _UploadSettingsPageState extends State<UploadSettingsPage> {
  late LiveCameraUploadMode _mode = UsbCameraUploadModeStorage.read();
  bool _saving = false;

  Future<void> _changeMode(LiveCameraUploadMode mode) async {
    if (_saving || mode == _mode) return;
    final previous = _mode;
    setState(() {
      _mode = mode;
      _saving = true;
    });
    try {
      await UsbCameraUploadModeStorage.save(mode);
      AppToast.success('Upload settings saved');
    } catch (_) {
      if (mounted) setState(() => _mode = previous);
      AppToast.error('Could not save upload settings');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Upload settings',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          const Text(
            'CAMERA TRANSFER',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: .6,
              color: AppColors.mutedForeground,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: AppColors.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: UsbCameraUploadModeSelector(
                value: _mode,
                onChanged: _changeMode,
                isSaving: _saving,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: AppColors.accentSoft,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: AppColors.primary),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Manual uploads still let you select individual photos before sending them. This setting only controls which photos are included when you start a USB camera session.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.45,
                        color: AppColors.foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
