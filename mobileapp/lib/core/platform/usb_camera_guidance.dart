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
      'camera-detected' => const UsbCameraGuidance(
        title: 'Wired camera detected',
        details:
            'The phone can see the camera. This check has not opened a '
            'photo-transfer session or read its photos.',
        nextSteps:
            'Choose New shots only or Existing photos + new shots, then '
            'Start Live shooting. Take one photo with the camera shutter '
            'to verify automatic transfer.',
      ),
      'live-ready' => const UsbCameraGuidance(
        title: 'Live camera session is active',
        details:
            'AirPix is listening for new photos from the connected camera.',
        nextSteps:
            'Take a test photo with the camera shutter and check that it '
            'appears in Camera transfers. Keep AirPix open. If the camera '
            'screen or shutter is locked, stop Live shooting and check this '
            'model\'s supported tethered-shooting mode.',
      ),
      'ready' => const UsbCameraGuidance(
        title: 'Camera photo transfer is available',
        details: 'The camera is connected and its stored photos can be read.',
        nextSteps:
            'For automatic new-shot upload, start Live shooting and take '
            'a test photo. Import access alone does not confirm that the camera '
            'allows its shutter to work while connected.',
      ),
      'ptp_invalid_response' => const UsbCameraGuidance(
        title: 'Camera reply could not be decoded',
        details:
            'AirPix could not decode a camera reply. This error alone does '
            'not show that the camera USB setting is wrong.',
        nextSteps:
            'Retry with the updated app. If the camera shutter still works, '
            'you can choose Compatibility photo reader in USB / OTG options '
            'to read its available PTP/MTP photo catalog. Keep the same '
            'shooting-capable camera setting; do not select Mass Storage. '
            'Copy the connection details below if the problem continues.',
      ),
      'ptp_shooting_command_blocked' => const UsbCameraGuidance(
        title: 'Receiving stopped to protect camera controls',
        details:
            'This connection requested a command that AirPix does not allow.',
        nextSteps:
            'Unplug USB and check Camera setup for your brand. Choose '
            'Remote Shooting / PC Remote / Tether where supported. AirPix '
            'will not try Mass Storage or a different control mode.',
      ),
      'sony_mass_storage_mode' => const UsbCameraGuidance(
        title: 'Sony is in USB Mass Storage mode',
        details:
            'Mass Storage is for copying existing files; it can blank the '
            'Sony shooting display and cannot keep the physical shutter live.',
        nextSteps:
            'Unplug USB and choose the model in Camera setup. On Alpha '
            '7R IV use Network > PC Remote Function: On, USB, PC+Camera. '
            'On Alpha 7 IV use Setup > USB > USB Connection Mode > Remote '
            'Shooting and Still Img. Save Dest. > Dest.+Camera. Reconnect '
            'with a USB data cable and select New shots only in AirPix.',
      ),
      'sony_ptp_control_unavailable' ||
      'sony_camera_session_failed' => const UsbCameraGuidance(
        title: 'Sony detected, but live USB control is unavailable',
        details:
            'The iPhone found the Sony camera but could not open the '
            'shooting-control session. Detection does not prove the Sony '
            'vendor PTP interface is available on this iPhone.',
        nextSteps:
            'Disconnect USB, then on Sony Alpha 7 IV select Setup > USB > '
            'USB Connection Mode > Remote Shooting, not Mass Storage/MTP/'
            'USB Streaming. Set Network > Cnct./Remote Sht. > Remote '
            'Shoot Setting > Still Img. Save Dest. to Dest.+Camera. '
            'Keep the iPhone unlocked and grant camera access if prompted. '
            'Reconnect and try New shots only. If iOS still blocks the '
            'vendor PTP session, use a supported wireless/FTP workflow; '
            'the app cannot override iOS USB access.',
      ),
      'live_camera_transfer_only' ||
      'tether_mode_unsupported' ||
      'ptp_passthrough_unavailable' ||
      'ptp_interface_unavailable' ||
      'camera_transfer_mode' ||
      'live_camera_unsupported' ||
      'live_camera_mass_storage' ||
      'live_camera_shutter_unavailable' => const UsbCameraGuidance(
        title: 'Camera USB mode does not support live shooting',
        details: 'File transfer can disable the camera screen or shutter.',
        nextSteps:
            'Disconnect USB and check the camera manual for tethered '
            'shooting / PC Remote mode, then reconnect. Mode names and app '
            'compatibility depend on the model. On Nikon bodies offering USB '
            'connection priority, select Shooting instead of Upload. AirPix '
            'negotiates supported Canon EOS, Nikon and Sony shooting connections.',
      ),
      'tether_camera_unsupported' => const UsbCameraGuidance(
        title: 'This camera does not expose a supported shooting connection',
        details:
            'AirPix could not identify a compatible live-shooting protocol in '
            'the connected camera’s current mode.',
        nextSteps:
            'Check the camera’s tethering USB setting and reconnect. You can '
            'also use Wireless camera > Live shooting with camera FTP if the '
            'camera supports automatic FTP transfer.',
      ),
      'tether_camera_setting_required' ||
      'tether_mode_not_confirmed' ||
      'tether_card_recording_required' => const UsbCameraGuidance(
        title: 'Check the camera’s shooting settings',
        details:
            'The camera has not confirmed the settings needed for physical '
            'shooting and automatic photo transfer.',
        nextSteps:
            'Follow the camera setting shown above, then reconnect and start '
            'Live shooting. On Sony Alpha 7 IV, use Remote Shooting over '
            'USB with Still Img. Save Dest. set to Dest.+Camera; older Sony '
            'bodies may call this PC Remote / PC+Camera.',
      ),
      'tether_previous_photos_pending' => const UsbCameraGuidance(
        title: 'The camera has photos waiting from an earlier connection',
        details:
            'AirPix found an existing camera transfer queue before this '
            'shooting session was ready.',
        nextSteps:
            'Finish or clear the earlier transfer in the camera, then reconnect. '
            'Wait for AirPix’s ready message before taking new photos.',
      ),
      'tether_existing_photos_unavailable' => const UsbCameraGuidance(
        title: 'Use New shots only with this camera connection',
        details:
            'This shooting connection cannot also read existing card photos. '
            'AirPix has stopped the connection without opening file-import mode.',
        nextSteps:
            'Select New shots only and start Live shooting again. To import '
            'older photos separately, stop Live shooting and use Connected '
            'camera (USB / OTG) in manual upload. Check the camera’s USB mode '
            'before returning to live shooting.',
      ),
      'tether_mode_changed' => const UsbCameraGuidance(
        title: 'Camera shooting settings changed',
        details:
            'The camera is no longer using the shooting and recording '
            'settings confirmed at connection time.',
        nextSteps:
            'Check the camera’s USB and recording settings, then restart Live '
            'shooting. Photos already saved on the phone remain in the queue.',
      ),
      'tether_file_format_unsupported' ||
      'tether_file_too_large' ||
      'ptp_file_too_large' ||
      'ptp_transfer_too_large' ||
      'ptp_partial_read_required' => const UsbCameraGuidance(
        title: 'This photo cannot be received with the current connection',
        details:
            'The photo’s format or size exceeds what this camera connection '
            'can transfer safely.',
        nextSteps:
            'Use a supported still-image format or a smaller image setting, '
            'then take a new test photo. The original remains on the camera.',
      ),
      'ptp_staged_file_missing' ||
      'ptp_transfer_not_recoverable' ||
      'ptp_storage_unavailable' ||
      'ptp_staging_failed' => const UsbCameraGuidance(
        title: 'The phone could not keep the received photo',
        details:
            'The transfer file is missing or could not be saved. AirPix will '
            'not substitute the next camera photo for this one.',
        nextSteps:
            'Check free phone storage, recover this photo from the camera '
            'memory card, then restart Live shooting.',
      ),
      'camera_busy' => const UsbCameraGuidance(
        title: 'The camera is busy',
        details: 'The camera is still completing another operation.',
        nextSteps:
            'Allow the camera to finish writing its photo. If this continues, '
            'close other camera apps and reconnect.',
      ),
      'ptp_close_failed' ||
      'ptp_close_timeout' ||
      'ptp_close_pending' => const UsbCameraGuidance(
        title: 'Disconnect USB to release the camera',
        details:
            'Receiving has stopped, but the phone has not confirmed that the '
            'camera connection is closed.',
        nextSteps:
            'Unplug the USB cable, wait for the camera’s shooting display, '
            'then reconnect and start Live shooting. Photos already received '
            'continue uploading to cloud.',
      ),
      'live_camera_busy' ||
      'live_camera_already_running' ||
      'camera_live_session_active' ||
      'camera_live_session_starting' => const UsbCameraGuidance(
        title: 'A camera session is already running',
        details: 'The camera is busy with another import or live session.',
        nextSteps:
            'Stop the current session and close other camera apps, then '
            'start Live shooting again.',
      ),
      'live_camera_multiple_cameras' ||
      'multiple_cameras' ||
      'camera_selection_required' => const UsbCameraGuidance(
        title: 'Connect one camera for live shooting',
        details: 'More than one wired camera was detected.',
        nextSteps:
            'Disconnect the other cameras, then start the live session '
            'for the camera you want to use.',
      ),
      'live_camera_invalid_session' ||
      'live_camera_session_ended' ||
      'live_camera_session_not_found' ||
      'live_camera_session_mismatch' ||
      'camera_session_ended' ||
      'camera_storage_changed' ||
      'ptp_camera_changed' ||
      'live_camera_not_running' => const UsbCameraGuidance(
        title: 'Live camera session ended',
        details: 'The previous camera session is no longer active.',
        nextSteps:
            'Reconnect the camera and start Live shooting again. Wait '
            'for the ready message before taking a new photo.',
      ),
      'permission-denied' ||
      'camera_access_denied' ||
      'camera_control_access_denied' => const UsbCameraGuidance(
        title: 'AirPix camera permission is denied',
        details: 'The phone is blocking access to the external camera.',
        nextSteps:
            'Open phone Settings > AirPix and allow camera access. Reopen AirPix and retry the USB camera connection.',
        settingsRequired: true,
      ),
      'authorization-pending' ||
      'camera_authorization_pending' => const UsbCameraGuidance(
        title: 'External camera permission has not been granted yet',
        details: 'iOS has not yet granted or denied external camera access.',
        nextSteps:
            'Start or retry Live shooting, or choose Connected camera '
            '(USB / OTG) in manual upload, then allow external camera access '
            'if prompted. If no prompt appears, keep the phone unlocked, '
            'reconnect the camera and retry.',
      ),
      'permission-restricted' ||
      'camera_access_restricted' => const UsbCameraGuidance(
        title: 'External camera access is restricted',
        details: 'The phone reports a restriction on external camera access.',
        nextSteps:
            'Check Screen Time or device-management restrictions. If the '
            'phone is managed, ask its administrator to allow camera access, '
            'then retry.',
      ),
      'authorization-unavailable' ||
      'camera_authorization_unavailable' => const UsbCameraGuidance(
        title: 'External camera permission could not be checked',
        details:
            'iOS did not return a usable external camera authorization state.',
        nextSteps:
            'Keep the phone unlocked, reconnect the camera and retry. If '
            'the problem continues, restart AirPix and copy the USB camera '
            'support report with your iOS version.',
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
      'host-unsupported' || 'usb_host_unsupported' => const UsbCameraGuidance(
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
            "Unlock the phone, use a USB data cable and choose the camera model's shooting-capable USB mode for Live shooting. PTP / Photo Transfer is useful for importing existing photos, but may lock the shutter. Check the model manual before reconnecting.",
      ),
      'unsupported-device' => const UsbCameraGuidance(
        title: 'USB accessory detected, but not a camera',
        details:
            'The connected accessory does not advertise a supported PTP/MTP camera interface.',
        nextSteps:
            'For live shooting, unplug USB and choose the camera\'s dedicated remote-shooting/tether USB mode. PTP/MTP Photo Transfer alone may lock the shutter; use Files only for a separate manual import.',
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
      'ptp_session_closed' ||
      'ptp_session_busy' ||
      'ptp_session_failed' ||
      'ptp_transport_error' ||
      'ptp_transport_failed' ||
      'ptp_session_open_failed' ||
      'ptp_device_info_failed' ||
      'ptp_tether_timeout' ||
      'ptp_transaction_mismatch' ||
      'ptp_sequence_error' ||
      'ptp_invalid_packet' ||
      'ptp_write_failed' ||
      'ptp_timeout' ||
      'ptp_protocol_error' ||
      'ptp_command_rejected' ||
      'usb_camera_session_failed' => const UsbCameraGuidance(
        title: 'Camera found, but connection failed',
        details:
            'A USB camera was detected, but its photo-transfer session could not be opened.',
        nextSteps:
            'Close other camera apps and reconnect. For Live shooting, use the tethered-shooting USB mode supported by this model and app. File-transfer mode may prevent shooting. Also check camera power and the data cable.',
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
