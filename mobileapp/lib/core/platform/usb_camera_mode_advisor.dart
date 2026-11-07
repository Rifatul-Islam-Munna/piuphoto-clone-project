import 'package:flutter/services.dart';
import 'package:mobileapp/core/platform/usb_camera_diagnostics.dart';

/// Passive advice only. This never opens USB, changes camera settings, or
/// interprets a readable photo catalog as proof the physical shutter works.
enum UsbShootingModeState {
  noCamera,
  storageOnly,
  unverified,
  activeUnverified,
}

class UsbShootingModeAdvice {
  const UsbShootingModeAdvice({
    required this.state,
    required this.title,
    required this.status,
    required this.nextSteps,
  });

  final UsbShootingModeState state;
  final String title;
  final String status;
  final String nextSteps;
  bool get wrongMode => state == UsbShootingModeState.storageOnly;

  /// The native iOS bridge attaches a camera name, USB VID and transport
  /// label to real session failures. Use those facts for immediate guidance
  /// instead of requiring the photographer to open diagnostics separately.
  /// Never infer a vendor from a missing/null error payload.
  static UsbShootingModeAdvice? fromFailure(PlatformException error) {
    final details = error.details;
    if (details is! Map) return null;
    final name =
        details['camera']?.toString() ?? details['name']?.toString() ?? '';
    final vendor = (details['vendorId'] as num?)?.toInt() ?? 0;
    if (name.trim().isEmpty && vendor == 0) return null;
    return fromDiagnostics(
      UsbCameraDiagnostics.fromMap({
        'status': 'camera-detected',
        'message': error.message ?? '',
        'totalImages': 0,
        'cameras': [
          {
            'name': name,
            'usbVendorId': vendor,
            'transportType': details['transport']?.toString() ?? '',
          },
        ],
      }),
    );
  }

  static UsbShootingModeAdvice fromDiagnostics(UsbCameraDiagnostics report) {
    final camera = report.cameras.isEmpty ? null : report.cameras.first;
    final peripheral = report.usbDevices.isEmpty
        ? null
        : report.usbDevices.first;
    final brand = _CameraBrand.identify(
      camera?.name ?? peripheral?.name ?? '',
      camera?.usbVendorId ?? peripheral?.vendorId ?? 0,
    );
    final instructions = brand.instructionsFor(
      camera?.name ?? peripheral?.name ?? '',
    );
    final transport = (camera?.transportType ?? peripheral?.category ?? '')
        .toLowerCase()
        .replaceAll(' ', '')
        .replaceAll('-', '')
        .replaceAll('_', '');
    final stillImageInterface =
        peripheral != null &&
        (peripheral.usbClass == 6 || peripheral.interfaceClasses.contains(6));
    final storageOnlyClass =
        peripheral != null &&
        !stillImageInterface &&
        (peripheral.usbClass == 8 || peripheral.interfaceClasses.contains(8));
    final transferOnly =
        storageOnlyClass ||
        transport.contains('massstorage') ||
        transport.contains('pcstorage') ||
        transport.contains('cardreader') ||
        transport.contains('usbstreaming') ||
        // "File Transfer" can be an OS label for a valid PTP/MTP camera.
        // Do not conclude the physical shutter is disabled from that label.
        transport.contains('exfat');

    if (camera == null && peripheral == null) {
      return const UsbShootingModeAdvice(
        state: UsbShootingModeState.noCamera,
        title: 'No camera detected by the phone',
        status: 'Check cable and USB settings',
        nextSteps:
            'Use a powered-on camera, USB data cable and suitable '
            'adapter. On the camera, select Remote Shooting / PC Remote / '
            'Tether (names vary by brand), then retry. Open Camera setup '
            'for your model. AirPix never switches to Mass Storage. '
            'iOS may not expose an incompatible USB device.',
      );
    }
    if (transferOnly) {
      return UsbShootingModeAdvice(
        state: UsbShootingModeState.storageOnly,
        title: 'Wrong USB mode for live shooting',
        status: 'Storage / import mode detected',
        nextSteps:
            '$instructions Disconnect USB before changing '
            'the camera mode. AirPix will not change it or fall back to '
            'Mass Storage. Reconnect, choose New shots only, and test '
            'that the camera shutter and screen remain functional.',
      );
    }
    final active = camera?.liveSessionActive == true;
    return UsbShootingModeAdvice(
      state: active
          ? UsbShootingModeState.activeUnverified
          : UsbShootingModeState.unverified,
      title: active
          ? 'PTP session open; verify the shutter'
          : 'Camera detected; shooting mode not confirmed',
      status: active
          ? 'Live connection; test shot required'
          : 'PTP/tether capability unverified',
      nextSteps:
          '$instructions PTP/MTP can be correct for some '
          'cameras but stored-file access does not confirm live shooting. '
          'Take a new picture with the physical shutter, check that '
          'the screen is usable, and verify arrival in Camera transfers.',
    );
  }
}

enum _CameraBrand {
  canon,
  nikon,
  sony,
  fuji,
  panasonic,
  olympus,
  pentax,
  other;

  static _CameraBrand identify(String label, int vendor) {
    final name = label.toLowerCase();
    if (vendor == 0x04a9 || name.contains('canon')) return canon;
    if (vendor == 0x04b0 || name.contains('nikon')) return nikon;
    if (vendor == 0x054c || name.contains('sony') || name.contains('ilce-')) {
      return sony;
    }
    if (vendor == 0x04cb || name.contains('fuji')) return fuji;
    if (vendor == 0x04da ||
        name.contains('lumix') ||
        name.contains('panasonic')) {
      return panasonic;
    }
    if (vendor == 0x07b4 ||
        vendor == 0x33a2 ||
        name.contains('olympus') ||
        name.contains('om system')) {
      return olympus;
    }
    if (vendor == 0x0a17 ||
        vendor == 0x25fb ||
        name.contains('pentax') ||
        name.contains('ricoh')) {
      return pentax;
    }
    return other;
  }

  String instructionsFor(String label) {
    final model = label.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    if (this == sony && (model.contains('7rm4') || model.contains('7riv'))) {
      return 'Sony Alpha 7R IV: disconnect USB. In Network, set Ctrl w/ '
          'Smartphone to Off. Open PC Remote Function: PC Remote = On, '
          'PC Remote Cnct Method = USB, Still Img. Save Dest. = PC+Camera. '
          'Keep a writable card inserted and use Camera priority where available.';
    }
    return instructions;
  }

  String get instructions => switch (this) {
    canon =>
      'Canon EOS: select a remote-control PTP connection. On '
          'newer EOS cameras such as R6 Mark II, set Choose USB connection '
          'app to Photo Import/Remote Control. Disable camera Wi-Fi on '
          'bodies that disable USB while Wi-Fi is enabled.',
    nikon =>
      'Nikon: on models with Setup > USB connection priority, choose '
          'Shooting (not Upload). Nikon documents that Upload keeps the '
          'monitor blank while connected, while Shooting keeps it on. '
          'Use MTP/PTP if that is your model’s normal shooting-capable USB '
          'connection. Disconnect before changing settings; test the shutter.',
    sony =>
      'Sony: select PC Remote / Remote Shooting, not Mass Storage '
          'or MTP. On Alpha 7 IV, set Still Img. Save Dest. to '
          'Dest.+Camera when supported.',
    fuji =>
      'Fujifilm: select USB TETHER SHOOTING AUTO/FIXED rather '
          'than USB CARD READER or RAW conversion.',
    panasonic =>
      'Panasonic/LUMIX: select PC(Tether) and SD or SD + PC recording '
          'with a writable card inserted. PC(Storage) is for file import.',
    olympus =>
      'Olympus/OM SYSTEM: select RAW/Control or the camera-to-computer '
          'control icon on supported models, with camera-card recording. '
          'Storage import is not evidence of live tether.',
    pentax =>
      'Pentax/Ricoh: this connection must explicitly support the physical '
          'shutter while using PTP. There is no universal USB setting for '
          'iPhone tethering; Mass Storage/SCSI control is not used.',
    other =>
      'Choose the camera model’s shooting-capable PTP/MTP or '
          'tether mode, not Mass Storage or a card reader.',
  };
}
