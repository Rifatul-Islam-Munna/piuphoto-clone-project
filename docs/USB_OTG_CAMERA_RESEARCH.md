# AirPix: USB / OTG camera engineering audit (November 2026)

## Scope

This report covers **only physically connected camera-to-phone transfer through a USB data cable and compatible phone adapter**. The working wireless camera mode must not be modified.

## Key protocol distinction

| Connected hardware | Protocol or OS access | AirPix option |
| --- | --- | --- |
| DSLR/mirrorless camera in PTP/Photo Transfer mode | iOS ImageCaptureCore, Android USB Host + MtpDevice | Connected camera (USB / OTG) |
| Camera in Mass Storage mode, SD card reader | iOS/Android file-picker mounted storage | SD card / USB storage (Files) |
| USB webcam / HDMI capture dongle (UVC) | Video stream protocol, not a camera photo catalog | Not the DSLR stored-photo import flow |
| Photos already on phone | Photo library / media picker | Phone photos |
| Wi-Fi connected camera | Network PTP-IP / supported camera HTTP | Separate, working wireless mode |

## What the operating systems can actually tell us

**Android**: UsbManager.deviceList enumerates peripherals and reveals class/interface, VID/PID and USB permission; an empty OTG adapter with nothing enumerated does not necessarily appear. AirPix now shows **all** attached USB accessories in the *Test USB camera connection* report, including hubs, mass-storage/SD readers, UVC devices, camera-like devices and unknown devices. Unknown devices are **never** auto-probed. The user can explicitly tap **Try as PTP camera** for an unclassified accessory, which then uses the same Android permission and MTP open+scan flow.

**iPhone**: Apple ImageCaptureCore can discover compatible image-capture cameras, open a session and enumerate media. It does **not** expose a general USB-host inventory that ordinary iOS applications can use to attest that *any* OTG cable/adapter is plugged in. ExternalAccessory covers the specific MFi-accessory ecosystem and is not a universal USB camera discovery mechanism. AirPix now displays ImageCaptureCore transport, USB vendor/product identifiers where exposed, session error, catalog progress and photo count. It does not claim it detected an empty adapter. Cameras with clearly wireless transports are excluded from the wired-only browser.

**No API can guarantee the exact physical failure** behind an absent USB device. Repeatedly saying "bad cable" would be misleading; app reports a short differential diagnosis instead.

## USB diagnostic stages visible to photographers

1. **USB accessory**: Android USB host capability, number/type of enumerated devices; iOS says adapter enumeration unavailable.
2. **Camera detected**: Compatible camera name(s) detected by the appropriate native layer.
3. **Camera session**: Whether a PTP/MTP or ImageCaptureCore session really opened. If it fails, show native session reason.
4. **Photo catalog**: Loading, no supported images, or count of photos available for import.

All device details, vendor/product IDs, native error and status can be copied from the support report. The diagnostics do not browse the phone photo library.

## iPhone physical test: required

1. Install a **new native iOS build**, not hot reload.
2. Unlock iPhone. Turn on DSLR/mirrorless camera. Use its **USB DATA** port, not HDMI, and select PTP/Photo Transfer (not charging-only).
3. Connect camera to the appropriate USB-C cable or Lightning-to-USB camera adapter. For Lightning, a powered Lightning-to-USB 3 adapter may be needed.
4. Open Apple's Photos app. Check **Imports** or, on newer iOS versions, **Collections > Devices**. If Apple Photos cannot see this camera either, troubleshoot compatibility, adapter power, and camera settings before blaming AirPix.
5. Open AirPix > Upload > **Test USB camera connection**. Copy the result and check stages above.
6. If camera and photos appear, choose **Connected camera (USB / OTG)**, select a photo and verify successful local import and upload to the active event.
7. Test photo import after cable unplug/replug, a large memory card and a camera that refuses USB session access.

## Android physical test: required

1. Install fresh Android build; confirm USB OTG/host is supported.
2. Plug in known good USB data cable and camera set to PTP/MTP; tap **Connected camera** and allow the system USB permission prompt.
3. Inspect **Test USB camera connection**. It must distinguish "USB accessory recognized" from "photo-capable camera".
4. For an unidentified USB accessory (not a reader/webcam), explicitly tap **Try as PTP camera**. If the protocol is unsupported, the native PTP/MTP session error should be shown.
5. Import a photo, then intentionally disconnect camera during import and verify the recovery message.

## Open-source library review (no new dependency installed)

- Flutter `camera`: primarily device camera capture/preview; does not replace PTP file import.
- Flutter `usb_camera_plugin`: Android UVC/webcam streaming; no iOS and not DSLR PTP memory-card import.
- Flutter `flutter_usb_serial_manager`: Android USB serial/Modbus; not PTP and no iOS.
- libgphoto2: mature PTP vendor-specific camera support for PC/Linux class hosts but not a drop-in, unrestricted iOS Flutter solution.
- Native ImageCaptureCore (iOS) and Android USB Host/MtpDevice remain the right baseline for stored-camera-photo import. If supporting a specific camera that uses proprietary transport, assess that brand and model separately.

## Apple and Android primary references

- ImageCaptureCore framework: https://developer.apple.com/documentation/imagecapturecore/
- Session opening: https://developer.apple.com/documentation/imagecapturecore/icdevice/requestopensession%28%29
- Media catalogue ready callback: https://developer.apple.com/documentation/imagecapturecore/iccameradevicedelegate/devicedidbecomeready%28withcompletecontentcatalog%3A%29
- Camera file download API: https://developer.apple.com/documentation/imagecapturecore/iccamerafile/requestdownload%28options%3Acompletion%3A%29
- Camera USB transport details: https://developer.apple.com/documentation/imagecapturecore/icdevice/transporttype
- ExternalAccessory framework limits: https://developer.apple.com/documentation/externalaccessory
- Apple camera adapter troubleshooting: https://support.apple.com/en-ie/118280
- Android USB host API: https://developer.android.com/develop/connectivity/usb/host
- Android MtpDevice: https://developer.android.com/reference/android/mtp/MtpDevice
- Flutter webcam plugin: https://pub.dev/packages/usb_camera_plugin
- Flutter USB serial plugin: https://pub.dev/packages/flutter_usb_serial_manager
- libgphoto2: https://github.com/gphoto/libgphoto2

## Verification boundary

Flutter unit tests and Android Kotlin compilation can run on this Windows development PC. No physical iPhone, adapter, and client camera were connected for end-to-end iOS native testing; iOS Swift code must be rebuilt and verified on actual hardware. Do not claim that every camera model will work solely because an app build succeeds.
