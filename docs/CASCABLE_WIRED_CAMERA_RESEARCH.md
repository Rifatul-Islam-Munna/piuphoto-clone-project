# Cascable wired-camera research and AirPix integration constraints

Sources reviewed on 2026-11-06:
- https://cascable.se/help/wired-cameras/
- https://github.com/Cascable/cascablecore-demo
- https://github.com/Cascable/cascablecore-distribution
- https://github.com/Cascable/cascablecore-swift
- https://developer.cascable.se/

## What works and what does not

Cascable Studio documents full wired remote/tether shooting on supported Canon EOS, Nikon, and Sony Alpha models. Importing photos from other USB cameras is a separate feature. Never present import-only USB access as proof that the camera physical shutter works.

The CascableCore demo source is MIT-licensed, but its underlying CascableCore camera framework is commercial and needs an evaluation/commercial license from the vendor. Its public demo cannot enable those proprietary protocols without activation. No CascableCore package, API key, or binary has been linked into AirPix as part of this change. Current native USB operation remains AirPix's existing ImageCaptureCore (iOS) and raw PTP (Android) adapters.

## Changes applied to existing AirPix USB handling

1. Passive USB diagnostics display model-aware mode guidance for Canon, Nikon, Sony, Fuji, Panasonic/LUMIX, Olympus/OM SYSTEM, and Ricoh/Pentax.
2. Clearly storage-only interfaces (mass storage / card reader) are recognized as wrong for physical-shutter live sessions. A device simply labelled PTP/MTP is **not** automatically rejected; Canon, Nikon and others can use PTP/MTP as their correct control transport.
3. iOS live PTP open no longer rejects all MTP-labelled devices solely based on transport name. The underlying PTP adapter still negotiates vendor operations and refuses unsupported shooting configurations.
4. The previous 1-second polling + notifications design continues unchanged. On camera models exposing card handles in shooting mode, the app baselines existing card objects and imports only new ones. Sony PC Remote and some Fujifilm bodies use separate vendor mechanisms.
5. The help panel now includes Canon R6 Mark II's "Choose USB connection app > Photo Import/Remote Control", Canon Wi-Fi USB conflict, Nikon's often-normal PTP/MTP mode and Sony's PC Remote setting. This is vendor/model guidance, not a compatibility guarantee.

## What a licensed CascableCore integration would require

- Request a trial at https://developer.cascable.se/ and confirm redistribution rights and licensing terms. Do not commit or log the license key.
- On a Mac with Xcode, add the official CascableCore distribution via Swift Package Manager (or CascableCoreSwift, which depends on it), configure runtime license activation, and verify it builds and activates on a physical iPhone. The demo cannot use wired USB in the iOS simulator.
- Implement an isolated iOS SDK owner behind a dedicated Flutter MethodChannel / EventChannel. Never open the same USB camera through both CascableCore and AirPix ImageCaptureCore simultaneously. Explicitly stop one owner and wait for release before starting another.
- SDK connection sequence: camera discovery -> camera choice -> authentication/prompts -> connect -> capability verification -> baseline existing files (or use SDK new-photo delivery API where available) -> receive complete new photos -> durable local queue -> cloud worker -> clean disconnect.
- Implement session IDs, duplicate prevention, download ACK only after durable save, retries, cancellation, and background limitations equivalent to AirPix's current LiveCameraCapture contract. New-photo polling is an optional fallback when supported by the SDK/camera; it is not a universal substitute for vendor tether events.
- Show model-specific "unsupported for shooting" errors when a device can only expose its stored files. Do not silently switch to USB Mass Storage, card reader, or MTP import.
- Use the exact SDK headers/docs for the installed licensed version; the MIT demo gives example discovery/connection/filesystem APIs but is not a complete production tether receiver.

The existing AirPix iOS Info.plist already includes NSLocalNetworkUsageDescription, _ptp._tcp Bonjour discovery, NSAllowsLocalNetworking, and a camera usage description. Reuse these instead of duplicating entries.

## Acceptance checklist for a real USB camera

1. Turn off and unplug other USB camera controller applications; connect the camera by a known-good USB data cable.
2. Select the camera's supported shooting-capable connection. Never force mass storage as fallback.
3. Launch live receiving. Confirm the camera screen/viewfinder and its physical shutter still work before declaring capture verified.
4. Press the camera's shutter three times. All three **new** images appear in AirPix, with no old card photos misclassified as new.
5. Keep cloud offline during one shot: local receipt is preserved and upload resumes when connectivity returns.
6. Disconnect cleanly; the camera returns to ordinary shooting and AirPix does not leave the USB session held.
7. Repeat on a real iPhone/iPad (and Android where supported), not only on simulators. Camera and firmware support remain model-dependent.

## Unverified items

- CascableCore's vendor code has **not** been integrated or licensed.
- The modified native Swift path has **not** been compiled or tested on a Mac/iPhone here.
- Successful wired Sony Alpha 7 IV physical-shutter-to-cloud transfer has **not** been demonstrated.
- The current AirPix implementation does not promise Cascable Studio's full brand/model coverage.


## 2026-11-06 Deep dive: Apple ImageCaptureCore and CascableCoreSwift

Official sources:
- https://developer.apple.com/documentation/imagecapturecore
- https://developer.apple.com/documentation/imagecapturecore/iccameradevice/requestsendptpcommand(_:outdata:completion:)
- https://developer.apple.com/documentation/imagecapturecore/iccameradevice/ptpeventhandler
- https://developer.apple.com/documentation/imagecapturecore/iccameradevice/requestenabletethering()
- https://github.com/Cascable/cascablecore-demo
- https://github.com/Cascable/cascablecore-swift
- https://cascable.se/help/wired-cameras/

### Apple-native connection lifecycle

1. Discover ICCameraDevice via ICDeviceBrowser and obtain explicit iOS camera-control permission.
2. Reject known storage-only transport names (USB Mass Storage, card reader, USB streaming). Do not reject MTP by name alone: Canon/Nikon and other models use PTP/MTP for actual shooting control.
3. Open exactly one ICCameraDevice session; wait for didOpenSessionWithError. ImageCaptureCore owns underlying PTP open/close and transaction identifiers.
4. Check cameraDeviceCanAcceptPTPCommands before calling requestSendPTPCommand. The native bridge sends standard PTP requests; the shared Dart vendor adapter inspects GetDeviceInfo operations/extension and negotiates Canon, Nikon, Sony or Fujifilm shooting mode as supported.
5. Listen for ICCameraDeviceDelegate.didReceivePTPEvent, while keeping a 1-second independent polling fallback for models exposing a readable photo list in shooting mode. Never wait exclusively for ObjectAdded event.
6. Establish a baseline of existing card photos (or vendor queue) before starting; import only new objects, copy completed bytes to durable phone storage, and acknowledge only after the local upload queue accepts them. Cloud delivery is independent of the USB session.
7. On stop/error, close the exact native owner; never open an MTP/import session automatically as a fallback. A successful USB connection is not proof that a physical shutter works: explicitly check a test shot.

Apple marks requestEnableTethering() and requestDisableTethering() deprecated and says the call has no effect on standard third-party cameras with a standard capture capability; do not rely on them to switch Sony/Canon/Nikon firmware into remote-shooting mode. Never send an app-triggered shutter command in AirPix.

### What CascableCore's demo teaches

The demo differentiates the RemoteShooting command category from FilesystemAccess. Camera models may support them simultaneously or require separate modes. It has discovery, on-device authentication callbacks and asynchronous connection completion. It is *not* just a generic 1-second filesystem poll. The Swift wrapper depends on CascableCore binary distribution (CascableCoreSwift Package.swift currently depends on cascablecore-distribution from 18.0.2). The wrapper and demo are MIT; the CascableCore engine is not. An evaluation or commercial license is necessary for an actual SDK-based multi-brand adapter.

### Changes in AirPix in this round

- lib/core/platform/ptp_shooting_safety.dart: forbid host-issued PTP DeleteObject, InitiateCapture/OpenCapture, Canon remote-shutter/UI-lock/viewfinder and Sony remote-shutter commands.
- ios/Runner/PtpTetherTransport.swift: same hard stop at the native PTP request boundary. The default ImageCaptureCore requestDownload fallback reads a file on the same active camera session and does not switch the camera into Mass Storage.
- android/.../PtpTetherController.kt: enforce the same passive-camera command policy for raw USB/PTP.
- lib/core/platform/ptp_tether_camera.dart: treat an exhausted standard PTP DeviceBusy (0x2019) while polling as a transient physical-camera-write state. Retry on next tick and issue occasional nonfatal status instead of repeated error messages.
- lib/core/platform/usb_camera_mode_advisor.dart + upload_page.dart: reuse native camera VID/model/transport error details to give direct brand-specific recovery steps on failed connections, including Sony Mass Storage and Canon/Nikon MTP mode distinctions.
- Flutter, Android and Xcode-native tests cover shutter command restrictions. The Swift tests require Xcode/Mac hardware to run; an iOS connection cannot be validated on Windows.

### Current implementation boundaries

- The original AirPix paths remain intact. No licensed CascableCore binary or activation token was provided or installed.
- Read-only USB/PTP commands do not guarantee a physically functional camera screen: the selected camera firmware mode must support local shooting.
- In particular, Sony Alpha 7 IV requires USB Remote Shooting / PC Remote and a compatible photo destination. The app cannot change a camera from USB Mass Storage into remote mode over that storage-only connection.
- Not all models permit reading card objects while the shutter is active. Sony can expose a PC Remote transfer queue instead, and some Fujifilm models expose only vendor object events.
- Run a clean iOS build and physical shutter-to-cloud test on the actual camera. The existing Flutter tests and Android Gradle tests validate code behavior but cannot establish iOS USB hardware compatibility.


## November 6, 2026: Revisited Cascable demo versus AirPix passive polling

Cascable's public "Getting Started With CascableCore" explicitly separates RemoteShooting and FilesystemAccess command categories. Many camera models cannot keep both active simultaneously. Its demo switches categories before invoking separate filesystem functionality; that switch is not safe for AirPix's strict always-usable shutter workflow. The alternative camera-initiated transfer handler is triggered by the camera, and it can provide previews or sometimes original files, but only when that camera/mode supports the capability. The commercial framework's proprietary USB vendor protocols are NOT included in cascablecore-demo or cascablecore-swift.

AirPix must *never* switch to Mass Storage or a dedicated filesystem import mode inside a live session. It keeps the existing iOS ImageCaptureCore PTP transport, Canon EOS / Nikon / Sony PC Remote / eligible Fujifilm vendor adapters, and durable Flutter upload queue. A standard PTP camera with camera-side shutter capability and GetObjectHandles/GetObject support can be checked periodically; camera event notifications are optional optimization. Sony's PC Remote fixed RAM queue is polled separately. A vendor camera unable to read files from its shooting mode cannot be made universally polling-only through Apple's APIs.

New adjustment this turn: keep 1-second monitoring on small cards, but scale *full PTP card-handle enumeration* with observed card size to avoid overwhelming the camera while shooting. Baseline <=499 files: ~1s; 500-999: ~2s; 1000-1499: ~3s; cap at ~5s. Vendor event notifications still wake the receiver independently. The Sony shooting-mode queue remains checked approximately every second and does not enumerate the card. New-shot objects are downloaded and ACKed only after the durable local upload queue save. No camera original is deleted; no camera shutter command is issued by AirPix. A regression test validates delayed discovery of a new physical-shutter photo on a large card without needing events.

Non-goal: install an unlicensed CascableCore framework or claim that opening PTP guarantees the camera screen remains active. A real Sony Alpha 7 IV + iPhone test with Sony USB Remote Shooting is still mandatory. iOS Swift native changes cannot be compiled on this Windows desktop.

Recovery UI change (this round): the Camera transfers screen now offers "Camera screen black? Stop and fix USB mode" for active live-USB sessions. AirPix closes its PTP receiver before presenting camera-specific setup instructions. It never retries by opening a Mass Storage session. Other transfer sources do not show this USB-only recovery action. This is a control-restoration action, not proof that a camera supports simultaneous remote shooting and filesystem access.
