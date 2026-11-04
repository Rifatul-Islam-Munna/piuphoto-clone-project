# AirPix wired USB / OTG camera validation

## Separate photo sources (do not conflate them)

- **Connected camera (USB / OTG)**: reads directly from a compatible USB PTP/MTP camera over native iOS ImageCaptureCore or Android USB Host/MTP. It does not read photos from the phone's built-in camera or gallery.
- **SD card / USB storage (Files)**: opens the operating system file picker. The user must choose their attached drive, not On My iPhone / internal phone storage.
- **Phone photos**: images already stored on the phone.
- **Wireless camera**: camera-to-phone Wi-Fi/PTP-IP, not the OTG cable.

## Physical iPhone / camera test (required before promising client hardware works)

1. Install a *fresh native iOS build*. Hot reload cannot update `AppDelegate.swift`.
2. Unlock the iPhone, connect a **USB data** cable and a compatible powered adapter if necessary (some Lightning iPhones require a powered Lightning-to-USB 3 Camera Adapter).
3. Turn the camera on; set USB mode to **PTP / Photo Transfer** and allow any iOS camera access prompt. Ensure photos exist on the camera's card.
4. In **AirPix > Upload**, choose **Test USB camera connection** and inspect status, camera name, session open, media catalog, and readable image count.
5. If status is ready with images, tap **Connected camera (USB / OTG)**, select a test photo and confirm it is copied into the app.
6. Upload the copied photo to an active event. Confirm the uploaded image in that event.
7. Try disconnecting the cable during a scan/import and verify the error is clear. Reconnect and retry.
8. If the camera uses Mass Storage instead of PTP, use the **SD card / USB storage (Files)** option. Do not mistake selecting iPhone photos for a successful OTG connection.

If iOS does not find the camera, check the built-in Photos **Imports** view as an independent detection test. If Photos does not recognize it either, investigate power, USB mode, cable/adapter and device compatibility. An app cannot determine *which* of these causes an undetected camera from a "no camera" result alone.

## Physical Android / camera test

1. Install a fresh Android build and confirm the phone supports USB Host/OTG.
2. Connect the camera with a data cable and turn it on in PTP/MTP Photo Transfer mode.
3. Tap **Connected camera (USB / OTG)** and **Allow** the Android USB device permission prompt.
4. If it does not connect, tap **Test USB camera connection**. Status can distinguish USB permission, unsupported device/protocol, failed session and empty media.
5. Select and import an actual photo, then upload it to the event.
6. Try a USB flash drive/keyboard without a camera attached: the app should not show a misleading camera permission prompt.
7. Remove/reconnect the camera during import and check the error and retry path.

## What each report status means

| Status | Meaning / next action |
| --- | --- |
| `permission-denied` | iOS app lacks external camera access; allow camera permission in iPhone Settings |
| `permission-required` | Android detects USB camera but lacks USB device permission; tap Connect and Allow |
| `no-camera` | No compatible camera was detected; this does *not* prove which cable, adapter, power or camera-mode issue caused it |
| `unsupported-device` | Android sees a USB accessory but no supported PTP/MTP camera candidate; change USB mode or use Files for SD storage |
| `session-failed` | Camera was detected but camera photo-transfer session failed; check PTP mode, busy camera, cable/power |
| `catalog-loading` | Camera session exists but photo list has not completed; keep camera awake, retry |
| `empty-media` | Camera session opened but no supported photos were found; verify card and supported file formats |
| `ready` | Camera session and photos available; try importing a real file |

**Support report**: tap **Copy report** in USB diagnostics. It includes status, native message, camera, USB session state, catalog progress, image count and session error. Send this plus iPhone/Android version, camera brand/model, USB mode and cable/adapter information to engineering. Native iOS logs are labeled `[AirPix USB]`; Android logs use `AirPixCamera`.

## Boundaries of verification

- Automated Flutter tests validate native method channel data conversion and error guidance; an Android debug build validates Kotlin compilation.
- Windows cannot build Swift iOS code or prove that a physical iPhone/adapter/camera enumerates. A macOS/Xcode or Codemagic iOS build and an actual iPhone with the client's camera are required.
- USB enumeration APIs do not reliably distinguish a disconnected cable from an incompatible adapter or a camera that is powered off. Error wording must never assert a unique hardware cause without evidence.

## References

- Apple ImageCaptureCore: https://developer.apple.com/documentation/imagecapturecore/
- Apple iPhone photo import: https://support.apple.com/guide/iphone/import-photos-and-videos-iph480caa1f3/ios
- Android MtpDevice: https://developer.android.com/reference/android/mtp/MtpDevice
- Android USB Host: https://developer.android.com/develop/connectivity/usb/host
