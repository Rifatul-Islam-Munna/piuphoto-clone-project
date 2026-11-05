# USB tether protocols

## Scope and compatibility

`PtpTetherCameraTransport` implements camera-specific preparation, new-shot discovery, download and shutdown for Canon EOS, Nikon and Sony. A standard PTP fallback requires an explicit native physical-shutter capability and excludes Fujifilm. A brand match alone does not establish compatibility: advertised operations, property permissions and required readbacks must pass before monitoring starts.

This is an implementation inventory, **not a hardware-certified model list**. Physical compatibility remains untested. Camera firmware and its selected USB mode determine whether its shutter, display and other controls remain available. There is no universal iOS “remote tether session” flag that overrides a camera's file-transfer mode. Mass-storage/card-reader connections cannot provide this workflow. Keep the receiving app in the foreground.

Shared policy/parsers live in `mobileapp/lib/core/platform/ptp_tether_camera.dart` and `ptp_tether_codec.dart`; `ptp_tether_link.dart` defines the native boundary. Native transport ownership is separate from vendor negotiation. The receiver sends no remote-shutter, UI-lock, live-view or camera-file deletion commands.

## Implemented adapters

### Canon EOS

Regular EOS handling requires advertised SetRemoteMode `0x9114`, SetEventMode `0x9115` and GetEvent `0x9116`. Initialization sends remote mode `1`, then event mode `1`. PowerShot and EOS M models are excluded, except the EOS M6 Mark II pattern; this exception still requires every capability gate.

GetEvent supplies capture destination `0xD11C` and its choices. The receiver retains a nonzero card destination other than host-only `4`; if necessary, it selects an advertised card choice using SetDevicePropValueEx `0x9110` and confirms the value through subsequent events. Optional RequestDevicePropValue `0x9127` assists refresh. An unconfirmed destination prevents arming. DeviceInfo is reread after negotiation because advertised operations can change.

The parser handles card-object and host-transfer notifications, including extended formats. GetObjectInfo remains authoritative; only verified classic `0xC186` transfer-event metadata may substitute when its RAM handle rejects ObjectInfo. Host-transfer completion `0x9117` follows durable local persistence. Shutdown attempts remote mode `0`, then `1`, then event mode `0`, retaining card recording.

### Nikon

When advertised, ChangeCameraMode `0x90C2` receives `0`, returning control to the camera body. Full PC-control mode `1` is never requested. Without that operation, startup requires the native physical-shutter capability.

GetEventEx `0x941C` is preferred over GetEvent `0x90C7` when advertised. Events supplement card reconciliation. A PC-memory-transfer notification ends monitoring with recording-mode guidance instead of guessing RAM-transfer semantics. Shutdown attempts body mode `0` again. Successful command acceptance is not hardware proof of every body control.

### Sony

SDIO Connect `0x9201` uses phases `[1,0,0]`, `[2,0,0]`, then GetExtensionDeviceInfo `0x9202` with `[0x12C,1]`, followed by Connect `[3,0,0]`. The decoder supports property layouts 2/`0xC8` and 3/`0x12C`; other layouts fail explicitly. Advertised extension operations augment DeviceInfo.

GetAllDevicePropData `0x9209` must expose:

| Property | Required value |
| --- | --- |
| StillImageStoreDestination `0xD222` | `17`: PC + Camera |
| PriorityMode `0xD25A` | `0`: Camera |
| ObjectInMemory `0xD215` | Valid queue state |

SetControlDeviceA `0x9205` changes a property only if writable and the desired value is selectable; subsequent reads must confirm it. Application priority `1` and RAM-only destination `1` are never used to force configuration. Camera priority and card-plus-PC recording remain enabled after stop.

Startup requires an idle queue (`0` or `0x8000`); old queued photos are not consumed to manufacture a baseline. Only `0xD215 > 0x8000` triggers ObjectInfo/full GetObject for fixed RAM handle `0xFFFFC001`. Interrupt ObjectAdded alone is insufficient. One logical transfer remains pending until local persistence is acknowledged, preventing a retry from consuming the next shot. Connect phase 3 opens the connection; it is not a disconnect command.

Successful but empty extension-capability responses during Sony startup are retried up to 20 times with 100 ms between attempts. Nonempty malformed datasets fail immediately; exhausted empty replies never produce a ready session.

### Other detected brands

Fujifilm, Panasonic/LUMIX, OM SYSTEM/Olympus and Pentax/Ricoh are identified by USB IDs, vendor extensions or reported names. Dedicated adapters for these brands are not included. Detection does not establish unrestricted physical shooting; the standard card/event path still requires an explicitly advertised native physical-shutter capability and all required card operations.

Fujifilm is explicitly excluded from that fallback, even when native discovery reports physical-shutter support. Its ordered volatile-buffer lifecycle needs a dedicated adapter; replacing partial reads with full GetObject does not implement those semantics. The build reports `TETHER_CAMERA_UNSUPPORTED` with Fuji-specific setup guidance instead of arming the generic card reader. See the [libgphoto2 Fujifilm transfer investigation](https://github.com/gphoto/libgphoto2/issues/653) and the pinned PTP sources below.

## Upload scope, identity and recovery

Non-Sony adapters require StorageIDs, ObjectHandles, ObjectInfo and GetObject. Existing card handles are snapshotted before arming. `LiveCameraUploadMode.newShotsOnly` (default) skips that initial set; `existingAndNew` schedules it as a bounded card backlog while listening for new-shot events. The scope is immutable for a transport/session and the UI persists the next-session preference. Existing files are discovered in small batches; new photos sort before existing pending files. The controller refreshes pending priority after every successful complete-file save/ACK in combined mode. An in-progress file is not interrupted mid-transfer.

The Sony PC Remote adapter rejects combined mode with `TETHER_EXISTING_PHOTOS_UNAVAILABLE` before the vendor handshake or configuration writes. Standard card-listing opcodes may expose only Sony's synthetic RAM storage, so advertised operations do not prove access to old card images. This adapter never changes into MTP/mass-storage to provide combined import. Sony's newer Background File Transfer is model/firmware dependent and requires a separate implementation.

Default vendor polling is 700 ms; card reconciliation is every three seconds. Card changes require a fresh session. Removed/reused handles receive new generations; unsupported media are skipped. Valid photographs need an authoritative positive size no greater than 512 MiB. Ordinary card transfer IDs remain stable for the same reported camera ID, object handle, filename, capture timestamp and generation across reconnects. They are metadata identities, not cryptographic file hashes. Sony's consumptive RAM queue still requires distinct session-specific logical identities.

A busy, temporarily missing or unfinished card photo no longer aborts the rest of a burst. Metadata discovery retries that handle separately with 500 ms to 8 seconds of backoff; a fresh completion notification can bypass the delay. An invalid handle is retired only after a later complete card scan confirms it absent. Framing, transport, permission and consumptive-transfer failures are not swallowed as temporary metadata errors.

Known XMP/THM/CTG/XML sidecars are ignored. An initial card photo larger than the 512 MiB transfer limit produces a filename-specific error and is skipped for that session, allowing later existing photos to proceed; its camera original is not read or deleted. A new-shot metadata or transport error retains its existing recovery semantics. Temporary filenames and incomplete image metadata remain retryable.

Native staging is keyed by `(sessionId, transferId)`. Completed files survive stop/disconnect; exact-token retries reuse them and late ACKs remain valid. A missing staged Sony photo or an ambiguous consumptive transfer fails explicitly rather than substituting another photograph. ACK clears bookkeeping; Dart owns staging-file deletion after durable queue persistence. Camera originals are retained.

## Native bridge

Method channel: `airpix/otg_picker`. Event channel: `airpix/otg_live`.

| Method | Contract |
| --- | --- |
| `openPtpTetherSession` | `{sessionId,cameraId?}` → session/camera IDs, name, USB IDs, transport, physical-shutter capability |
| `sendPtpTetherCommand` | `{sessionId,opcode,params,outData?}` → actual `responseCode`, unsigned `parameters`, payload `data` |
| `downloadPtpTetherObject` | `{sessionId,transferId,handle,name,expectedSize,partialOpcode?}` → `{path,name,size}` |
| `acknowledgePtpTetherFiles` | `{sessionId,ids}`; old-session ACK accepted |
| `closePtpTetherSession` | `{sessionId}`; exact-owner cleanup, with confirmed iOS release and an eight-second deadline |

Events carry `sessionId` and `type`; `ptpEvent.data` is a complete PTP event container. Metadata calls reject OpenSession/CloseSession and file-read opcodes `0x1009`, `0x101B`, `0x9107`. Photos use native file transfer, never Flutter byte arrays.

| Limit | Value |
| --- | --- |
| Outgoing control data / incoming metadata | 64 KiB / 8 MiB |
| File / partial request | 512 MiB / 1 MiB |
| Android physical USB transfer | At most 16 KiB |
| iOS full GetObject without partial support | 128 MiB |

These are transport limits. The existing cloud image endpoint independently accepts files up to 256 MiB; a native transfer limit is not a promise that every file size is accepted by cloud storage.

Android exclusively claims raw USB; `MtpDevice`, manual import and live sessions cannot overlap. Initial GetDeviceInfo/OpenSession use transaction zero; subsequent transactions start at one. Framing supports fragmentation, coalescing and ZLPs. Commands run off the UI thread; close aborts blocked I/O. Interrupt events use timed requests on Android 26+, with polling on older versions.

iOS uses ImageCaptureCore authorization, session ownership and `requestSendPTPCommand`. ImageCaptureCore assigns transaction IDs and delivers payload separately from the response container. Native partial reads write successive chunks to disk; full GetObject returns one native data callback, hence its lower memory limit. Do not describe that fallback as constant-memory streaming.

Partial-read sizes are maximum requests: a positive shorter chunk is accepted and the next offset advances by actual bytes. Standard response byte counts must match actual payloads. Zero progress, oversized/inconsistent chunks and incomplete final files are rejected. Full GetObject still requires the exact complete size.

Partial-to-full fallback requires the first unsupported-operation response with no transferred data. Timeouts or malformed responses retire the transport. Shutdown serializes vendor cleanup before native close; the native event subscription remains alive through cleanup. Completed files remain deliverable under their original token.

Lost iOS listeners have a three-second exact-owner lease; reattachment or explicit close invalidates the old expiry. Android listener/activity teardown attempts PTP CloseSession only while idle with a one-second bound. Failed/detached streams and active transactions are aborted instead of inserting a close command into an unfinished response.

### Confirmed iOS release

`PtpTetherSessionRelease` retains the exact camera and ended session owner while `requestCloseSession(options:completion:)` runs. Success requires the camera to be detached, or both its opening flag and `hasOpenSession` to be false. A completion callback alone is insufficient. The eight-second deadline bounds the caller's wait; it does not clear an unconfirmed native session.

`PTP_CLOSE_PENDING` prevents a new tether, manual-import or legacy-live operation while release is pending. A failed close reports `PTP_CLOSE_FAILED`; an expired deadline reports `PTP_CLOSE_TIMEOUT`. Both retain the ownership guard until actual closure or detachment. A later state change can release the guard without resolving an already-failed waiter twice. Flutter preserves this failure and tells the user to disconnect USB; it does not replace it with a successful stopped status. Already-queued photos keep uploading.

Manual and legacy session cleanup uses the same release mechanism. If Stop wins during native open, the late open callback is routed back to that exact release owner and closed before another receiver can arm. Old callbacks cannot clear a newer owner's state. Completed staging remains available for its original transfer token.

## Automatic cloud delivery

USB, FTP and existing wireless camera receivers use service-owned `receiveCameraFile` or `receiveCameraBytes` entrypoints. Complete photo receipt starts cloud delivery automatically, without the former five-second review delay or a separate Upload action. A durable retry copy lets camera ACK proceed independently from cloud speed. The transfer page shows actual cloud state; uploaded means the server returned a valid event-photo ID. On success the phone queue file is deleted. Failed or malformed confirmation keeps the same cloud URL and idempotent registration ID for retry. Camera originals are not deleted.

Completed-transfer receipts and cancellation IDs are persisted separately from the bounded display ledger. The receipt key retains the existing event/source/camera-object identity, so reading the same card again does not resend a confirmed photo after its display history is pruned. Only a valid cloud event-photo confirmation creates a receipt. It is persisted before temporary-file cleanup; failure preserves the existing URL and registration boundary for idempotent retry. A crash after receipt persistence finishes local cleanup without another cloud request. Retained successful history from earlier builds is backfilled at service startup.

The transfer page's guest QR uses the receiving event; image registration retains its album. QR preparation reads an already-enabled face-delivery setting without requiring a settings write, while enabling it still follows existing authorization. The loading helper removes only its own dialog route and suppresses the final QR after cancellation, navigation or disposal. This change does not modify backend publication, review or guest-access policies.

## Sources and validation boundary

Protocol behavior was checked against [libgphoto2 PTP sources pinned at `26a57b27caeb865a6b1d415aa5a80b47837c9023`](https://github.com/gphoto/libgphoto2/tree/26a57b27caeb865a6b1d415aa5a80b47837c9023/camlibs/ptp2): `library.c`, `config.c`, `ptp.h`, `ptp.c`, `ptp-pack.c`. Original code implements those protocol facts; libgphoto2 is not bundled.

[Apple's archived PTPPassThrough sample](https://developer.apple.com/library/archive/samplecode/PTPPassThrough/PTPPassThrough.zip) explains pass-through framing/transaction ownership; its macOS sample is not iOS compatibility evidence. See also [ImageCaptureCore](https://developer.apple.com/documentation/imagecapturecore).

[Sony Camera Remote Command](https://support.d-imaging.sony.co.jp/app/cameraremotecommand/en/index.html?id=portal) documents Background File Transfer as a separate capability and directs developers to model-specific command compatibility. The libgphoto maintainer's [A6300 PC Remote issue](https://sourceforge.net/p/gphoto/bugs/1038/) explains the older PC Remote limitation on reading card files. These sources do not establish support for that newer capability in this adapter.

The supplied [camera-connect-sdk repository](https://github.com/18818474455/camera-connect-sdk/tree/fb066ee7c3e201c09778aa362fee4445556e862e) contains documentation/assets and a demo APK release, but no public installable SDK source, package or license file. Its README describes iOS as closed TestFlight beta; its architecture article labels API examples illustrative. No proprietary demo implementation was incorporated.

Latest Windows verification: **239 Flutter tests passed**, including 56 PTP workflow/native-contract cases and 23 codec cases; Flutter analysis is clean and the fresh Android debug APK build succeeded. Three integration tests exercise the real protocol/controller/cloud queue with temporary JPEG files and simulated native/HTTP boundaries. Detailed results are in [CAMERA_LIVE_TRANSFER.md](CAMERA_LIVE_TRANSFER.md#validation-and-device-acceptance).

The iOS target contains **44 tests**, including 13 new release-lifecycle cases. **Native iOS changes remain uncompiled and XCTest execution unrun without Xcode; physical camera compatibility is untested.** Protocol/staging tests exercise synthetic traffic, not camera firmware.
