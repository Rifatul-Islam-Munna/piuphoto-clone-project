import 'package:flutter/material.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/models/album_model.dart';

/// Presentation only. The original UploadPage owns all camera connections,
/// permissions, file picking, transfer queue, and automatic session navigation.
class CameraUploadSheetView extends StatefulWidget {
  const CameraUploadSheetView({
    super.key,
    required this.onStart,
    required this.onClose,
    required this.onStop,
    required this.onOpenTransfers,
    required this.onUploadSettings,
    required this.onUsbOptions,
    required this.onWirelessOptions,
    required this.onShare,
    required this.onGuestQr,
    required this.onFaceQr,
    required this.onPreview,
    required this.onClearSelected,
    required this.onUploadSelected,
    required this.onChangeAlbum,
    required this.onRetryQueue,
    required this.onFreeSpace,
    required this.eventTitle,
    required this.albums,
    required this.selectedAlbumId,
    required this.selectedFileCount,
    required this.receiving,
    required this.isBusy,
    required this.isUploading,
    required this.queueCount,
    required this.pendingReviewCount,
    this.statusMessage,
  });

  final Future<void> Function(String method) onStart;
  final VoidCallback onClose;
  final Future<void> Function() onStop;
  final VoidCallback onOpenTransfers;
  final VoidCallback onUploadSettings;
  final VoidCallback onUsbOptions;
  final VoidCallback onWirelessOptions;
  final VoidCallback onShare;
  final VoidCallback onGuestQr;
  final VoidCallback onFaceQr;
  final VoidCallback onPreview;
  final VoidCallback onClearSelected;
  final VoidCallback onUploadSelected;
  final ValueChanged<String?> onChangeAlbum;
  final VoidCallback onRetryQueue;
  final VoidCallback onFreeSpace;

  final String eventTitle;
  final List<AlbumModel> albums;
  final String? selectedAlbumId;
  final int selectedFileCount;
  final bool receiving;
  final bool isBusy;
  final bool isUploading;
  final int queueCount;
  final int pendingReviewCount;
  final String? statusMessage;

  @override
  State<CameraUploadSheetView> createState() => _CameraUploadSheetViewState();
}

class _CameraUploadSheetViewState extends State<CameraUploadSheetView> {
  String _method = 'usb';
  bool _showMore = false;
  bool _starting = false;

  Future<void> _start() async {
    if (_starting || widget.isBusy || widget.receiving) return;
    setState(() => _starting = true);
    try {
      await widget.onStart(_method);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.isBusy || widget.isUploading || _starting;
    final height = MediaQuery.sizeOf(context).height * .89;
    return Material(
      color: AppColors.background,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: height),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(50),
                    ),
                  ),
                ),
                const SizedBox(height: 13),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Upload method',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close upload sheet',
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                Text(
                  'Connect a camera for real-time photo transfer.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  widget.eventTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (widget.albums.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    key: ValueKey('sheet-album-${widget.selectedAlbumId}'),
                    initialValue: widget.selectedAlbumId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Upload to album',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('No album'),
                      ),
                      ...widget.albums.map(
                        (album) => DropdownMenuItem<String?>(
                          value: album.id,
                          child: Text(
                            album.title,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: busy || widget.receiving
                        ? null
                        : widget.onChangeAlbum,
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: const Center(
                    child: Text(
                      'Photos',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      _methodOption(
                        'usb',
                        'Wired Camera Connection',
                        'USB cable · shoot and transfer photos',
                        Icons.camera_alt_outlined,
                      ),
                      const Divider(height: 1, indent: 48),
                      _methodOption(
                        'wireless',
                        'Wireless Camera Connection',
                        'Camera Wi-Fi or FTP transfer',
                        Icons.wifi_tethering_rounded,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () => setState(() => _showMore = !_showMore),
                  icon: Icon(
                    _showMore
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                  ),
                  label: Text(
                    _showMore ? 'Fewer methods' : 'More upload methods',
                  ),
                ),
                if (_showMore) ...[
                  _methodOption(
                    'phone',
                    'Phone Gallery',
                    'Choose only the photos you want',
                    Icons.photo_library_outlined,
                  ),
                  _methodOption(
                    'camera',
                    'Choose Camera Photos',
                    'Select individual photos from connected camera',
                    Icons.usb_rounded,
                  ),
                  _methodOption(
                    'files',
                    'Card Reader / Files',
                    'Choose photos from an SD card or other storage',
                    Icons.sd_storage_outlined,
                  ),
                  _methodOption(
                    'gallery',
                    'Watch Phone Gallery',
                    'Automatically receive new phone photos',
                    Icons.phone_android_outlined,
                  ),
                  _methodOption(
                    'phone-camera',
                    'Take a Phone Photo',
                    'Capture a photo with this phone',
                    Icons.add_a_photo_outlined,
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: busy ? null : widget.onUploadSettings,
                        icon: const Icon(Icons.tune_rounded, size: 17),
                        label: const Text('Upload settings'),
                      ),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: busy
                            ? null
                            : (_method == 'wireless'
                                  ? widget.onWirelessOptions
                                  : widget.onUsbOptions),
                        icon: const Icon(
                          Icons.settings_input_component_outlined,
                          size: 17,
                        ),
                        label: const Text('Camera options'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (widget.receiving) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: widget.onOpenTransfers,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('View live transfers'),
                    ),
                  ),
                  const SizedBox(height: 7),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : () => widget.onStop(),
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Stop receiving'),
                    ),
                  ),
                ] else ...[
                  const Text(
                    'Choose Shoot & Upload or Select & Upload from Upload settings. '
                    'Your camera connection and native permissions are handled automatically.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.mutedForeground,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: busy ? null : _start,
                      child: busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Start Upload'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _methodOption(
    String method,
    String title,
    String subtitle,
    IconData icon,
  ) {
    final selected = _method == method;
    return Material(
      color: Colors.transparent,
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 7),
        onTap: widget.isBusy || _starting || widget.receiving
            ? null
            : () => setState(() => _method = method),
        leading: Icon(icon, size: 21),
        title: Text(title, style: const TextStyle(fontSize: 13)),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.mutedForeground,
          ),
        ),
        trailing: Icon(
          selected
              ? Icons.radio_button_checked_rounded
              : Icons.radio_button_off_rounded,
          color: selected ? AppColors.primary : AppColors.mutedForeground,
        ),
      ),
    );
  }
}
