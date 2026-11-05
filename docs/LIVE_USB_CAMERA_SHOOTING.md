# AirPix live USB camera shooting

Updated: 6 November 2026

## What is implemented

Physical camera shutter → new photo → phone relay → automatic cloud upload
to the selected event and album, with preview and progress on the transfer page.

**Live shooting uses the new PTP tether driver by default.** It detects regular
Canon EOS, Nikon and Sony protocols and validates the camera's advertised
operations before negotiating shooting mode. Android owns a raw USB connection;
iOS uses ImageCaptureCore PTP passthrough. The USB upload scope can include existing
card photos on shooting connections that support reading the card. A separate
manual card/file importer remains available; live shooting never falls back to it.

The exact protocol profiles, excluded variants, native methods, source references
and size limits are documented in [USB_TETHER_PROTOCOLS.md](USB_TETHER_PROTOCOLS.md).
Protocol implementation does not establish hardware compatibility with every
model under a brand. Physical screen/shutter/menu behavior remains camera firmware
behavior and must be verified with a real phone and camera.

## Setup

1. Install a fresh native build. Hot reload cannot add Swift/Kotlin methods.
2. Select the event and album in **Upload > Auto sync**.
3. Choose the camera's shooting-capable USB mode, then connect one camera with
   a USB data cable and a compatible phone adapter.
4. Choose **New shots only** (the default) or **Existing photos + new shots**.
   The app remembers this choice. Stop receiving before changing it.
5. Tap **Start live shooting**, allow external-camera/USB access, and wait for
   the ready message before taking photographs. In New shots only mode, existing
   card files are skipped. In Existing photos + new shots mode, readable existing
   photos join the automatic upload queue and the app keeps listening for new shots.
6. Press the physical camera shutter. Confirm the new photo appears on the full
   **Camera transfers** page with its preview, filename and size.
7. Cloud uploading starts automatically when the complete camera photo arrives.
   There is no five-second delay or separate Upload button. Tap **X** while
   cancellation remains available to cancel an upload. Keep shooting while
   cloud uploads run independently.

Keep AirPix in the foreground. Back navigation keeps reception active, but
backgrounding, changing events, or **Stop receiving** stops new reception and
requests release of the camera connection.
Already queued images retain their original event/album and continue uploading.
The phone screen stays awake during reception. Camera originals are never deleted.
On iOS, Stop waits for confirmed native release. If release fails or times out,
follow the displayed USB-disconnect instruction before starting another session.

## Choosing what to upload

| USB upload mode | Behavior |
| --- | --- |
| **New shots only** | Skips card objects already present when the session is armed. Receives each supported new photo automatically after the ready message. |
| **Existing photos + new shots** | Receives readable supported still photos already on the card and keeps receiving new photos. New-shot transfers take priority between complete files; one file already copying is allowed to finish. |

The choice is fixed for the receiving session, together with the event, album and
enhancement setting. Changing it requires stopping and starting reception. Both
modes start cloud uploads automatically; neither adds a manual Upload step.
Card metadata is discovered in small batches so a large existing collection does
not monopolize the connection. Completed/cancelled transfer identities prevent
identical retained camera objects from being queued again for the same event and
source, including after reconnecting. Camera object identity is based on the
camera's reported identifiers and metadata, not a cryptographic content match.

Existing photos + new shots is available through the Canon EOS, Nikon and
explicitly shooting-capable standard card routes when their required operations
succeed. The current Sony PC Remote adapter receives the new-photo transfer
queue; it does not implement older-card access during shooting. Selecting the
combined mode for that adapter gives a specific explanation and closes the
session without switching to file-import mode. Select New shots only for Sony
live shooting, or stop reception and import older photos separately. Sony's newer
model-dependent Background File Transfer capability requires a separate adapter.
A Sony queue left from an earlier connection must still be resolved before a
new-shots session can start; it is never consumed to manufacture a clean baseline.

The phone uses temporary transfer/retry storage, not a manual gallery-import
step. The temporary queue copy is deleted after the cloud returns a valid event
photo ID. A cloud outage keeps the retry copy and shows a waiting status; it does
not mark the photo uploaded. Receipt/ACK to the camera does not wait for internet
delivery, so the camera can send its next shot while earlier photos upload.

## How shooting is enabled

| Profile | Connection behavior |
| --- | --- |
| Canon EOS | Enables the supported remote/event protocol, verifies a card recording destination, polls new-shot events and reconciles new card objects. Does not issue a UI-lock or remote-shutter command. Regular EOS M/PowerShot variants are excluded except the regular M6 Mark II path. |
| Nikon | Selects body-control mode when the camera advertises that command, then receives vendor events and scans card handles. PC-memory captures require a different adapter and stop this card-recording workflow. |
| Sony | Runs the SDIO/PC Remote connection handshake, selects or confirms **Camera** control priority and **PC + Camera** still-image storage, then reads complete new-photo queue entries. These camera settings remain after Stop. |
| Fujifilm | Detected but excluded until a dedicated adapter implements its ordered volatile-buffer lifecycle. Native physical-shutter capability does not enable the generic card route for Fuji. |
| Other camera | Uses the standard card/event route only when iOS explicitly advertises physical-shutter support and the required card operations succeed; otherwise reports that the connection needs a supported adapter. |

USB mode names vary by model. Sony commonly requires PC Remote; its camera-side
priority and save destination may need manual selection when they cannot be set
through the connection. Do not choose Mass Storage, Card Reader or USB Streaming
for this workflow. The app reports a specific setup error if required operations
or property readbacks are missing; it does not claim ready merely because files
can be browsed.

If the camera screen or shutter is locked, tap **Camera locked? Release
connection**, disconnect USB, check the model's tethering settings and reconnect.
**Test wired camera connection > Copy report** performs passive discovery and
provides the camera/OS/capability report for investigation without opening a new
import session.

## Native lifecycle and transfer reliability

The new native methods on `airpix/otg_picker` are:

| Method | Responsibility |
| --- | --- |
| `openPtpTetherSession` | Discover/authorize one camera and exclusively own its native transport. |
| `sendPtpTetherCommand` | Exchange bounded protocol datasets; photo reads must use the streaming method. |
| `downloadPtpTetherObject` | Save one complete object using a stable logical `transferId`, expected name and size. |
| `acknowledgePtpTetherFiles` | Release staged-file bookkeeping only after durable local queue persistence. |
| `closePtpTetherSession` | Close only the matching session; on iOS wait for confirmed native release. Preserve completed staging for a late local save. |

Raw notifications arrive through `airpix/otg_live`. Every operation/event carries
its session token. Polling reconciles lost notifications, transfers are serialized,
and a completed download can finish saving to its original event after Stop.
Old-session acknowledgements cannot send vendor commands into a new session.
The legacy native live methods remain for compatibility and tests; the production
`LiveCameraCapture` default now selects `PtpTetherCameraTransport`.

iOS tracks the exact camera/session owner until ImageCaptureCore confirms closure
or detachment. It gives a close request eight seconds; an error or expired deadline
returns `PTP_CLOSE_FAILED` or `PTP_CLOSE_TIMEOUT` without clearing that guard.
`PTP_CLOSE_PENDING` blocks a new operation while closure is still pending. Manual
import and the legacy receiver share this protection. A late open after Stop is
closed before reuse, and an old close callback cannot release a later owner.
The UI preserves release errors and queued cloud uploads continue independently.

Sony reuses a consumptive RAM handle. AirPix therefore assigns a distinct logical
ID to each photo, retains its completed native staging file, and does not read
that handle again under the old ID after an ambiguous or failed consumed transfer.
Canon host-transfer completion is sent only after durable local persistence.
Invalid lengths, truncated packets and session mismatches cannot publish a partial
photo. No camera DeleteObject or remote-shutter operation is issued.

## Guest QR while receiving

The transfer page's QR action remains available while photos upload and refers to
the same receiving event. Already-enabled face delivery is checked without a
settings write, so sharing it does not require management permission. Enabling
it still requires the existing authorization. QR preparation owns its loading
dialog; dismissing it or navigating elsewhere cannot later close the transfer
page or show a stale QR. Album assignment, publication/review and guest-access
rules remain unchanged. See [CAMERA_LIVE_TRANSFER.md](CAMERA_LIVE_TRANSFER.md#guest-qr-delivery).

## Verification status

The latest automated results are recorded in
[CAMERA_LIVE_TRANSFER.md](CAMERA_LIVE_TRANSFER.md#validation-and-device-acceptance).
The full Flutter suite has **239 passing tests**, analysis is clean, and a fresh
Android debug APK build succeeded. Three integration tests connect the real
protocol/controller/queue pipeline to simulated native and cloud boundaries.
The tests cover binary protocol fixtures, vendor handshakes and readbacks, new-shot
baselines, bursts, fixed/reused handles, streaming, cancellation and staging
retries. These use simulated cameras and cannot certify physical compatibility.

The Windows workspace can compile/test Android and Flutter. The iOS source and
RunnerTests require macOS/Xcode. Its **44 iOS tests**, including 13 new release
cases, remain **uncompiled and unrun**; signing and installation are also pending.
No phone/camera hardware was attached for an end-to-end capture test.

Before approving a camera model, verify its firmware and USB mode, take a photo
with the physical shutter, inspect it on the camera and in AirPix, change camera
exposure controls, shoot a burst, reconnect, and interrupt a transfer. Confirm
New shots only skips old card photos. Then test Existing photos + new shots with
an existing card collection and a new burst; confirm new shots take priority and
reconnecting does not upload already accepted photos again. In both modes, verify
the right event, cancellation, and delayed cloud delivery during an internet outage.

Wireless automatic shooting uses the existing camera FTP receiver, with automatic
transfer enabled on cameras that support FTP. Its setup and review/cancellation
behavior are documented in [CAMERA_LIVE_TRANSFER.md](CAMERA_LIVE_TRANSFER.md).
