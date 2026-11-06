# USB physical-shutter receiving

The intended workflow is: choose a shooting-capable USB mode, connect the
camera to the phone, start Live shooting, and press the camera's own shutter.
Received files go through the existing durable local upload queue before native
transfer acknowledgement. Cloud upload is a separate state and needs internet.
AirPix must remain open while receiving.

## Added adapters

| Family | Connection and protocol requirements | Behavior | Verification status |
| --- | --- | --- | --- |
| Panasonic / LUMIX | PC(Tether), standard card-object operations, capture-target read `0x940A` and advertised tether-capture capability `0x9404` (never invoked) | Requires SD target `0` or SD + PC `2`; never writes target `0x940B`; handles `0xC108` card events and periodic card discovery | Automated wire/flow tests; physical iPhone/model testing pending |
| Olympus / OM SYSTEM | OM-D style PTP protocol, advertised `0x9486`, standard property operations; control `0xD052` must have a known UINT16 value and reversible writable enumeration if changed; target `0xD0DC` must already be card `2` | Reads the original control mode, requests PC connection `1` only if necessary, confirms readback, restores the original control mode on stop/failed setup | Automated wire/flow tests; physical iPhone/model testing pending |
| Pentax / Ricoh | Native connection must explicitly report physical-shutter support and expose standard card-object operations | Receives card photos using standard PTP. Otherwise rejects live receiving with specific guidance; stored-photo import remains separate | Conditional compatibility path only; no vendor-specific iPhone SCSI/SDK implementation or verified model list |

Support is capability-based, not a promise for every camera bearing a brand
name. In particular, older Olympus XML/PictBridge control is a different
transport. Desktop Pentax SCSI/SDK support is not proof of ImageCaptureCore/iPhone
support. Do not switch a camera to Mass Storage to try to enable live receiving.

Both LUMIX and OM paths support New shots only and Existing photos + new shots
through the existing scheduler. Existing files do not count as proof that the
physical shutter worked. UI labels distinguish a prepared connection, a photo
received on the phone, and cloud upload progress.

## Protocol and lifecycle details

- LUMIX `0x940A` uses parameter `0x08000090`. Its accepted response is the
  10-byte little-endian tuple `(uint32 0x08000091, uint32 2, uint16 target)`.
  Target `0` is card, `1` is RAM and `2` is both. RAM-only, unknown or
  malformed replies fail closed. The app never sends the setter.
- OM connection mode is read through standard `GetDevicePropDesc`/`GetDevicePropValue`.
  Only `0xD052` can be written, only UINT16 `1` (connect) or `2` (restore),
  and only for Olympus/OM USB identities. The recording target is read-only.
  Both original and requested connection values must be advertised. Storage is
  primed before PC control and the new-shot baseline is taken afterwards.
- OM `0xC002`/`0xC102` are card-object events; `0xC008`/`0xC108` are property
  events. Preview/direct-store notifications are not treated as card files.
  Event decoding is vendor-specific: `0xC108` has a different LUMIX meaning,
  and OM `0xC101` must not be decoded as a Nikon RAM photo.
- Recording settings are checked on periodic card scans. A changed target or
  OM control-off event stops receiving. LUMIX RAM and OM preview/direct-store
  events are ignored; card scans discover the saved originals. No new adapter
  sends shutter, live-view, delete, format or UI-lock commands. The app never
  changes the selected recording destination.
- OM control restoration is attempted only after pending PTP work settles.
  Failure or timeout still closes the native session and reports that the user
  must unplug USB and check the camera controls. Unplugging during a session
  cannot be repaired with commands to a disconnected device.
- PTP negotiation cannot establish that the LCD, viewfinder, focus controls and
  physical shutter all remain usable. No model is hardware-certified by these
  tests. iOS may also decline to expose a camera in its vendor tethering mode.

## Native protection and upload lifetime

The Dart, Swift/ImageCaptureCore and Kotlin/USB endpoints block standard
capture, format, reset, power-down, delete, move/copy and property-write
commands. Every USB identity now uses a positive allowlist: common metadata/photo
reads, plus only the current adapter's explicitly reviewed vendor commands.
Canon connection/event mode permits only values 0/1; Nikon permits body priority
0 only; Sony connect permits only phases 1/2/3 with their exact arguments.
Unknown identities cannot inherit vendor commands from a model name or PTP
extension number. Unreviewed live-view, capture, mode and data-write commands
are rejected in Dart, Swift and Kotlin before reaching USB. The sole property
write exception is the validated OM connection transaction above. Native photo
downloads use the same vendor restriction, preventing a Canon partial-read
opcode from becoming an Olympus mode command.

The Camera upload page shows Remote Shooting / PC Remote / Tether guidance
beside Connect, with the exact brand settings in Camera setup. Sony Alpha 7R IV
(ILCE-7RM4) has separate PC Remote Function / USB / PC+Camera instructions;
Alpha 7 IV (ILCE-7M4) uses Remote Shooting / Dest.+Camera. Negotiation
failures retain camera identity after session release so the error screen shows
brand-specific setup. No automatic storage-mode fallback is attempted.

The receive pipeline is physical shutter -> camera card (Sony also exposes its
PC Remote queue) -> immediate events / 500 ms vendor polling / 1-second small-card scans -> private phone staging -> durable
upload queue -> cloud object and gallery record confirmation -> automatic
deletion of the private phone copies. Failed uploads retain their queued copy.
Cleanup failure retries cleanup without uploading again. Camera-card originals
and the phone photo gallery are never deleted.

No universal display-on guarantee is possible from PTP success. Mass Storage
selected on the camera must be changed on the camera before connecting.
Cascable's demo does not supply a free universal USB driver: its published wired
support distinguishes Canon/Nikon/Sony tethering from other-camera image import.

## Cleanup permissions, latency and iOS build configuration

- Automatic deletion operates only on private camera staging roots and
  Documents/upload_queue. Ownership checks resolve existing paths, reject links
  that lead outside those directories, and refuse camera-card/gallery originals.
  The native iOS temporary directory (TMPDIR) and Flutter's cache directory are
  both covered. No Photos-library deletion API or permission is used.
- The first staging copy can be removed after the separate durable queue copy
  is saved. The queue copy is removed only after cloud registration is confirmed.
  Invalid persisted staging paths are discarded without deleting their files.
- Camera events wake discovery immediately. Vendor polling uses 500 ms, and
  card reconciliation starts at 1 second, scaling to 5 seconds for large cards.
  Storage/event DeviceBusy responses back off 500-3000 ms. A busy individual
  object has its own retry so it does not block every later shot in a burst.
- Uploads start immediately after durable receipt, without a review countdown.
  Full end-to-end upload under 1.5 seconds is not an SLA: exposure, JPEG/RAW size,
  USB transfer, queued work, internet bandwidth and server processing all count.
- The Podfile now explicitly enables camera, photo read and photo add handlers
  and disables unused microphone, location, Bluetooth and tracking handlers.
  All four used iOS purpose strings are nonempty and checked in Codemagic.
  The unused `onesignal_flutter` dependency was removed: its locked 5.5.4
  plugin linked the full location-capable OneSignalXCFramework despite no app
  initialization or calls. This removes a likely source of the reported location
  purpose-string warning; no invented GPS purpose or location prompt is added.
  USB, camera FTP and the explicit Canon CCAPI connection do not read GPS or Wi-Fi SSIDs.
  Confirm the warning is absent in the next fresh iOS archive/App Store check.
  iOS deployment is 15.0, matching the installed Flutter 3.47.8 pod helper.
  A macOS/Xcode build is still required to verify the compiled app.

## Source references

Wire facts were checked against libgphoto2 commit
`26a57b27caeb865a6b1d415aa5a80b47837c9023`; no libgphoto2 dependency is added.
The Dart adapters are independently implemented against those protocol facts.

- [PTP vendor commands and events](https://github.com/gphoto/libgphoto2/blob/26a57b27caeb865a6b1d415aa5a80b47837c9023/camlibs/ptp2/ptp.h)
- [LUMIX target packet and OM PC-mode transactions](https://github.com/gphoto/libgphoto2/blob/26a57b27caeb865a6b1d415aa5a80b47837c9023/camlibs/ptp2/ptp.c)
- [Capture-target property choices](https://github.com/gphoto/libgphoto2/blob/26a57b27caeb865a6b1d415aa5a80b47837c9023/camlibs/ptp2/config.c)
- [Panasonic: tethered recording / PC(Tether)](https://help.na.panasonic.com/answers/how-to-use-tethered-recording-lumix-s-series/)
- [Olympus: tethered shooting setup](https://learnandsupport.getolympus.com/learn-center/photography-tips/technique/tips-on-tethered-shooting)
- [pkTriggerCord: Pentax SCSI requirement for Mass Storage](https://github.com/asalamon74/pktriggercord/blob/master/pentax_scsi_protocol.md)
- [Sony Alpha 7R IV: PC Remote Function](https://helpguide.sony.net/ilc/1930/v1/en/contents/TP0002728092.html)
- [Cascable demo](https://github.com/Cascable/cascablecore-demo)
- [Cascable wired-camera compatibility](https://cascable.se/help/wired-cameras/)
- [OM Capture: camera and computer controls](https://software.omsystem.com/omcapture/en/)
- [Apple: private temporary files and cleanup](https://developer.apple.com/documentation/foundation/using-the-file-system-effectively)
- [Apple: permission purpose strings](https://developer.apple.com/documentation/uikit/requesting-access-to-protected-resources)

## Software validation (2026-11-07)

- The earlier 246-test Flutter regression passed. This follow-up adds USB
  identity/parameter isolation, default-deny vendor operations, failed-command
  release without retry, and distinct Sony 7R IV setup coverage. The expanded
  regression and affected-suite reruns pass; one symbolic-link test is skipped
  because this Windows host lacks symlink creation privileges. Coverage also
  includes real one-second event-free polling, shutter-to-cloud queue, durable
  receipts, cleanup retries, cancellation, discovery and transfer/setup UI.
- Android `:app:testDebugUnitTest` passed, including native vendor guards.
- The full Dart app analysis passes with no issues. The local HTTP simulator
  test now scopes a real loopback HTTP client to its own test zone instead of
  Flutter's default HTTP-400 stub; its receive/download/acknowledge test passes.
- Swift safety tests were added, but an iOS/Xcode build and physical camera
  acceptance tests cannot be run on this Windows host.
- These results validate software behavior; no camera/firmware combination is
  certified by simulated PTP replies.

## Required device acceptance test

Record the exact camera model/firmware, iPhone model/iOS version and cable or
adapter for every result. Native iOS builds require macOS/Xcode.

1. With existing card photos, connect in the documented shooting mode. Check
   the camera display, viewfinder, focus, menu controls and physical shutter.
2. In New shots only, take JPEG and supported RAW photos, then a burst. Confirm
   that only new images arrive once, remain on the camera, and reach the selected
   event's cloud gallery. Check RAW+JPEG pair handling for the actual model.
3. Repeat in Existing photos + new shots and confirm new shots are prioritized.
4. Disable internet, shoot, then restore internet. Confirm local receipt and
   subsequent cloud completion without another capture or duplicate.
5. Change recording target, stop receiving, unplug/reconnect, and background
   the app. Check release behavior and start a new session as needed. For OM,
   verify normal control after both successful stop and failed setup.

Run the PTP codec/transport, live-camera, upload queue, USB guidance/discovery,
setup-dialog and transfer-page tests after changes. These cover software
behavior; they do not replace the device test above.

## Wireless live shooting

The live wireless entry point now has two explicit protocols. It does not
scan generic PTP/IP, browse DLNA libraries, or guess HTTP capture/snapshot/live
URLs. Those older modules are not called by the live Upload page. No protocol
or USB-mode fallback is attempted when a wireless connection fails.

| Choice | One-time camera setup | Receiving path |
| --- | --- | --- |
| Camera FTP auto-send | Camera and iPhone on the same trusted Wi-Fi; enter the app's host, port, login, passive mode and folder in the camera FTP profile; enable automatic transfer after each shot | Camera initiates a transfer after its physical shutter. AirPix streams the complete file to private staging, makes a durable queue copy, journals staging cleanup, then acknowledges FTP. Cloud upload runs independently. |
| Canon CCAPI | Compatible Canon with CCAPI enabled/activated; shared Wi-Fi or the camera's access point; enter the exact displayed address/port and optional camera login | GET-only photo-event polling and same-origin image reads. No shutter, live view or shooting-setting endpoint is allowed. |

Sony FTP setup calls automatic sending "Auto Trans When Shot" / "Auto Transfer"
on relevant models. Other brands and models use different menu names and may
lack FTP auto-send entirely. Camera Wi-Fi or Bluetooth alone does not prove
support for either path. Panasonic, OM and Pentax USB adapters do not imply
that all their wireless protocols are implemented. An unsupported model must
show setup/unsupported guidance instead of a storage-only connection.

CCAPI processes events immediately after connection (including any event consumed
by discovery), then polls every 500 ms when idle. Polls do not overlap;
transient failures back off to 5 seconds. Failed photos remain pending during
the session, and a failed download does not discard subsequent burst photos.
An image is acknowledged only after its durable upload-queue save.
The address is remembered; camera passwords remain in memory for that session.
HTTP Basic and Digest (MD5/SHA-256, supported qop) use at most one challenge
retry per request. Wrong credentials on the exact configured endpoint stop
discovery. Redirects, cross-origin content and non-content image URLs are
blocked. TLS certificate verification is not bypassed.

Allow Local Network access if iOS asks. If denied, open Settings > Privacy &
Security > Local Network > AirPix, then retry. These paths do not read GPS or
the Wi-Fi SSID and need no Location permission. A socket failure cannot reliably
distinguish permission denial, a wrong address, a powered-off camera or bad Wi-Fi;
the UI explains those checks rather than claiming permission was granted.
Incoming FTP can be initiated by the camera without an outgoing discovery probe.

Keep AirPix in the foreground while shooting. Receiving stops when the app is
backgrounded; restart it before continuing. FTP cameras can retry unacknowledged
transfers. CCAPI announcements not yet durably imported are session state, so
an app termination/disconnection is not guaranteed to recover missed shots.
Camera-card originals remain available. A camera hotspot may provide no internet:
already received photos remain in the durable queue and upload when the app can
reach the cloud. Full files, queued work and network bandwidth determine latency;
500 ms detection does not guarantee a completed cloud upload within 1.5 seconds.

The upload architecture remains: native USB adapter or wireless receiver ->
private staging/bytes -> durable app-private upload queue + transfer ledger ->
cloud object upload -> event-image registration -> completed receipt -> private
queue-file deletion. Only app-owned copies are automatically removed; no Photos
library or camera-card deletion permission is requested.

### Wireless validation and remaining device checks

Loopback HTTP/FTP tests cover actual socket transfers, complete/truncated files,
burst retention, redirects/control-URL refusal, same-origin enforcement,
cancellation during discovery/polling, Basic/Digest login, bounded wrong-password
failure, durable FTP acknowledgement and staging cleanup. Digest calculations
are checked against RFC 7616 published vectors. The Canon setup dialog is checked
at 320 px width with 1.6x text scaling. These are software checks, not camera
certification.

On each supported physical model, test a new shutter photo and burst, camera
display/focus/menu use, wrong login, permission denial/retry, Wi-Fi interruption,
no internet then reconnection, and app background/restart. Confirm cloud gallery
registration before private queue files disappear. A fresh macOS/Xcode archive
and actual iPhone/camera tests remain required.

Sources:
- [Canon CCAPI functions](https://developercommunity.usa.canon.com/s/article/CCAPI-Function-List)
- [Canon CCAPI camera setup](https://cam.start.canon/en/C018/manual/html/UG-06_Network_0130.html)
- [Sony 7R IV automatic FTP](https://helpguide.sony.net/di/ftp/v1/en/contents/TP0002043783.html)
- [Apple local-network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
- [HTTP Digest standard and test vectors](https://www.rfc-editor.org/rfc/rfc7616.html)

Final full-suite run: `flutter analyze --no-pub` reports no issues.
`flutter test --no-pub --reporter expanded` passes 341 tests; one symlink test is
skipped because this Windows host cannot create symbolic links.
`git diff --check` reports no whitespace errors.
