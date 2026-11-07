import Foundation
import ImageCaptureCore
import Darwin

struct PtpTetherFailure: Error {
  let code: String
  let message: String
  let diagnostics: [String: String]

  init(code: String, message: String, diagnostics: [String: String] = [:]) {
    self.code = code
    self.message = message
    self.diagnostics = diagnostics
  }

  func forOperation(_ opcode: UInt16) -> PtpTetherFailure {
    var details = diagnostics
    details["operation"] = String(format: "0x%04X", opcode)
    return PtpTetherFailure(code: code, message: message, diagnostics: details)
  }
}

struct PtpTetherReply {
  let responseCode: UInt16
  let parameters: [UInt32]
  let data: Data
}

struct PtpTetherStagedFile {
  let path: String
  let name: String
  let size: Int
}

/// ImageCaptureCore is a safety net, never the primary tether protocol. Only
/// failures that mean "this exact object could not be read through PTP" may
/// try the framework's file-download API. Transport/session/storage failures
/// must keep their original error instead of silently changing ownership.
enum PtpImageCaptureFallbackPolicy {
  private static let eligibleCodes: Set<String> = [
    "PTP_OBJECT_NOT_READY",
    "PTP_INCOMPLETE_FILE",
    "PTP_FILE_TOO_LARGE",
  ]

  static func shouldTry(code: String, handle: UInt32, expectedSize: Int) -> Bool {
    handle > 0 && expectedSize > 0 && expectedSize <= PtpTetherCodec.fileLimit &&
      eligibleCodes.contains(code)
  }
}

/// Main-queue lease for an EventChannel listener. A lost Flutter receiver must
/// release its native camera, while a quick reattachment invalidates old timers.
final class PtpTetherListenerLease {
  private let schedule: (DispatchWorkItem) -> Void
  private var timeout: DispatchWorkItem?
  private var generation: UInt64 = 0
  private(set) var isDetached = false

  init(schedule: @escaping (DispatchWorkItem) -> Void = {
    DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: $0)
  }) {
    self.schedule = schedule
  }

  func attach() {
    generation &+= 1
    isDetached = false
    timeout?.cancel()
    timeout = nil
  }

  func detach(onExpired: @escaping () -> Void) {
    generation &+= 1
    let detachedGeneration = generation
    isDetached = true
    timeout?.cancel()
    let task = DispatchWorkItem { [weak self] in
      guard let self, self.isDetached, self.generation == detachedGeneration else { return }
      self.generation &+= 1
      self.timeout = nil
      onExpired()
    }
    timeout = task
    schedule(task)
  }

  func invalidate() { attach() }
}

/// A close request is not a release confirmation. Keep the exact camera owner
/// blocked after a failure/timeout until its session is actually closed or the
/// device is detached. All callbacks and state reads run on the main queue.
final class PtpTetherSessionRelease {
  struct CameraState {
    let connected: Bool
    let opening: Bool
    let open: Bool

    var isReleased: Bool { !connected || (!opening && !open) }
  }

  typealias Outcome = Result<Void, PtpTetherFailure>
  let sessionID: String
  private var endedOwnerIDs: Set<String>
  private let state: () -> CameraState
  private let requestClose: (@escaping (Error?) -> Void) -> Void
  private let schedule: (DispatchWorkItem) -> Void
  private let onReleased: (PtpTetherSessionRelease) -> Void
  private let onFailure: (PtpTetherSessionRelease, PtpTetherFailure) -> Void
  private var timeout: DispatchWorkItem?
  private var waiters: [(Outcome) -> Void] = []
  private var outcome: Outcome?
  private var started = false
  private var closeRequested = false
  private(set) var isReleased = false
  private(set) var failure: PtpTetherFailure?

  init(
    sessionID: String,
    state: @escaping () -> CameraState,
    requestClose: @escaping (@escaping (Error?) -> Void) -> Void,
    schedule: @escaping (DispatchWorkItem) -> Void = {
      DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: $0)
    },
    onReleased: @escaping (PtpTetherSessionRelease) -> Void,
    onFailure: @escaping (PtpTetherSessionRelease, PtpTetherFailure) -> Void = { _, _ in }
  ) {
    self.sessionID = sessionID
    endedOwnerIDs = [sessionID]
    self.state = state
    self.requestClose = requestClose
    self.schedule = schedule
    self.onReleased = onReleased
    self.onFailure = onFailure
  }

  func includesOwner(_ id: String?) -> Bool {
    guard let id else { return false }
    return endedOwnerIDs.contains(id)
  }

  func includeEndedOwner(_ id: String) {
    // A cancelled start can still be waiting for its predecessor's close.
    // Both ended owners must receive that same exact native close outcome.
    endedOwnerIDs.insert(id)
  }

  func wait(_ completion: @escaping (Outcome) -> Void) {
    if let outcome { completion(outcome) }
    else { waiters.append(completion) }
  }

  func begin() {
    guard !started else { return }
    started = true
    let task = DispatchWorkItem { [weak self] in
      guard let self, !self.isReleased, self.outcome == nil else { return }
      if self.state().isReleased { self.confirmRelease() }
      else {
        self.fail(PtpTetherFailure(
          code: "PTP_CLOSE_TIMEOUT",
          message: "iPhone has not confirmed that the camera connection was released. Disconnect the USB cable before reconnecting. Photos already received continue uploading."
        ))
      }
    }
    timeout = task
    schedule(task)
    cameraStateChanged()
  }

  func cameraStateChanged() {
    guard started, !isReleased else { return }
    let current = state()
    if current.isReleased { confirmRelease(); return }
    // Stop can arrive during requestOpenSession. Its late open callback must
    // be closed before allowing another receiver to use this camera.
    guard !current.opening, current.open, !closeRequested else { return }
    closeRequested = true
    requestClose { [weak self] error in self?.nativeCloseCompleted(error) }
  }

  func nativeCloseCompleted(_ error: Error?) {
    guard !isReleased else { return }
    if state().isReleased { confirmRelease(); return }
    let detail = error.map { " \($0.localizedDescription)" } ?? ""
    fail(PtpTetherFailure(
      code: "PTP_CLOSE_FAILED",
      message: "iPhone could not confirm release of the camera connection. Disconnect the USB cable before reconnecting. Photos already received continue uploading.\(detail)"
    ))
  }

  private func confirmRelease() {
    guard !isReleased else { return }
    isReleased = true
    failure = nil
    timeout?.cancel()
    timeout = nil
    outcome = .success(())
    let callbacks = waiters
    waiters.removeAll()
    onReleased(self)
    callbacks.forEach { $0(.success(())) }
  }

  private func fail(_ failure: PtpTetherFailure) {
    guard !isReleased, outcome == nil else { return }
    self.failure = failure
    timeout?.cancel()
    timeout = nil
    outcome = .failure(failure)
    let callbacks = waiters
    waiters.removeAll()
    onFailure(self, failure)
    callbacks.forEach { $0(.failure(failure)) }
    // Do not mark released here. A late native completion/detach can still
    // release this owner, but cannot resolve its failed waiter a second time.
  }
}

/// Only PTP framing lives here. Camera-specific mode negotiation is owned by
/// the shared Dart driver, which also owns camera-specific shutdown.
enum PtpTetherCodec {
  static let metadataLimit = 8 * 1024 * 1024
  static let outgoingLimit = 64 * 1024
  static let fileLimit = 512 * 1024 * 1024
  static let wholeObjectLimit = 128 * 1024 * 1024
  static let partialChunkSize = 1024 * 1024

  static func command(opcode: UInt16, parameters: [UInt32]) throws -> Data {
    guard opcode != 0, parameters.count <= 5 else {
      throw PtpTetherFailure(code: "PTP_INVALID_ARGUMENT", message: "Invalid PTP command parameters.")
    }
    var bytes = Data()
    append32(UInt32(12 + parameters.count * 4), to: &bytes)
    append16(1, to: &bytes)
    append16(opcode, to: &bytes)
    // ImageCaptureCore's PTPCamera device module assigns the transaction ID.
    // Apple documents this in its PTPPassThrough sample, PTPProtocolHelpers.h.
    append32(0, to: &bytes)
    parameters.forEach { append32($0, to: &bytes) }
    return bytes
  }

  static func decode(
    response: Data, data: Data, maximumData: Int
  ) throws -> PtpTetherReply {
    // Apple's block callback is (response, data, error). Never infer success
    // from missing response bytes or interchange the two callback arguments.
    func invalid(_ reason: String) -> PtpTetherFailure {
      var details = [
        "decoderReason": reason,
        "responseBytes": String(response.count),
        "dataBytes": String(data.count),
      ]
      if response.count >= 4 { details["declaredLength"] = String(read32(response, 0)) }
      if response.count >= 6 { details["containerType"] = String(read16(response, 4)) }
      if response.count >= 8 { details["responseCode"] = String(format: "0x%04X", read16(response, 6)) }
      // Only PTP control-response bytes, NEVER the photo/data payload. This
      // makes failures diagnosable from an actual camera instead of guessing.
      details["responsePrefixHex"] = response.prefix(32)
        .map { String(format: "%02X", $0) }.joined()
      return PtpTetherFailure(
        code: "PTP_INVALID_RESPONSE",
        message: "Camera detected, but its PTP command reply could not be decoded. The camera USB setting may be correct; this alone does not prove a mode or cable problem.",
        diagnostics: details
      )
    }
    // A PTP response container has at most five 32-bit parameters (32 bytes).
    // ImageCaptureCore owns the callback buffer and may include padding. Do
    // not guess how large that buffer must be: bound the declared PTP length
    // to 12...32 bytes, and read only those declared response bytes.
    guard response.count >= 12 else {
      throw invalid("response-buffer-size")
    }
    let declaredLength = Int(read32(response, 0))
    // Apple's PTPPassThrough response parser uses the declared container size,
    // separately from NSData.length. A fixed/padded buffer is not a bad reply.
    // Read only declared parameters; never treat trailing padding as parameters.
    guard declaredLength >= 12, declaredLength <= response.count,
          declaredLength <= 32, (declaredLength - 12) % 4 == 0 else {
      throw invalid("declared-length")
    }
    guard read16(response, 4) == 3 else { throw invalid("container-type") }
    // Do not guess a numeric range for proprietary PTP response codes.
    // Pass the actual code up; only PTP_RC_OK (0x2001) is treated as success.
    var parameters: [UInt32] = []
    for offset in stride(from: 12, to: declaredLength, by: 4) {
      parameters.append(read32(response, offset))
    }
    // The callback belongs to its exact active Command instance. Comparing
    // the response transaction ID with the placeholder would reject valid
    // commands because ImageCaptureCore replaces that ID. Apple's sample also
    // reads inData directly as the dataset: it has no USB data-container header.
    // Keep every payload byte, including bytes that happen to resemble one.
    guard maximumData >= 0, data.count <= maximumData else {
      throw PtpTetherFailure(code: "PTP_DATA_LIMIT", message: "The camera returned more data than this operation permits.")
    }
    return PtpTetherReply(responseCode: read16(response, 6), parameters: parameters, data: data)
  }

  static func validateChunk(_ reply: PtpTetherReply, opcode: UInt16, requested: Int) throws {
    let partial = opcode == 0x101B || opcode == 0x9107
    // Partial-object's count is a maximum, not a promise of that many bytes.
    // Advance by the actual payload, then verify the complete file at the end.
    guard requested > 0, !reply.data.isEmpty, reply.data.count <= requested,
          partial || reply.data.count == requested else {
      throw PtpTetherFailure(code: "PTP_INCOMPLETE_FILE", message: "The camera did not send the complete requested photo data. No partial photo was uploaded.")
    }
    if opcode == 0x101B, let reported = reply.parameters.first, reported != UInt32(reply.data.count) {
      throw PtpTetherFailure(code: "PTP_INCOMPLETE_FILE", message: "The camera's transferred-byte count does not match its photo data.")
    }
  }

  static func canFallbackToWholeObject(
    _ reply: PtpTetherReply, partialOpcode: UInt16?, receivedBytes: Int
  ) -> Bool {
    // A new GetObject is safe only when the first partial operation explicitly
    // reports OperationNotSupported without returning any photo bytes.
    (partialOpcode == 0x101B || partialOpcode == 0x9107) &&
      receivedBytes == 0 && reply.responseCode == 0x2005 && reply.data.isEmpty
  }

  static func read16(_ data: Data, _ offset: Int) -> UInt16 {
    UInt16(data[data.startIndex + offset]) | (UInt16(data[data.startIndex + offset + 1]) << 8)
  }

  static func read32(_ data: Data, _ offset: Int) -> UInt32 {
    UInt32(read16(data, offset)) | (UInt32(read16(data, offset + 2)) << 16)
  }

  private static func append16(_ value: UInt16, to data: inout Data) {
    data.append(UInt8(truncatingIfNeeded: value))
    data.append(UInt8(truncatingIfNeeded: value >> 8))
  }

  private static func append32(_ value: UInt32, to data: inout Data) {
    append16(UInt16(truncatingIfNeeded: value), to: &data)
    append16(UInt16(truncatingIfNeeded: value >> 16), to: &data)
  }
}

/// Persists across a native session close, so a completed Sony RAM-object read
/// cannot be repeated as if it still referred to the previous photograph.
final class PtpTetherStagingStore {
  private enum Record {
    case file(PtpTetherStagedFile, handle: UInt32)
    case failed(PtpTetherFailure)
  }
  private var records: [String: [String: Record]] = [:]

  func lookup(
    sessionID: String, transferID: String, handle: UInt32? = nil,
    name: String? = nil, expectedSize: Int? = nil
  ) throws -> PtpTetherStagedFile? {
    guard let record = records[sessionID]?[transferID] else { return nil }
    switch record {
    case .failed(let failure): throw failure
    case .file(let file, let savedHandle):
      guard (handle == nil || savedHandle == handle),
            (name == nil || file.name == name),
            (expectedSize == nil || file.size == expectedSize) else {
        throw PtpTetherFailure(code: "PTP_TRANSFER_ID_REUSED", message: "A photo transfer identity cannot be reused for a different camera object.")
      }
      guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
            attributes[.type] as? FileAttributeType == .typeRegular,
            (attributes[.size] as? NSNumber)?.intValue == file.size else {
        throw PtpTetherFailure(code: "PTP_STAGED_FILE_MISSING", message: "This photograph was already received, but its saved transfer file is missing. It will not be replaced with a different camera photograph.")
      }
      return file
    }
  }

  func save(_ file: PtpTetherStagedFile, sessionID: String, transferID: String, handle: UInt32) {
    records[sessionID, default: [:]][transferID] = .file(file, handle: handle)
  }

  func markConsumedFailure(sessionID: String, transferID: String) {
    records[sessionID, default: [:]][transferID] = .failed(PtpTetherFailure(
      code: "PTP_STAGING_FAILED",
      message: "The camera sent this photograph, but the phone could not save it. Free phone storage and recover the original from the camera card; the next photograph will not be substituted for it."
    ))
  }

  func acknowledge(sessionID: String, transferIDs: [String]) {
    for id in transferIDs { records[sessionID]?[id] = nil }
    if records[sessionID]?.isEmpty == true { records[sessionID] = nil }
    // Dart deletes only its staging copy after saving a durable queue copy.
    // This acknowledgement never deletes a camera object or arbitrary path.
  }
}

/// ImageCaptureCore reports USB transport labels, not a universal camera
/// shooting-mode property. Only reject labels that explicitly identify a
/// storage/streaming connection. Plain USB, PTP, MTP or File Transfer labels
/// are NOT sufficient to decide whether the physical shutter works.
enum WiredCameraLiveTransportPolicy {
  static func isKnownImportOnly(_ transport: String?) -> Bool {
    guard let transport else { return false }
    let label = transport.lowercased().filter { $0.isLetter || $0.isNumber }
    return label.contains("massstorage") || label.contains("pcstorage") ||
      label.contains("cardreader") || label.contains("usbstreaming") ||
      label.contains("exfat")
  }
}

/// Live USB receives camera photos, it never operates the shutter, deletes
/// originals, starts video capture, or locks the camera's physical UI.
/// Defense in depth: the shared Dart driver applies this same restriction.
enum PtpShootingSafety {
  static let blocked: Set<UInt16> = [
    0x100B, // PTP DeleteObject
    0x100E, // PTP InitiateCapture
    0x100F, // PTP FormatStore
    0x1010, // PTP ResetDevice
    0x100C, 0x100D, 0x1011, 0x1012, 0x1013,
    0x1017, 0x1018, 0x1019, 0x101A, 0x101C,
    0x910F, // Canon EOS RemoteRelease
    0x911B, // Canon EOS UILock
    0x9128, // Canon EOS RemoteReleaseOn
    0x9129, // Canon EOS RemoteReleaseOff
    0x9151, // Canon EOS InitiateViewfinder
    0x9207, // Sony remote shutter / camera buttons
    0x1016, 0x9110, 0x9205, 0x9206, // Camera property writes
  ]

  private static let readOperations: Set<UInt16> = [
    0x1001, 0x1004, 0x1005, 0x1007, 0x1008, 0x1009, 0x100A,
    0x1014, 0x1015, 0x101B
  ]

  static func isAllowed(
    _ opcode: UInt16, vendorID: Int = 0,
    parameters: [UInt32] = [], outgoing: Data? = nil
  ) -> Bool {
    let olympus = vendorID == 0x07B4 || vendorID == 0x33A2
    if olympus && opcode == 0x1016 {
      guard parameters == [0xD052], let outgoing = outgoing else { return false }
      // Only begin/restore the OM connection; no shooting-setting writes.
      return outgoing == Data([1, 0]) || outgoing == Data([2, 0])
    }
    if blocked.contains(opcode) { return false }
    if let outgoing = outgoing, !outgoing.isEmpty { return false }
    if readOperations.contains(opcode) { return true }
    // Only the receiver's exact vendor negotiation/read operations are allowed.
    // Unknown identities never inherit another brand's command meanings.
    switch vendorID {
    case 0x04A9:
      switch opcode {
      case 0x9114, 0x9115: return parameters == [0] || parameters == [1]
      case 0x9116: return parameters.isEmpty
      case 0x9127: return parameters == [0xD11C]
      case 0x9117: return parameters.count == 1 && parameters[0] > 0 &&
        parameters[0] < 0xFFFFFFFF
      case 0x9107: return true // Native download validates partial-read ranges.
      default: return false
      }
    case 0x04B0:
      return (opcode == 0x90C2 && parameters == [0]) ||
        ((opcode == 0x90C7 || opcode == 0x941C) && parameters.isEmpty)
    case 0x054C:
      return (opcode == 0x9201 &&
        (parameters == [1, 0, 0] || parameters == [2, 0, 0] ||
         parameters == [3, 0, 0])) ||
        (opcode == 0x9202 && parameters == [0x12C, 1]) ||
        (opcode == 0x9209 && parameters.isEmpty)
    case 0x04DA:
      return opcode == 0x940A && parameters == [0x08000090]
    default: return false
    }
  }
}

/// All protocol state is confined to the main queue. ImageCaptureCore commands
/// are asynchronous; disk writes run on a separate serial utility queue.
final class PtpTetherTransport {
  private final class Command {
    let opcode: UInt16
    let parameters: [UInt32]
    let outgoing: Data?
    let maximumData: Int
    let isDownload: Bool
    let completion: (Result<PtpTetherReply, PtpTetherFailure>) -> Void
    var timeout: DispatchWorkItem?
    var completed = false

    init(
      opcode: UInt16, parameters: [UInt32], outgoing: Data?, maximumData: Int,
      isDownload: Bool, completion: @escaping (Result<PtpTetherReply, PtpTetherFailure>) -> Void
    ) {
      self.opcode = opcode
      self.parameters = parameters
      self.outgoing = outgoing
      self.maximumData = maximumData
      self.isDownload = isDownload
      self.completion = completion
    }
  }

  private final class Download {
    let handle: UInt32
    let name: String
    let expectedSize: Int
    let transferID: String
    let directory: URL
    let partialURL: URL
    let finalURL: URL
    let completion: (Result<PtpTetherStagedFile, PtpTetherFailure>) -> Void
    var partialOpcode: UInt16?
    var file: FileHandle?
    var received = 0
    var ioBusy = false
    var cancelled = false
    var completed = false
    var sourceConsumed = false

    init(
      handle: UInt32, name: String, expectedSize: Int, transferID: String,
      partialOpcode: UInt16?, completion: @escaping (Result<PtpTetherStagedFile, PtpTetherFailure>) -> Void
    ) {
      self.handle = handle
      self.name = name
      self.expectedSize = expectedSize
      self.transferID = transferID
      self.partialOpcode = partialOpcode
      self.completion = completion
      directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("airpix_ptp_tether", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      partialURL = directory.appendingPathComponent("incoming.part")
      finalURL = directory.appendingPathComponent(name)
    }
  }

  let sessionID: String
  private let camera: ICCameraDevice
  private let staging: PtpTetherStagingStore
  private let onFailure: (PtpTetherFailure) -> Void
  private let fileIO = DispatchQueue(label: "com.nikofly.ptp-file", qos: .utility)
  private var commands: [Command] = []
  private var active: Command?
  private var download: Download?
  private var acknowledgedTransfers: Set<String> = []
  private(set) var closed = false

  init(
    sessionID: String, camera: ICCameraDevice, staging: PtpTetherStagingStore,
    onFailure: @escaping (PtpTetherFailure) -> Void
  ) {
    self.sessionID = sessionID
    self.camera = camera
    self.staging = staging
    self.onFailure = onFailure
  }

  func send(
    opcode: UInt16, parameters: [UInt32], outgoing: Data?,
    completion: @escaping (Result<PtpTetherReply, PtpTetherFailure>) -> Void
  ) {
    guard !closed else { completion(.failure(Self.ended)); return }
    guard download == nil else { completion(.failure(Self.busy)); return }
    guard PtpShootingSafety.isAllowed(opcode, vendorID: Int(camera.usbVendorID),
      parameters: parameters, outgoing: outgoing) else {
      completion(.failure(PtpTetherFailure(
        code: "PTP_SHOOTING_COMMAND_BLOCKED",
        message: "This command is not approved for this camera. Receiving stops without switching USB modes."
      )))
      return
    }
    if opcode == 0x1009 || opcode == 0x101B || opcode == 0x9107 {
      completion(.failure(PtpTetherFailure(
        code: "PTP_STREAM_REQUIRED", message: "Camera photos must use the native file transfer method."
      )))
      return
    }
    guard opcode != 0x1002, opcode != 0x1003,
          parameters.count <= 5, (outgoing?.count ?? 0) <= PtpTetherCodec.outgoingLimit else {
      completion(.failure(Self.invalidArgument)); return
    }
    enqueue(opcode: opcode, parameters: parameters, outgoing: outgoing,
            maximumData: PtpTetherCodec.metadataLimit, isDownload: false, completion: completion)
  }

  func downloadObject(
    handle: UInt32, name: String, expectedSize: Int, transferID: String,
    partialOpcode: UInt16?, completion: @escaping (Result<PtpTetherStagedFile, PtpTetherFailure>) -> Void
  ) {
    guard !closed else { completion(.failure(Self.ended)); return }
    guard !acknowledgedTransfers.contains(transferID) else {
      completion(.failure(PtpTetherFailure(code: "PTP_ALREADY_ACKNOWLEDGED", message: "This photograph has already been saved to the upload queue.")))
      return
    }
    guard PtpShootingSafety.isAllowed(partialOpcode ?? 0x1009,
      vendorID: Int(camera.usbVendorID)) else {
      completion(.failure(PtpTetherFailure(code: "PTP_SHOOTING_COMMAND_BLOCKED",
        message: "This download opcode belongs to a different camera protocol.")))
      return
    }
    guard handle > 0, expectedSize > 0, expectedSize <= PtpTetherCodec.fileLimit,
          !transferID.isEmpty, transferID.utf8.count <= 2048,
          partialOpcode == nil || partialOpcode == 0x101B || partialOpcode == 0x9107,
          !(camera.usbVendorID == 0x054C && handle == 0xFFFFC001 && partialOpcode != nil) else {
      completion(.failure(Self.invalidArgument)); return
    }
    do {
      if let cached = try staging.lookup(sessionID: sessionID, transferID: transferID,
                                        handle: handle, name: Self.safeName(name), expectedSize: expectedSize) {
        completion(.success(cached)); return
      }
    } catch let failure as PtpTetherFailure {
      completion(.failure(failure)); return
    } catch {
      completion(.failure(Self.storageFailure(error))); return
    }
    guard download == nil, active == nil, commands.isEmpty else { completion(.failure(Self.busy)); return }
    if partialOpcode == nil && expectedSize > PtpTetherCodec.wholeObjectLimit {
      completion(.failure(Self.requiresPartialRead)); return
    }
    let job = Download(handle: handle, name: Self.safeName(name), expectedSize: expectedSize,
                       transferID: transferID, partialOpcode: partialOpcode, completion: completion)
    download = job
    job.ioBusy = true
    fileIO.async {
      let prepared: Result<FileHandle, PtpTetherFailure>
      do {
        try FileManager.default.createDirectory(at: job.directory, withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: job.partialURL.path, contents: nil) else {
          throw PtpTetherFailure(code: "PTP_STAGING_FAILED", message: "The phone could not create a photo transfer file. Check free storage.")
        }
        prepared = .success(try FileHandle(forWritingTo: job.partialURL))
      } catch {
        prepared = .failure(Self.storageFailure(error))
      }
      DispatchQueue.main.async {
        job.ioBusy = false
        switch prepared {
        case .success(let file):
          job.file = file
          if job.cancelled || self.closed { self.finishDownload(job, .failure(Self.ended)) }
          else { self.receiveNextChunk(job) }
        case .failure(let failure): self.finishDownload(job, .failure(failure))
        }
      }
    }
  }

  func acknowledge(_ transferIDs: [String]) {
    acknowledgedTransfers.formUnion(transferIDs)
    staging.acknowledge(sessionID: sessionID, transferIDs: transferIDs)
  }

  func close() {
    guard !closed else { return }
    closed = true
    let queued = commands
    commands.removeAll()
    for command in queued { complete(command, result: .failure(Self.ended), pump: false) }
    if let job = download { job.cancelled = true }
    if let active, !active.isDownload {
      complete(active, result: .failure(Self.ended), pump: false)
    }
    // An already completed camera read can race a Stop/disconnect callback.
    // Allow its last chunk to finish disk persistence under the original token.
    // No next chunk or new camera command is issued after close.
    if let job = download, active == nil, !job.ioBusy {
      finishDownload(job, .failure(Self.ended))
    }
  }

  private func enqueue(
    opcode: UInt16, parameters: [UInt32], outgoing: Data?, maximumData: Int,
    isDownload: Bool, completion: @escaping (Result<PtpTetherReply, PtpTetherFailure>) -> Void
  ) {
    guard !closed else { completion(.failure(Self.ended)); return }
    commands.append(Command(opcode: opcode, parameters: parameters, outgoing: outgoing,
                            maximumData: maximumData, isDownload: isDownload, completion: completion))
    pump()
  }

  private func pump() {
    guard !closed, active == nil, !commands.isEmpty else { return }
    let command = commands.removeFirst()
    active = command
    let packet: Data
    do {
      packet = try PtpTetherCodec.command(opcode: command.opcode, parameters: command.parameters)
    } catch {
      failTransaction(command, Self.invalidArgument)
      return
    }
    let timeout = DispatchWorkItem { [weak self, weak command] in
      guard let self, let command, self.active === command, !command.completed else { return }
      self.failTransaction(command, PtpTetherFailure(
        code: "PTP_TETHER_TIMEOUT",
        message: "The camera stopped responding to its tether connection. Reconnect it; incomplete files have not been uploaded."
      ))
    }
    command.timeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + (command.isDownload ? 120 : 30), execute: timeout)
    camera.requestSendPTPCommand(packet, outData: command.outgoing) { response, data, error in
      DispatchQueue.main.async {
        guard self.active === command, !command.completed else { return }
        if let error {
          let nativeError = error as NSError
          self.failTransaction(command, PtpTetherFailure(
            code: "PTP_TRANSPORT_FAILED", message: error.localizedDescription,
            diagnostics: [
              "operation": String(format: "0x%04X", command.opcode),
              "errorDomain": nativeError.domain,
              "errorCode": String(nativeError.code),
              "responseBytes": String(response.count),
              "dataBytes": String(data.count),
            ]
          ))
          return
        }
        do {
          let reply = try PtpTetherCodec.decode(response: response, data: data,
                                               maximumData: command.maximumData)
          self.complete(command, result: .success(reply))
        } catch let failure as PtpTetherFailure {
          self.failTransaction(command, failure.forOperation(command.opcode))
        } catch {
          self.failTransaction(command, PtpTetherFailure(code: "PTP_INVALID_RESPONSE", message: error.localizedDescription))
        }
      }
    }
  }

  private func complete(
    _ command: Command, result: Result<PtpTetherReply, PtpTetherFailure>, pump shouldPump: Bool = true
  ) {
    guard !command.completed else { return }
    command.completed = true
    command.timeout?.cancel()
    command.timeout = nil
    if active === command { active = nil }
    command.completion(result)
    if shouldPump { pump() }
  }

  private func failTransaction(_ command: Command, _ failure: PtpTetherFailure) {
    let wasOpen = !closed
    // Retire this transport before completing the caller. No retry can run on
    // a bulk stream whose previous transaction timed out or had bad framing.
    closed = true
    complete(command, result: .failure(failure), pump: false)
    let queued = commands
    commands.removeAll()
    for queuedCommand in queued { complete(queuedCommand, result: .failure(failure), pump: false) }
    if let job = download {
      job.cancelled = true
      if !job.ioBusy { finishDownload(job, .failure(failure)) }
    }
    if wasOpen { onFailure(failure) }
  }

  private func receiveNextChunk(_ job: Download) {
    guard !job.completed else { return }
    guard !closed, !job.cancelled, download === job else {
      finishDownload(job, .failure(Self.ended)); return
    }
    let opcode = job.partialOpcode ?? 0x1009
    let requested = job.partialOpcode == nil
      ? job.expectedSize : min(PtpTetherCodec.partialChunkSize, job.expectedSize - job.received)
    let parameters: [UInt32] = job.partialOpcode == nil
      ? [job.handle] : [job.handle, UInt32(job.received), UInt32(requested)]
    enqueue(opcode: opcode, parameters: parameters, outgoing: nil,
            maximumData: requested, isDownload: true) { outcome in
      guard !job.completed else { return }
      switch outcome {
      case .failure(let failure): self.finishDownload(job, .failure(failure))
      case .success(let reply):
        if PtpTetherCodec.canFallbackToWholeObject(reply, partialOpcode: job.partialOpcode,
                                                   receivedBytes: job.received),
           !self.closed, !job.cancelled {
          guard job.expectedSize <= PtpTetherCodec.wholeObjectLimit else {
            self.finishDownload(job, .failure(Self.requiresPartialRead)); return
          }
          job.partialOpcode = nil
          self.receiveNextChunk(job)
          return
        }
        guard reply.responseCode == 0x2001 else {
          self.finishDownload(job, .failure(PtpTetherFailure(
            code: "PTP_OBJECT_NOT_READY",
            message: String(format: "The camera has not made this photo available (PTP 0x%04X). It remains pending.", reply.responseCode)
          )))
          return
        }
        if self.camera.usbVendorID == 0x054C && job.handle == 0xFFFFC001 && opcode == 0x1009 {
          // Reading Sony's shared RAM handle consumes one queue item. If local
          // persistence fails, repeating this read would substitute another shot.
          job.sourceConsumed = true
        }
        do {
          try PtpTetherCodec.validateChunk(reply, opcode: opcode, requested: requested)
        } catch let failure as PtpTetherFailure {
          self.finishDownload(job, .failure(failure)); return
        } catch {
          self.finishDownload(job, .failure(Self.storageFailure(error))); return
        }
        if (self.closed || job.cancelled), job.received + reply.data.count != job.expectedSize {
          self.finishDownload(job, .failure(Self.ended)); return
        }
        self.writeChunk(reply.data, job: job)
      }
    }
  }

  private func writeChunk(_ data: Data, job: Download) {
    guard let file = job.file else { finishDownload(job, .failure(Self.ended)); return }
    job.ioBusy = true
    fileIO.async {
      let outcome: Result<Void, PtpTetherFailure>
      do {
        try Self.appendFileData(data, to: file)
        outcome = .success(())
      } catch { outcome = .failure(Self.storageFailure(error)) }
      DispatchQueue.main.async {
        job.ioBusy = false
        if case .failure(let failure) = outcome { self.finishDownload(job, .failure(failure)); return }
        job.received += data.count
        if job.received == job.expectedSize { self.finalizeDownload(job) }
        else if job.cancelled || self.closed { self.finishDownload(job, .failure(Self.ended)) }
        else { self.receiveNextChunk(job) }
      }
    }
  }

  private func finalizeDownload(_ job: Download) {
    guard !job.completed, let file = job.file else { return }
    job.ioBusy = true
    fileIO.async {
      let outcome: Result<PtpTetherStagedFile, PtpTetherFailure>
      do {
        try file.synchronize()
        try file.close()
        let attributes = try FileManager.default.attributesOfItem(atPath: job.partialURL.path)
        guard (attributes[.size] as? NSNumber)?.intValue == job.expectedSize else {
          throw PtpTetherFailure(code: "PTP_INCOMPLETE_FILE", message: "The saved photo size does not match the complete camera file.")
        }
        try FileManager.default.moveItem(at: job.partialURL, to: job.finalURL)
        outcome = .success(PtpTetherStagedFile(path: job.finalURL.path, name: job.name, size: job.expectedSize))
      } catch {
        outcome = .failure(Self.storageFailure(error))
      }
      DispatchQueue.main.async {
        job.ioBusy = false
        self.finishDownload(job, outcome)
      }
    }
  }

  private func finishDownload(_ job: Download, _ outcome: Result<PtpTetherStagedFile, PtpTetherFailure>) {
    guard !job.completed else { return }
    job.completed = true
    if download === job { download = nil }
    switch outcome {
    case .success(let file):
      staging.save(file, sessionID: sessionID, transferID: job.transferID, handle: job.handle)
    case .failure:
      if job.sourceConsumed { staging.markConsumedFailure(sessionID: sessionID, transferID: job.transferID) }
      let file = job.file
      fileIO.async {
        try? file?.close()
        try? FileManager.default.removeItem(at: job.directory)
      }
    }
    job.file = nil
    job.completion(outcome)
  }

  private static func appendFileData(_ data: Data, to file: FileHandle) throws {
    // FileHandle's throwing write(contentsOf:) starts at iOS 13.4; the app also
    // supports 13.0. POSIX writes report disk-full errors on every supported
    // version without the old writeData API's Objective-C exceptions.
    let descriptor = file.fileDescriptor
    try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) throws -> Void in
      guard let base = bytes.baseAddress else { return }
      var offset = 0
      while offset < bytes.count {
        let count = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
        if count < 0 {
          let errorCode = errno
          if errorCode == EINTR { continue }
          throw NSError(domain: NSPOSIXErrorDomain, code: Int(errorCode), userInfo: nil)
        }
        guard count > 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(EIO), userInfo: nil) }
        offset += count
      }
    }
  }

  static func safeName(_ value: String) -> String {
    let invalid = CharacterSet(charactersIn: "/\\:\u{0000}").union(.controlCharacters)
    var result = value.components(separatedBy: invalid).joined(separator: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    while result.utf8.count > 180 { result.removeLast() }
    return result.isEmpty || result == "." || result == ".." ? "camera-image.jpg" : result
  }

  private static var invalidArgument: PtpTetherFailure {
    PtpTetherFailure(code: "PTP_INVALID_ARGUMENT", message: "Invalid camera tether operation arguments.")
  }
  private static var ended: PtpTetherFailure {
    PtpTetherFailure(code: "CAMERA_SESSION_ENDED", message: "This camera tether session has ended.")
  }
  private static var busy: PtpTetherFailure {
    PtpTetherFailure(code: "PTP_TETHER_BUSY", message: "A camera transaction is already receiving a photograph. Retry when it finishes.")
  }
  private static var requiresPartialRead: PtpTetherFailure {
    PtpTetherFailure(code: "PTP_FILE_TOO_LARGE", message: "This photo requires a camera partial-read operation that is unavailable in the selected mode. Use smaller JPEG files or import this original separately.")
  }
  private static func storageFailure(_ error: Error) -> PtpTetherFailure {
    (error as? PtpTetherFailure) ?? PtpTetherFailure(code: "PTP_STAGING_FAILED", message: "Could not save the received photo on the phone: \(error.localizedDescription)")
  }
}
