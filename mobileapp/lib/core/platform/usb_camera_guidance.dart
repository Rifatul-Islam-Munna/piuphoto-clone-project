/// Actionable, honest wording for the separate USB camera / OTG data route.
/// USB APIs cannot reliably tell a missing cable apart from an incompatible
/// camera, so 'no-camera' must never be reported as a confirmed cable failure.
class UsbCameraGuidance {
  const UsbCameraGuidance({
    required this.title,
    required this.details,
    required this.nextSteps,
    this.settingsRequired = false,
  });

  final String title;
  final String details;
  final String nextSteps;
  final bool settingsRequired;

  static UsbCameraGuidance forStatus(String status, {String? message}) {
    final hint = message?.trim();
    final advice = switch (status.toLowerCase()) {
      'permission-denied' || 'camera_access_denied' => const UsbCameraGuidance(
        title: 'AirPix camera permission is denied',
        details: 'The phone is blocking access to the external camera.',
        nextSteps:
            'Open phone Settings > AirPix and allow camera access. Reopen AirPix and retry the USB camera connection.',
        settingsRequired: true,
      ),
      'permission-required' ||
      'usb_permission_required' ||
      'usb_permission_denied' ||
      'usb_permission_in_progress' => const UsbCameraGuidance(
        title: 'USB permission is required',
        details:
            'Android sees a camera, but AirPix cannot read it until you grant USB device access.',
        nextSteps:
            'Tap Retry camera connection and choose Allow on the Android USB permission prompt. Reconnect the cable if the prompt does not appear.',
      ),
      'host-unsupported' => const UsbCameraGuidance(
        title: 'USB host / OTG not supported',
        details: 'Android does not report USB host support on this phone.',
        nextSteps:
            'Direct USB camera transfers require a phone with USB host/OTG capability. Check the phone specification or use a supported phone.',
      ),
      'no-camera' || 'no_camera_connected' => const UsbCameraGuidance(
        title: 'No compatible USB camera detected',
        details:
            'The app did not detect a compatible wired camera. This does not prove whether the cable, adapter, camera or USB mode is the cause.',
        nextSteps:
            'Unlock the phone, turn the camera on, connect a USB data cable and compatible OTG adapter, and select PTP / Photo Transfer on the camera. If available, check whether the phone Photos / Files app detects it.',
      ),
      'unsupported-device' => const UsbCameraGuidance(
        title: 'USB accessory detected, but not a camera',
        details:
            'The connected accessory does not advertise a supported PTP/MTP camera interface.',
        nextSteps:
            'Switch the camera from Mass Storage/Charging to PTP / Photo Transfer mode, or choose SD card / USB storage (Files).',
      ),
      'camera-locked' || 'camera_device_locked' => const UsbCameraGuidance(
        title: 'Connected device is locked',
        details:
            'The camera or connected device has restricted access to its photos.',
        nextSteps:
            'Unlock the camera/device, accept any trust or photo access prompt, then reconnect and retry.',
      ),
      'session-failed' ||
      'camera_session_failed' ||
      'usb_camera_session_failed' => const UsbCameraGuidance(
        title: 'Camera found, but connection failed',
        details:
            'A USB camera was detected, but its photo-transfer session could not be opened.',
        nextSteps:
            'Keep the camera awake, close other camera-import apps, reconnect the cable, and select PTP/MTP Photo Transfer on the camera. An underpowered adapter can also cause this.',
      ),
      'catalog-loading' || 'camera_catalog_loading' => const UsbCameraGuidance(
        title: 'Camera connected; loading photo list',
        details:
            'The USB connection exists, but the camera has not finished providing its photo list.',
        nextSteps:
            'Leave the camera on and unlocked, wait for its memory card to load, then tap Retry. Large cards may take longer.',
      ),
      'empty-media' => const UsbCameraGuidance(
        title: 'Camera connected; no readable photos',
        details:
            'The camera session opened, but it did not return any supported images.',
        nextSteps:
            'Verify there are photos on the camera memory card, check the photo-transfer mode, or use SD card / USB storage (Files).',
      ),
      'camera_import_failed' ||
      'usb_camera_import_failed' ||
      'usb_camera_read_failed' ||
      'usb_diagnostics_failed' ||
      'camera_files_missing' ||
      'usb_camera_disconnected' => const UsbCameraGuidance(
        title: 'Photo transfer failed',
        details:
            'The camera could not send the selected image data to the phone.',
        nextSteps:
            'Reconnect the camera, keep it powered on, check free phone storage and USB mode, refresh the camera photos, and try copying again.',
      ),
      'missing_plugin' => const UsbCameraGuidance(
        title: 'USB camera feature unavailable in this build',
        details:
            'The installed app does not have the native USB camera bridge.',
        nextSteps:
            'Install a freshly rebuilt version of AirPix. Hot reload will not add native iOS/Android camera code.',
      ),
      _ => const UsbCameraGuidance(
        title: 'Could not read the USB camera',
        details: 'The phone could not complete the wired camera check.',
        nextSteps:
            'Check USB permission, the data cable and camera transfer mode. Use Test USB camera connection to copy a support report.',
      ),
    };
    if (hint == null || hint.isEmpty) return advice;
    return UsbCameraGuidance(
      title: advice.title,
      details: hint,
      nextSteps: advice.nextSteps,
      settingsRequired: advice.settingsRequired,
    );
  }
}
