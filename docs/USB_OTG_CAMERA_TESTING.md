# AirPix USB / OTG Camera Testing

## What AirPix supports

- Connected camera (USB / OTG): native iOS ImageCaptureCore discovers a PTP camera, opens its session, reads camera images and copies selected files into AirPix for upload.
- SD card / USB storage (Files): select files from the connected drive under Files > Browse > Locations. This is distinct from direct PTP camera access.
- iPhone photos: access existing iPhone photo-library images. This should never silently replace the USB camera route.

## How to validate on an actual iPhone

1. Install a freshly built iOS app (changes in Swift require a native rebuild).
2. Unlock the iPhone. Connect a good-quality USB data cable and compatible camera adapter. For Lightning iPhones, a powered Lightning-to-USB 3 adapter may be required.
3. Turn on the camera, select PTP / Photo Transfer mode if available, and grant any Apple camera-access permission prompt.
4. Go to AirPix > Upload > Test USB camera connection.
5. Read the report: camera name, USB session open/closed, camera media catalog progress, readable image count.
6. Tap Copy report to capture the result for support.
7. If the camera is ready and lists images, choose Connected camera (USB / OTG), select a photo and upload it.
8. If it is a mass-storage or SD card reader, choose SD card / USB storage (Files), then the EXTERNAL drive under Locations, not On My iPhone.

If AirPix cannot see the camera, open the built-in iOS Photos app and check Imports / connected devices. If Photos does not see it either, investigate USB compatibility, cable, camera USB mode, power and firmware first.

## Diagnostic meanings

- permission-denied: camera access denied by iOS; check iPhone Settings.
- no-camera: iOS ImageCaptureCore found no connected USB/PTP camera.
- catalog-loading: camera found, but its media catalog is not yet ready. Keep it on and retry.
- ready and 0 images: camera found but no compatible photos were listed.
- ready and a positive image count: try importing a photo. Native logging uses the label [AirPix USB].

## Limitations

- Cameras vary widely in supported USB protocols; PTP support on a desktop does not guarantee direct iPhone PTP compatibility.
- The Swift iOS native code cannot be compiled or device-tested on the Windows development PC. Use a Mac/Xcode or Codemagic iOS build plus a physical iPhone/camera to verify.
- A connected USB camera is not the same as the phone's built-in camera or its photo library.

## References

Apple ImageCaptureCore: https://developer.apple.com/documentation/imagecapturecore/
Apple iPhone camera import: https://support.apple.com/en-gb/guide/iphone/iph480caa1f3/26/ios/26
Apple external storage: https://support.apple.com/en-asia/guide/iphone/iph95baac91f/ios
Microsoft PTP driver: https://learn.microsoft.com/en-us/windows-hardware/drivers/image/ptp-driver
gphoto2: https://github.com/gphoto/libgphoto2

