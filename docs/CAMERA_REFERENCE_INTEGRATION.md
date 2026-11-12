# Live camera integration — 2026-11-13

The mobile app now selects shooting-mode PTP on **both iOS and Android** after
the photographer presses **Connect & start**. The previous platform handlers
returned `USE_START_RECEIVING` for every PTP method and the transport selector
always chose a catalog import receiver. That prevented the existing vendor
drivers from running at all.

Native ownership is isolated in `SimpleUsbCameraReceiver`: ImageCaptureCore on
iOS, raw USB bulk/interrupt endpoints on Android. Catalog import is a separate
explicit transport, never an automatic recovery from failed live negotiation.
Discovery does not start at app launch. iOS requests contents and control
authorization for tethering, forwards PTP notifications and waits for confirmed
session release before allowing another owner. Android supports known camera
vendor interfaces as well as still-image interfaces and serializes commands.

Each complete shot enters the existing durable upload queue **before** its
camera transfer is acknowledged. Internet delivery runs independently. Burst
events, missed notifications, DeviceBusy replies and local persistence retries
are covered by the camera tests. A downloaded Sony RAM object retains its
transfer identity so a retry cannot accidentally consume the next shot.

## Reviewed reference code

These are source revisions inspected for protocol behavior, not dependencies
copied wholesale into the Flutter app. The implementations remain in Dart,
Swift and Kotlin; no React Native, Capacitor, desktop bridge, vendor SDK or
libgphoto2 binary was introduced.

| Reference / reviewed revision | Relevant code and integration |
| --- | --- |
| [expo-sony-camera](https://github.com/jongan69/expo-sony-camera/tree/b789e93cb6cbcd4a0e5528e82da58c964de567a1) — MIT | `ios/SonyPtpTransport.swift`, Android `SonyPtpTransport.kt`: older Sony `0x9202 [0xC8]` authentication; `D215` readiness and `FFFFC001` image queue. Added bounded V2 negotiation fallback after an explicit V3 rejection. |
| [CrCmd.DPCC.ios](https://github.com/sohtamei/CrCmd.DPCC.ios/tree/c46fc57b45233421c4d95ee358ae067b7d0285dc) — Apache-2.0 | `CameraManager.swift`, `PTPDef.swift`: Sony `9201` stages 1/2/3 with `9202 [0x12C,1]` negotiation between stages 2 and 3. Retained V3 parsing and physical-camera priority requirements. |
| [open-eos-control](https://github.com/js051/open-eos-control/tree/089e71a3fb3249164d36173b04b682c5612d3966) — Apache-2.0 | `AndroidUsbPtpTransport.kt`, `UsbPtpCameraBackend.kt`, `CanonEosPtp.kt`: native USB framing, EOS remote/event preparation, object-transfer notifications and completion. Reconnected the existing Canon driver and added `C1B6` card-object notification recognition with authoritative ObjectInfo lookup. Existing Canon CCAPI receiving remains available. |
| [ZENCHE](https://github.com/Tauber01/ZENCHE/tree/52d60af0b4b532ec862904c8787f43364d57e2c3) — MIT | Android `PtpCamera.java` / `PtpIpCamera.java` and Apple camera services: vendor-specific transactions and serialized physical-camera lifecycle. Its remote-capture flow temporarily selects Nikon host control; this app keeps body priority `90C2 [0]` for the requested physical-shutter workflow. |
| [aero-shutter](https://github.com/subhashraveendran/aero-shutter/tree/b7f5596392dae2e31674ad95ca412e4ca4dcf962) — MIT | `internal/ptpip/client.go`, `internal/camera/camera.go`, mobile `ptpip/client.ts` / `camera.ts`: separate command/event TCP sockets and event-driven import. Wired the existing Dart PTP/IP client into **Wireless → Nikon Wi-Fi (PTP/IP)**; added ObjectAdded wake-ups, event ping responses, a complete old-photo baseline and local-save-before-ACK delivery. |

The two Sony references name ImageCaptureCore's callback buffers differently
from [Apple's documented response/data order](https://developer.apple.com/documentation/imagecapturecore/iccameradevice/requestsendptpcommand(_:outdata:completion:)).
The bridge recognizes a structurally valid, bounded PTP response container in
either ordering. It never infers success from a missing response or strips image
payload bytes. Invalid framing ends the session.

Sony V3 requests the full property set with `9209 [0]`, then uses the reference's
`9209 [1]` difference query. Delta replies merge into confirmed state so an
omitted, unchanged Camera priority or save destination does not falsely end
the session. V2 retains the parameterless query used by expo-sony-camera.

## Protocol coverage and limits

| Family | Receiving path / prerequisites |
| --- | --- |
| Sony | USB PC Remote / Remote Shooting, V2 or V3; destination PC+Camera / Dest.+Camera (`D222=17`), Camera priority (`D25A=0`). New RAM-queue photos only. A pre-existing RAM queue must be completed before arming a new-shots-only session. |
| Canon EOS | USB EOS remote/event protocol with camera-card recording; card reconciliation plus host-transfer events. CCAPI remains available on models where enabled. |
| Nikon | USB PTP with physical-camera priority and card recording. Wi-Fi PTP/IP port 15740 is available through the new explicit wireless option on compatible models. |
| Fujifilm | Existing USB tether adapter with verified tether mode; card polling where exposed, otherwise new-object notifications. |
| Panasonic / LUMIX | Existing vendor adapter verifies recording target before receiving. |
| OM SYSTEM / Olympus | Existing OM adapter verifies/restores its supported connection setting and camera-card target. |
| Pentax / Ricoh / other PTP | Existing standard adapter requires the native platform to confirm physical-shutter capability; unverified models fail with setup guidance. This is not universal Pentax tether support. |
| Camera FTP | Existing foreground FTP auto-send receiver works with models that expose automatic FTP transfer. |

## Second review: physical shutter and iOS ownership

All five GitHub heads were fetched and rechecked on 2026-11-13; their revisions
in the table above are unchanged. The remote-control demos are not equivalent
to leaving the photographer in control of the camera. In particular,
`expo-sony-camera` prepares PC priority with `D25A=1`, and CrCmd's
`setupCamera` does the same. Those setup writes are not copied into AirPix.

- Sony now returns an advertised, writable PC-priority setting to **Camera**
  (`D25A=0`) instead of simply refusing the session. The permitted write is
  exactly `9205 [D25A]` for V2 or `9205 [D25A,1]` for V3, with one zero byte.
  Six bounded full-property reads must confirm Camera priority. A successful
  write reply alone is insufficient. Unknown/read-only modes fail and release
  USB. PC priority is never restored on Stop. Recording destination and exposure
  settings are not written. Dart, Swift and Kotlin enforce the same exception.
- The iOS receiver previously emitted `catalogAdded`, while Dart only handled
  `catalogHint`. It now sends the expected event with file name and size, walks
  new folder contents and forwards removals and catalog-ready notifications.
  Dart also accepts the older event name. These are same-session hints, not a
  fallback to import mode. This restores event-only Fuji delivery and allows
  reused camera handles to represent subsequent shots.
- Reattaching a Flutter listener cancels its stale cleanup timer. A new session
  after hot restart first closes the orphan native owner and waits for confirmed
  release. Failed close still blocks reopening. Camera access restrictions end
  and release the current session instead of leaving it polling indefinitely.
- Native authorization preserves denied, restricted, pending and unavailable
  states. Obsolete XCTest cases for the deleted native catalog index were
  removed; authorization tests now target the mapping used by the receiver.
- ZENCHE's iOS `Connectivity/RemoteCaptureServices.swift` is a PTP/IP client;
  its `Camera/CameraService.swift` uses AVFoundation. Video streaming is not an
  original-photo USB tether driver and is not substituted for receiving photos.

On Nikon models with the option, select **Setup → USB connection priority →
Shooting before connecting USB**. Nikon explicitly documents a blank monitor
under Upload and an active monitor under Shooting. Returning protocol control
with `90C2 [0]` cannot by itself certify that camera-side display setting.
See [Nikon's USB connection priority manual](https://onlinemanual.nikonimglib.com/z9/en/sum_usb_connection_priority_307.html).

The app never opens a remote live-view session, sends a physical-shutter lock
command or selects Mass Storage. Manufacturer firmware still determines which
operations can overlap exposure and transfer. Shutter availability and display
behavior require a real-camera test on each model/firmware/iPhone combination.

No software can make every camera support simultaneous shooting and transfer.
Mass Storage, camera UVC video and firmware that locks the local display/shutter
cannot provide this workflow. iPhone hardware, adapter power, iOS visibility,
camera model, firmware and permissions all matter. SnapBridge pairing alone is
not a generic PTP/IP endpoint. Manufacturer setup names vary by model.

Keep AirPix open. After the ready message, take a physical test shot and verify
that the display stays usable, the shot appears locally, then cloud registration
completes. Camera originals are retained. Without internet, photos stay queued.

## Verification

217 focused Flutter tests passed after the second review. They cover protocol negotiation, Sony V2/V3 and consumptive
queue identities, all existing USB vendor adapters, burst capture and retries,
PTP/IP baseline/download/event/ping behavior, address validation, upload-page
wireless setup/cancellation, and transfer presentation. Native Swift callback
and command-policy regression tests were updated for Xcode.

No app build or lint was run, as requested. Native iOS/Android compilation and
physical-camera checks still need the user's device builds; host-side tests do
not certify model compatibility or prove the display stays enabled.
