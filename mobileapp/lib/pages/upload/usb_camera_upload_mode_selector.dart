import 'package:flutter/material.dart';
import 'package:mobileapp/core/platform/live_camera_types.dart';

/// The photo scope is chosen before connecting and remains fixed until the
/// receiver has stopped. Vertical options keep both choices readable on phones.
class UsbCameraUploadModeSelector extends StatelessWidget {
  const UsbCameraUploadModeSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.sessionLocked = false,
    this.isSaving = false,
  });

  final LiveCameraUploadMode value;
  final ValueChanged<LiveCameraUploadMode> onChanged;
  final bool sessionLocked;
  final bool isSaving;

  static String labelFor(LiveCameraUploadMode mode) => switch (mode) {
    LiveCameraUploadMode.newShotsOnly => 'New shots only',
    LiveCameraUploadMode.existingAndNew => 'Existing photos + new shots',
  };

  @override
  Widget build(BuildContext context) {
    final enabled = !sessionLocked && !isSaving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'USB photo selection',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        _UploadModeOption(
          key: const ValueKey('usb-upload-new-shots-only'),
          title: labelFor(LiveCameraUploadMode.newShotsOnly),
          description: 'Upload only photos taken after the camera is ready.',
          selected: value == LiveCameraUploadMode.newShotsOnly,
          onPressed: enabled
              ? () => onChanged(LiveCameraUploadMode.newShotsOnly)
              : null,
        ),
        const SizedBox(height: 8),
        _UploadModeOption(
          key: const ValueKey('usb-upload-existing-and-new'),
          title: labelFor(LiveCameraUploadMode.existingAndNew),
          description:
              'Upload photos already on the camera and keep uploading each new shot.',
          selected: value == LiveCameraUploadMode.existingAndNew,
          onPressed: enabled
              ? () => onChanged(LiveCameraUploadMode.existingAndNew)
              : null,
        ),
        const SizedBox(height: 8),
        Text(
          isSaving
              ? 'Saving photo selection…'
              : sessionLocked
              ? 'Stop live shooting to change which photos upload.'
              : 'Both options upload to your cloud event automatically. '
                    'Existing photos require card access while shooting.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _UploadModeOption extends StatelessWidget {
  const _UploadModeOption({
    super.key,
    required this.title,
    required this.description,
    required this.selected,
    required this.onPressed,
  });

  final String title;
  final String description;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.all(12),
            foregroundColor: colors.onSurface,
            backgroundColor: selected ? colors.primaryContainer : null,
            side: BorderSide(
              color: selected ? colors.primary : colors.outlineVariant,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
