# USB physical-shutter receiving

The intended workflow is: choose a shooting-capable USB mode, connect the
camera to the phone, start Live shooting, and press the camera's own shutter.
Received files go through the existing durable local upload queue before native
transfer acknowledgement. Cloud upload is a separate state and needs internet.
AirPix must remain open while receiving.

## Added adapters

| Family | Connection and protocol requirements | Behavior | Verification status |
| --- | --- | --- | --- |
| Panasonic / LUMIX | PC(Tether), standard card-object operations, capture-target read `0x940A`; write `0x940B` when a change is needed | Selects SD-card target `0`, confirms readback, handles `0xC108` card events and periodic card discovery | Automated wire/flow tests; physical iPhone/model testing pending |
| Olympus / OM SYSTEM | OM-D style PTP protocol, advertised `0x9486`, standard property operations; control `0xD052` and target `0xD0DC` must have known UINT16 values and advertise a writable enumeration if changed | Reads the original control mode, requests PC control `1`, sets camera-card target `2`, confirms readback, restores the original control mode on stop/failed setup | Automated wire/flow tests; physical iPhone/model testing pending |
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
  The setter uses parameter `0` with that tuple as outgoing data. Target `0`
  is card, `1` is RAM and `2` is both. Unknown/malformed replies fail closed.
- OM properties are read through standard `GetDevicePropDesc`/`GetDevicePropValue`
  and written only when the descriptor permits the requested value. Storage is
  primed before PC control and the new-shot baseline is taken afterwards.
- OM `0xC002`/`0xC102` are card-object events; `0xC008`/`0xC108` are property
  events. Preview/direct-store notifications are not treated as card files.
  Event decoding is vendor-specific: `0xC108` has a different LUMIX meaning,
  and OM `0xC101` must not be decoded as a Nikon RAM photo.
- Recording settings are checked on periodic card scans. A changed target or
  a LUMIX RAM-object notification stops receiving instead of consuming host-only
  captures. No new adapter sends shutter, live-view, delete, format or UI-lock
  commands. Card recording remains selected after disconnect.
- OM control restoration is attempted only after pending PTP work settles.
  Failure or timeout still closes the native session and reports that the user
  must unplug USB and check the camera controls. Unplugging during a session
  cannot be repaired with commands to a disconnected device.
- PTP negotiation cannot establish that the LCD, viewfinder, focus controls and
  physical shutter all remain usable. No model is hardware-certified by these
  tests. iOS may also decline to expose a camera in its vendor tethering mode.

## Source references

Wire facts were checked against libgphoto2 commit
`26a57b27caeb865a6b1d415aa5a80b47837c9023`; no libgphoto2 dependency is added.
The Dart adapters are independently implemented against those protocol facts.

- [PTP vendor commands and events](https://github.com/gphoto/libgphoto2/blob/26a57b27caeb865a6b1d415aa5a80b47837c9023/camlibs/ptp2/ptp.h)
- [LUMIX target packet and OM PC-mode transactions](https://github.com/gphoto/libgphoto2/blob/26a57b27caeb865a6b1d415aa5a80b47837c9023/camlibs/ptp2/ptp.c)
- [Capture-target property choices](https://github.com/gphoto/libgphoto2/blob/26a57b27caeb865a6b1d415aa5a80b47837c9023/camlibs/ptp2/config.c)
- [Panasonic: tethered recording / PC(Tether)](https://help.na.panasonic.com/answers/how-to-use-tethered-recording-lumix-s-series/)
- [Olympus: tethered shooting setup](https://learnandsupport.getolympus.com/learn-center/photography-tips/technique/tips-on-tethered-shooting)
- [pkTriggerCord: Pentax SCSI-based desktop transport](https://github.com/asalamon74/pktriggercord/blob/master/README.md)

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
