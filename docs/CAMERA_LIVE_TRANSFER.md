# Live camera transfer and automatic cloud upload

## Intended workflow

Select an event and album in **Upload > Auto sync**, then start a camera source.
The full **Camera transfers** page opens. Each received photo shows a preview
when its format can be decoded, its filename, exact file size, upload progress,
and an X while upload can still be cancelled. Received camera photos start uploading
to the cloud automatically as soon as the complete photo is received. There is
no five-second review delay and no separate Upload action. Shooting can continue
while cloud uploads are pending. Back navigation keeps reception active; **Stop receiving**
stops reception and waits for the camera connection to be released. Existing
queued photos continue uploading.

The event, album and enhancement choice are captured at session start. Changing
the active event stops reception; a completed in-flight local copy retains its
original destination. The app must remain in the foreground. Backgrounding stops
reception instead of pretending that iOS/Android will run the connection forever.
The phone screen stays awake while a live session is active.

For USB, choose **New shots only** (default) or **Existing photos + new shots**
before starting reception. The preference is remembered and locked for the active
session. Both scopes use the same shooting connection and immediate cloud upload.
The combined scope receives supported existing card photos in bounded batches,
checks for new shots between complete photo transfers, and gives new photos
priority. The current Sony adapter supports the new-shot queue only; a request
for combined import returns a clear mode limitation without opening a file-browse
session. See [LIVE_USB_CAMERA_SHOOTING.md](LIVE_USB_CAMERA_SHOOTING.md#choosing-what-to-upload).

The phone is a relay to the configured cloud storage. It uses a private temporary
retry file while receiving/uploading; it does not require a phone-gallery save.
Cloud delivery calls `/image/upload`, whose backend streams to the configured
S3/MinIO store, then `/eventImage` for the selected event/album. Only a valid
returned event-photo ID confirms upload completion. The temporary queue file is
deleted after that confirmation. A missing/malformed confirmation retains the
same uploaded URL and idempotency key for retry instead of uploading the blob again.

The transfer page distinguishes **Uploading to cloud**, **Uploaded to cloud**,
**Waiting for cloud connection**, and **Waiting for cloud confirmation**. Existing
automatic retry backoff is 1/2/5/10/30 minutes after failures; initial reception
has no artificial delay. A restored connection is tried automatically according
to that schedule. Backend temporary-file cleanup cannot replace a successful
storage response with a failed upload or delete another in-flight batch file.

## Wireless automatic shooting: camera FTP

Choose **Wireless camera > Live shooting with camera FTP**. This is for cameras
whose firmware includes an FTP client and automatic transfer after each shot.
It does not issue shutter, live-view, USB-mode, or camera-body lock commands.

1. Put the camera and phone on the same trusted Wi-Fi network. Client isolation
   on a guest network can prevent the devices from reaching each other.
2. Enter the settings displayed by AirPix in the camera's FTP profile:
   the phone's local server address, port **2121**, username, password, root
   folder **/**, **passive mode enabled**, and **FTP / no encryption**.
3. Enable the camera's automatic FTP transfer after each shot. Take a test photo.
4. Check its preview and cloud upload progress in Camera transfers. Upload starts
   automatically; tap X while cancellation is still available to cancel that photo.

The generated login is kept in device secure storage, so the camera can remember
its profile. Recheck the server address when changing Wi-Fi networks. Credentials
are not added to transfer tracking or sent to the backend. This receiver supports
ordinary passive FTP (PASV/EPSV), not FTPS/SFTP or active-mode FTP. Its local link
is unencrypted, so use a trusted network. Camera FTP support and which body/menu
functions remain available during transfer depend on the specific model.

Files stream to a staging file. FTP success is returned only after a complete
nonempty file has been copied into the durable local upload queue. Interrupted,
aborted, oversized, or declared-length-mismatched files are not queued. Where
ALLO supplies a length it is verified; otherwise FTP's clean data EOF is the
protocol completion signal. The receiver accepts supported still-image filename
extensions. It is not a general file server. All directories are virtual and
remote commands cannot read, rename, or delete arbitrary phone files.

Repeated identical transfers are identified by remote path, size, and SHA-256.
The same filename with different content is a different photo. Receiver callbacks
are serialized across connections, and camera acknowledgement never waits for
internet delivery. A cancelled photo stays cancelled even if the camera retries
it. Original files on the camera are never deleted.

The existing PTP/IP, Canon CCAPI, UPnP and HTTP discovery choices remain available
for compatible camera feeds. A gallery/file feed alone does not prove the camera
supports normal shooting while that connection is active.

## Cable connections and the black-screen issue

**USB file access and physical-shutter tethered shooting are separate capabilities.**
Some camera USB modes intentionally disable shooting. The generic Android MTP
and iOS ImageCaptureCore file/session APIs cannot universally unlock that state.
An iPhone connection label such as "Photo Import" is not proof of live shooting.

**Live shooting now uses the vendor PTP tether driver**, with original Canon EOS,
Nikon and Sony implementations. Android owns an exclusive raw USB PTP connection;
iOS sends PTP commands through ImageCaptureCore. Manual import remains separate.
The shared driver identifies the camera, validates its exposed operations,
negotiates shooting settings, receives new-shot events and downloads complete
files before acknowledging them. See [USB_TETHER_PROTOCOLS.md](USB_TETHER_PROTOCOLS.md)
for the exact profiles, wire operations, limits and primary references.

Canon EOS enables remote/event delivery while preserving card recording and
without requesting a UI lock. Nikon explicitly selects camera-body control.
Sony performs its PC Remote handshake, confirms Camera priority and PC + Camera
recording, then reads complete entries from its new-photo queue. The Sony settings
remain selected after Stop; the app does not restore Application priority or
RAM-only recording. Unsupported modes fail with setup guidance instead of
silently opening manual import. Regular EOS M and PowerShot protocols require
separate adapters; the regular EOS M6 Mark II path is allowed.

Fujifilm is detected but excluded from this live USB implementation, even when
iOS advertises a physical-shutter capability. Its ordered volatile-buffer
transfer lifecycle needs a dedicated adapter; generic card scans or full-object
reads alone cannot establish safe new-shot delivery.

Choose the model's documented shooting-capable USB mode before connecting. Native
discovery capability and a successful handshake are useful evidence, but a real
test shot is still required to verify screen, shutter and menu behavior on each
camera/firmware. The transfer page offers **Camera locked? Release connection**
to release the session before changing modes. On iOS, a close request is no longer
reported as successful before ImageCaptureCore confirms that the exact camera
session is closed or the device has detached. Its eight-second deadline reports
`PTP_CLOSE_TIMEOUT`; an unsuccessful close reports `PTP_CLOSE_FAILED`. While
release is pending, `PTP_CLOSE_PENDING` prevents a new USB operation from taking
over that camera. A failed/timed-out release stays guarded until actual closure
or detachment; disconnect the USB cable when instructed. The app preserves this
failure instead of replacing it with a successful stopped message.

Manual import and the legacy receiver use the same iOS release guard. A late
open after Stop is closed under its original owner before another session can
start; an old close callback cannot clear a later owner's state. Photos already
received keep uploading during release. No camera hardware has been certified
by the automated tests described below.

No app can promise that every camera menu/function stays available under every
connection: the camera firmware defines those limits. The implementation must
not label import access as verified shooting support.

### Passive connection checks and the supplied iOS reference

The **Test USB camera connection** action now performs discovery without opening
or closing a photo-import session. Android reads USB descriptors and existing
permission state; iOS uses ImageCaptureCore discovery and inspects a catalog only
when an explicit live/manual operation already owns an open session. Listing
Android camera devices no longer performs a hidden MTP open/close probe either.
This removes an unnecessary session transition that could interrupt shooting.
It does not change the camera firmware's behavior when a live session is opened.

An idle camera reports **camera-detected** and **Not inspected** for its photo
list. Cached catalog entries from a closed iOS session cannot make the connection
appear ready for import. An active session reports **live-ready**, including when
its card is empty and it is waiting for its first new photo. Diagnostic checks
never take ownership of, close, or replace the live receiver's session.

iOS authorization is preserved as authorized, denied, restricted, not-determined,
or unavailable. An unresolved permission callback is no longer reported as user
denial or treated as permission granted. Copyable reports include contents and
control authorization states. Reading the control state does not request control
permission or send a camera-mode command.

The user-supplied repository
https://github.com/nicorichard/ICDeviceBrowserTest was inspected at commit
`040de73060cfc921c1eb5ed4db3f83d733b04dae` on 2026-11-06. Its README describes an
iOS 18 beta authorization/discovery reproduction. `DeviceService.swift` starts
and stops discovery and requests/resets contents authorization. It does not open
a camera session, send PTP commands, receive new photo events, or download photos.
There is no remote-versus-file-browse session switch to copy from that sample.

Apple's public `ICSessionOptions` configures content delivery, not a universal
shooting-mode switch. `requestControlAuthorization` grants permission; actual
camera-mode negotiation now occurs through the vendor PTP driver. The iOS bridge
uses `requestSendPTPCommand` and requests contents/control permission when starting
the explicit tether operation. ImageCaptureCore owns its underlying session and
transaction IDs, as documented in Apple's PTPPassThrough sample. The app does
not use the macOS-only tether/shutter APIs as an imaginary iOS mode switch.

## Cancellation and persistence

- X cancels a queued file or interrupts its current file-upload request. A
  persistent cancellation record prevents stale queue snapshots, retries,
  restarts, or identical camera resends from uploading it again.
- A cancelled local queue copy is retained for its session preview. Cancellation
  does not remove camera originals or delete an already-uploaded event photo.
- Once event-image registration begins, the button is disabled and the page
  reports that the upload is finishing. Losing a server response cannot safely
  be treated as a cancelled server operation.
- Registration retries reuse the image URL and idempotent `clientTransferId`.
  Pending/uncertain registration records are retained beyond the completed
  history limit, so their cancellation boundary cannot be forgotten in a burst.
- Confirmed cloud transfer IDs and cancellation decisions are stored separately
  from the 2,000-entry display history. Reconnecting to an existing card does not
  reupload the same event/source identity after its history row has been pruned.
  A completion receipt is written only after a valid event-photo confirmation;
  a failed receipt write retains the same cloud URL and retry file.
- The backend transfer-state enum accepts `cancelled`. Deploy the corresponding
  backend change for remote dashboards to display that status; local cancellation
  remains effective if tracking cannot sync.

## Guest QR delivery

**Share guest QR** remains available on the transfer page during upload and uses
that receiving session's event. Uploaded photos retain their selected album.
Event-photo creation schedules face indexing, and an enrolled guest's personal
gallery refreshes every six seconds. Existing publication/review, gallery-access
and face-match rules determine which photos the guest can see; this follow-up
does not change backend policy or make every uploaded photo visible to every guest.

QR preparation first reads the existing face-delivery setting. An already-enabled
event can be shared without requiring permission to edit its settings. Enabling
a disabled event still uses the existing authorized settings request and consent
rule. The temporary loading dialog removes only its own route: Back, navigation
or caller disposal cannot later pop the camera transfer page or display a stale
QR dialog. Repeated taps cannot start overlapping preparation dialogs.

## Validation and device acceptance

Latest Windows validation after the USB release and guest-QR follow-up:

- `flutter analyze --no-pub`: **no issues**.
- Full `flutter test --no-pub`: **239 passed**, including **23 binary-codec**
  and **56 PTP tether workflow/native-contract** tests. The 21 new regressions
  cover three native-event-to-cloud integration scenarios, seven QR route
  lifecycles, four QR permission cases, QR access during upload, three controller
  close-lifecycle cases, close guidance and two additional PTP cases.
- Fresh `flutter build apk --debug --no-pub`: **successful** (exit 0;
  `assembleDebug` 10.1 seconds), producing
  `mobileapp/build/app/outputs/flutter-apk/app-debug.apk`.
- Earlier Android `:app:testDebugUnitTest`: **22 passed**, zero failures/errors/skips;
  the Android app and test sources compiled successfully. This follow-up's fresh
  APK build also compiled Android successfully. Existing Gradle/AGP/Kotlin future
  support notices did not prevent it; dependency upgrades are outside this change.

The preceding cloud-upload change passed **12 backend tests** and `nest build`
after the temporary-file cleanup fixes; backend code is unchanged by this USB
and QR follow-up. Those tests use mocked storage; no production test photograph
was uploaded.
The iOS test target now contains **44 cases**, including **13 new release-lifecycle
cases** alongside framing, staging, partial-read/fallback and listener-lifetime
regressions. These iOS changes remain **uncompiled and unrun** because Xcode is
not available on the Windows machine. Installation and physical phone/camera
tests have not been performed.
These automated results are not a camera compatibility certification.

Automated tests cover FTP authentication, passive data connections, duplicate
transfers, retained files after local-save failures, stop/start races, cancellation
and partial data, upload cancellation races and persistence, and the transfer-page
preview/progress/cancellation and immediate cloud-upload behavior. The three
integration tests join the real PTP parser, live controller and durable cloud
queue with real temporary JPEG files; only native camera I/O and HTTP responses
are simulated. They cover bursts while cloud delivery is blocked, duplicate
events, both upload scopes, reconnect receipts and cancellation. They do not
prove compatibility with an unspecified physical camera.

Before releasing a device build, verify:

1. With the named camera in its documented shooting mode, press the physical
   shutter, inspect the captured image on the camera, change exposure controls,
   and confirm the phone receives that new photo once.
   Test both USB upload scopes on card-capable connections: old photos must be
   skipped in New shots only and received in Existing photos + new shots. Shoot
   during a large card import and verify the next new photo takes priority after
   any file already copying. Reconnect and verify completed/cancelled objects
   do not upload again, including a collection larger than the 2,000-row history.
2. Shoot a burst, reconnect, interrupt Wi-Fi/USB mid-transfer, and confirm no
   partial or duplicate photos are published.
3. Cancel while queued and during file upload; verify the event does
   not receive that photo and a restart/resend does not revive it.
4. Disconnect internet while leaving camera Wi-Fi available, receive more shots,
   then restore internet and verify the queued photos finish.
5. Background the app and return. Confirm receiving shows stopped and can be
   restarted; confirm FTP retries on the camera according to its firmware.
6. On iOS, stop while connecting and while receiving, then reconnect. Verify
   a missing/failed close never reports successful release, new USB operations
   remain blocked until closure or detachment, and a late open cannot arm a
   cancelled session. Use the session's guest QR during upload and verify the
   published, matching photo appears under the existing guest-access rules.

iOS native compilation, signing, installation and real tether tests require Xcode
and an actual iPhone/camera. A Windows Flutter/Kotlin build cannot validate that
hardware path. Hot reload cannot install changed native channel methods.

## Primary references

- Piufoto features, OTG and camera FTP support: https://www.piufoto.com/features
- Canon EOS R3 FTP automatic transfer while continuing to shoot:
  https://cam.start.canon/en/C010/manual/html/UG-06_Network_0070.html
- Apple physical-shutter capability:
  https://developer.apple.com/documentation/imagecapturecore/icdevicecapability/cameradevicecantakepictureusingshutterreleaseoncamera
- Apple session options:
  https://developer.apple.com/documentation/imagecapturecore/icsessionoptions
- Apple control authorization:
  https://developer.apple.com/documentation/imagecapturecore/icdevicebrowser/requestcontrolauthorization(completion:)
- Supplied reference source reviewed at a fixed commit:
  https://github.com/nicorichard/ICDeviceBrowserTest/blob/040de73060cfc921c1eb5ed4db3f83d733b04dae/ImageCapture/DeviceService.swift
- Reference author's iOS 18 discovery report:
  https://forums.swift.org/t/icdevicebrowser-fails-to-find-any-devices-after-ios-18-update/72764
- Android MtpDevice import/event API:
  https://developer.android.com/reference/android/mtp/MtpDevice
- libgphoto2 model-specific PTP configuration and capture implementation:
  https://github.com/gphoto/libgphoto2/tree/master/camlibs/ptp2
