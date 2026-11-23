import 'package:flutter/material.dart';
import 'package:mobileapp/core/theme/app_theme.dart';

/// Mirrors the reference's upload-options sheet without changing camera
/// transport, USB read scope, file quality, or native capture behavior.
Future<bool?> showCameraUploadPreferencesSheet(
  BuildContext context, {
  required bool manualSelection,
}) {
  var selectedManual = manualSelection;
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * .85,
        ),
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Upload settings',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'UPLOAD OPTIONS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.mutedForeground,
                    letterSpacing: .5,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      _UploadPreferenceTile(
                        title: 'Shoot & Upload',
                        subtitle: 'Automatically send each new camera photo.',
                        icon: Icons.camera_alt_outlined,
                        selected: !selectedManual,
                        onTap: () =>
                            setSheetState(() => selectedManual = false),
                      ),
                      const Divider(height: 1, indent: 52),
                      _UploadPreferenceTile(
                        title: 'Select & Upload',
                        subtitle:
                            'Keep incoming camera photos on this phone. Select them before uploading.',
                        icon: Icons.checklist_rounded,
                        selected: selectedManual,
                        onTap: () => setSheetState(() => selectedManual = true),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Manual mode only changes delivery approval. Your existing camera connection and original photo quality stay the same. Unselected photos are never sent to the cloud.',
                        style: TextStyle(
                          color: AppColors.mutedForeground,
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.pop(sheetContext, selectedManual),
                    child: const Text('Confirm'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _UploadPreferenceTile extends StatelessWidget {
  const _UploadPreferenceTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: AppColors.foreground, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.mutedForeground,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            selected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            color: selected ? AppColors.primary : AppColors.mutedForeground,
          ),
        ],
      ),
    ),
  );
}
