# Current USB shooting audit - 2026-11-06

This section supersedes the earlier catalog-default recommendation preserved below.

## Observed failure and corrected routing

The supplied Sony Alpha 7 IV photograph shows **USB Mode: Mass Storage**. That camera-side mode exposes storage rather than a shooting session. The app cannot change the physical USB mode selected on the camera or guarantee that every camera firmware keeps its display and shutter usable.

The recent iOS/Android catalog-default change bypassed the existing Sony PC Remote RAM-queue adapter. Restored PtpTetherCameraTransport as the live USB default on both platforms, with no automatic fallbacks into ImageCaptureCore media import, Android MtpDevice, Mass Storage, or folder selection. The separate manual/catalog utilities remain available in code.

## Receiving and camera controls

- Default polling is 3 seconds without requiring shutter events. Card enumeration backs off for large catalogs (configured interval capped at 5 seconds; busy cameras and in-flight transfers can delay actual checks). Events can wake handling sooner.
- Sony performs the required connection handshake and reads the new-photo queue. Existing memory-card import is not substituted for live shooting.
- Sony destination and Camera priority are checked, not written. The required destination is card+SDRAM (0x11); Camera priority is 0. A mismatch stops with setup instructions.
- Canon card recording is checked, not changed. Canon session/event negotiation remains; Nikon uses body-control release mode 0. Fujifilm checks its tether mode.
- Standard, Canon, and Sony property-writing opcodes 0x1016, 0x9110, 0x9205, 0x9206 are blocked in Dart, Swift, and Kotlin in addition to existing shutter/UI-lock/delete guards.
- Necessary protocol/session/read commands still exist. This is not a claim that the phone sends no USB commands.
- No newly invented Panasonic/LUMIX, Olympus/OM SYSTEM, or Pentax/Ricoh vendor protocol. Those bodies remain limited to explicitly supported generic capability checks; unsupported models stop with guidance.

## Automatic phone cleanup

The live USB callback first saves a separate durable upload-queue copy, then journals deletion of its private native staging buffer. Failed staging deletion persists in SharedPreferences and retries when the upload service runs, including after restart.

After both blob upload and event-image registration are confirmed, the private upload-queue file is deleted. A failed delete now retains a completed queue row for cleanup-only retry instead of silently forgetting the file. Persisted completion prevents another upload. Network failures retain the queue copy. Camera-card originals are never deleted by these paths.

## Sony Alpha 7 IV setup and validation

Disconnect USB. Select Setup > USB > USB Connection Mode > Remote Shooting (PC Remote on older firmware). In Network > Cnct./Remote Sht. > Remote Shoot Setting, set Still Img. Save Dest. to Dest.+Camera. Use a writable memory card. Choose New shots only in AirPix. Keep the app foreground and phone unlocked, allow external-camera permissions, and wait for readiness.

Build and install a fresh iOS app, take three physical-shutter shots, verify the camera display/controls and cloud receipt of all three, then test a burst, offline queueing, reconnect, and automatic temporary-file cleanup. **Native iOS compilation and real Sony/iPhone behavior have not been verified on this Windows machine.**

## Evidence and verification

- 206 focused Flutter tests passed after the fixes (protocols, transfer pipeline, upload failures, deduplication, cleanup, and UI guidance).
- Additional Sony event-free automatic polling regression added and run separately.
- Android :app:testDebugUnitTest: BUILD SUCCESSFUL.
- Dart analysis of production lib and changed tests: no issues.
- No SDK license purchase, git commit, push, or deployment performed.

Primary sources checked:
- Sony Alpha 7 IV USB mode and remote save settings: https://helpguide.sony.net/ilc/2110/v1/en/print.html
- Cascable wired camera modes: https://cascable.se/help/wired-cameras/
- Cascable demo and its separate SDK license requirement: https://github.com/Cascable/cascablecore-demo
- libgphoto2 protocol value reference: https://github.com/gphoto/libgphoto2/blob/master/camlibs/ptp2/config.c

Cascable's MIT demo license does not license the commercial CascableCore framework. The demo requires its own evaluation/production license; it was reviewed, not embedded as an unlicensed dependency.

---

## Earlier audit (historical, superseded above)

# AirPix USB camera audit: historic catalog polling restored

Date: 2026-11-06. Historical reference: Git commit `b07f61b5e530ccad472bcdd43a35bb26a5f744be` (2026-08-31).

## What the old implementation actually did

The old iOS AppDelegate used ICDeviceBrowser / ICCameraDevice.requestOpenSession, enumerated ICCameraDevice.mediaFiles, and copied selected ICCameraFile objects using requestDownload. On Android, MtpDevice opened each request, enumerated storage IDs, object handles and metadata, imported individual objects, and closed afterward. Flutter upload_page.dart skipped baseline image IDs, polled for new IDs every three seconds, downloaded only unseen items, placed complete files into the app's persistent upload queue, then uploaded them through /image/upload and registered /eventImage. This was catalog polling, not remote-shutter events or a vendor tether SDK.

## What had changed

The newer default LiveCameraCapture transport was PtpTetherCameraTransport. Depending on camera family it sent vendor remote-control commands: Canon EOS 0x9114/0x9115 and sometimes 0x9110 card-destination write; Nikon 0x90c2 body-mode write; Sony 0x9201 handshake, 0x9205 property changes 0xd222 and 0xd25a. Those operations can change camera behavior. They were NOT present in the historical read-only catalog import path. Without a physical camera, it cannot be established whether any particular command caused a black camera screen.

## Fix applied

- lib/core/platform/live_camera_capture.dart: On iOS, select NativeLiveCameraTransport (ImageCaptureCore photo catalog) by default. On Android, select MtpCatalogCameraTransport (Android MtpDevice catalog) by default. Keep the vendor PTP transport code for explicit specialist uses, but never auto-fallback from catalog failure into manufacturer mode writes.
- lib/pages/upload/upload_page.dart: The normal physical USB session polls every 3 seconds regardless of shutter event notifications. The user can keep manually pressing the camera shutter; upload uses the existing durable queue and does not depend on internet speed.
- ios/Runner/AppDelegate.swift: Reuse its existing single-owner ImageCaptureCore live catalog session, unchanged remote/vendor PTP command path. Support both New shots only and Existing + new in the passive media catalog, preserving initial baseline/ack semantics. Also allow a fully completed catalog (100%) to arm even if the ready delegate callback wasn't delivered.
- lib/core/platform/mtp_catalog_camera.dart: Android photo catalog receiver follows the old open-list/close approach. It skips old IDs by default, monitors newly appearing images without events, stages them using existing native import methods, checks the staged file size, acknowledges only after durable local save, and keeps the Android phone screen awake while active. It does not select Mass Storage, browse a folder, send remote-shutter commands or change manufacturer shooting properties.
- test/usb_passive_catalog_test.dart: Verifies preferred transport selection, iOS native MethodChannel calls, Android event-independent polling, initial baseline, partial camera writes, camera-class compatibility, Android wake lock, explicit stored-file mode rejection, and absence of vendor-control/folder-picker calls.

## Practical limits and acceptance criteria

- Opening the standard ImageCaptureCore or MtpDevice session may still cause a particular camera firmware to enter a transfer-only mode. The app cannot guarantee otherwise. The camera must have a shooting-capable PTP/MTP USB configuration, and the OS must actually expose new photo objects in that mode.
- Some Sony PC Remote cameras expose new photos only through vendor RAM transfer queues, not ImageCaptureCore.mediaFiles. The default catalog approach will not receive shots on such camera firmware; switching to raw Sony vendor control is not automatic.
- User must rebuild/install native iOS code on a Mac/Codemagic/TestFlight. Flutter hot reload cannot apply AppDelegate.swift changes.
- Physical validation: Connect the intended camera with the proper cable and shooting-capable camera-side setting; confirm its screen and shutter work; take three shots; verify three new images arrive in Camera transfers after a short delay, persist to the local queue, and upload to the event; disconnect to confirm the camera returns to normal.
- Native iOS compilation and actual shutter behavior have NOT been verified on this Windows desktop.

## Testing this change

- All focused passive catalog tests passed, including an automatic poll with no event.
- 138 focused Flutter camera tests passed. Production Flutter source analysis passed.
- Full Flutter test run: one unrelated existing PC camera simulator test uses real localhost HTTP inside TestWidgetsFlutterBinding, which rejects HTTP requests; it failed independently of the USB catalog change.

## Final validation and wake-state handling

The Android passive catalog transport now uses the existing token-scoped TransferScreenAwake control while its foreground receiver is active, then releases that phone wake flag on stop. This does not change camera mode. Android vendor-specific USB interfaces are eligible for the passive MTP catalog attempt, not merely devices advertising the standard still-image USB interface; native MtpDevice must actually open for the catalog read to succeed.

Final targeted USB/passive tests: 10 tests passed. All relevant camera/PTP Flutter tests: 138 tests passed. Android :app:testDebugUnitTest succeeded (Gradle BUILD SUCCESSFUL). Production Flutter analysis passed. The full Flutter test suite still contains a pre-existing test failure in test/debug_pc_camera_transport_test.dart because TestWidgetsFlutterBinding blocks localhost HTTP; this is unrelated to USB camera behavior. All Git diff checks passed.
