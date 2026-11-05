import Flutter
import ImageCaptureCore
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testAuthorizedCameraContentsAccessHasNoError() throws {
    guard #available(iOS 14.0, *) else {
      throw XCTSkip("ImageCaptureCore authorization requests require iOS 14 or later.")
    }
    let state = WiredCameraAuthorizationState(.authorized)
    XCTAssertEqual(state, .authorized)
    XCTAssertTrue(state.allowsContentsAccess)
    XCTAssertNil(state.errorCode)
  }

  func testDeniedCameraContentsAccessKeepsExplicitDenial() throws {
    guard #available(iOS 14.0, *) else {
      throw XCTSkip("ImageCaptureCore authorization requests require iOS 14 or later.")
    }
    let state = WiredCameraAuthorizationState(.denied)
    XCTAssertEqual(state, .denied)
    XCTAssertFalse(state.allowsContentsAccess)
    XCTAssertEqual(state.errorCode, "CAMERA_ACCESS_DENIED")
  }

  func testRestrictedCameraContentsAccessIsDistinctFromUserDenial() throws {
    guard #available(iOS 14.0, *) else {
      throw XCTSkip("ImageCaptureCore authorization requests require iOS 14 or later.")
    }
    let state = WiredCameraAuthorizationState(.restricted)
    XCTAssertEqual(state, .restricted)
    XCTAssertFalse(state.allowsContentsAccess)
    XCTAssertEqual(state.errorCode, "CAMERA_ACCESS_RESTRICTED")
  }

  func testUndeterminedCameraAuthorizationStaysPendingWithoutGrantingAccess() throws {
    guard #available(iOS 14.0, *) else {
      throw XCTSkip("ImageCaptureCore authorization requests require iOS 14 or later.")
    }
    let state = WiredCameraAuthorizationState(.notDetermined)
    XCTAssertEqual(state, .pending)
    XCTAssertEqual(state.rawValue, "not-determined")
    XCTAssertFalse(state.allowsContentsAccess)
    XCTAssertEqual(state.errorCode, "CAMERA_AUTHORIZATION_PENDING")
  }

  func testUnknownCameraAuthorizationFailsClosedWithoutReportingDenial() throws {
    guard #available(iOS 14.0, *) else {
      throw XCTSkip("ImageCaptureCore authorization requests require iOS 14 or later.")
    }
    let status = ICAuthorizationStatus(rawValue: "AirPixUnknownAuthorizationStatus")
    let state = WiredCameraAuthorizationState(status)
    XCTAssertEqual(state, .unavailable)
    XCTAssertFalse(state.allowsContentsAccess)
    XCTAssertEqual(state.errorCode, "CAMERA_AUTHORIZATION_UNAVAILABLE")
  }

  private func photo(
    _ handle: Int,
    name: String? = nil,
    created: Int64? = 1_700_000_000_000
  ) -> WiredCameraPhotoIdentity {
    WiredCameraPhotoIdentity(
      handle: String(handle),
      name: name ?? "IMG_\(handle).JPG",
      createdMilliseconds: created
    )
  }

  func testWholeCardBaselineIsSkippedAndNewShotIsPending() {
    let index = WiredCameraPhotoIndex(cameraID: "camera-a")
    let oldPhotos = (1...1200).map { photo($0) }
    index.establishBaseline(oldPhotos)
    for oldPhoto in oldPhotos {
      XCTAssertFalse(index.observe(oldPhoto).added)
    }
    XCTAssertTrue(index.pendingIDs.isEmpty)

    let shot = index.observe(photo(1201))
    XCTAssertTrue(shot.added)
    XCTAssertEqual(index.pendingIDs, [shot.id])
  }

  func testRepeatedEventsStayPendingUntilExplicitAcknowledgement() {
    let index = WiredCameraPhotoIndex(cameraID: "camera-a")
    index.establishBaseline([])
    let first = index.observe(photo(1))
    for _ in 0..<5 {
      XCTAssertFalse(index.observe(photo(1)).added)
    }
    XCTAssertEqual(index.pendingIDs, [first.id])
    index.acknowledge([first.id])
    XCTAssertTrue(index.pendingIDs.isEmpty)
    XCTAssertFalse(index.observe(photo(1)).added)
    XCTAssertTrue(index.pendingIDs.isEmpty)
  }

  func testMetadataArrivingAfterObjectEventKeepsSameDeliveryID() {
    let index = WiredCameraPhotoIndex(cameraID: "camera-a")
    index.establishBaseline([])
    let announced = index.observe(photo(1, created: nil))
    let finished = index.observe(photo(1))
    XCTAssertEqual(announced.id, finished.id)
    XCTAssertFalse(finished.added)
    XCTAssertEqual(index.pendingIDs, [announced.id])
  }

  func testBurstBacklogIsNotTruncatedTo500Images() {
    let index = WiredCameraPhotoIndex(cameraID: "camera-a")
    index.establishBaseline([])
    let shots = (1...750).map { index.observe(photo($0)) }
    XCTAssertEqual(index.pendingIDs.count, 750)
    index.acknowledge(Set(shots.prefix(500).map { $0.id }))
    XCTAssertEqual(index.pendingIDs, shots.suffix(250).map { $0.id })
  }

  func testRemovedUnacknowledgedPhotoIsRetainedAndReusedHandleIsNew() {
    let index = WiredCameraPhotoIndex(cameraID: "camera-a")
    index.establishBaseline([])
    let old = index.observe(photo(1))
    index.markRemoved(handle: "1")
    let replacement = index.observe(photo(1))
    XCTAssertNotEqual(old.id, replacement.id)
    XCTAssertEqual(index.pendingIDs, [old.id, replacement.id])
    index.acknowledge([replacement.id])
    XCTAssertEqual(index.pendingIDs, [old.id])
  }

  func testRenameDoesNotTurnOldCardPhotoIntoNewShot() {
    let index = WiredCameraPhotoIndex(cameraID: "camera-a")
    index.establishBaseline([photo(1)])
    let renamed = index.observe(photo(1, name: "RENAMED.JPG"), preserveIdentity: true)
    XCTAssertFalse(renamed.added)
    XCTAssertTrue(index.pendingIDs.isEmpty)
  }

  func testDifferentCreationTimeDoesNotReuseDeliveredObjectID() {
    let index = WiredCameraPhotoIndex(cameraID: "camera-a")
    index.establishBaseline([photo(1)])
    let replacement = index.observe(photo(1, created: 1_800_000_000_000))
    XCTAssertTrue(replacement.added)
    XCTAssertEqual(index.pendingIDs, [replacement.id])
  }

  private func ptpResponse(
    code: UInt16 = 0x2001,
    transaction: UInt32 = 0x7351,
    parameters: [UInt32] = []
  ) -> Data {
    var bytes: [UInt8] = []
    func word(_ value: UInt32) {
      bytes += (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
    }
    word(UInt32(12 + parameters.count * 4))
    bytes += [3, 0, UInt8(truncatingIfNeeded: code), UInt8(truncatingIfNeeded: code >> 8)]
    word(transaction)
    parameters.forEach { word($0) }
    return Data(bytes)
  }


  func testImageCaptureFallbackOnlyCoversSafeObjectReadFailures() {
    let eligible = [
      "PTP_OBJECT_NOT_READY",
      "PTP_INCOMPLETE_FILE",
      "PTP_FILE_TOO_LARGE",
    ]
    for code in eligible {
      XCTAssertTrue(
        PtpImageCaptureFallbackPolicy.shouldTry(
          code: code,
          handle: 42,
          expectedSize: 4096
        )
      )
    }

    for code in [
      "PTP_TRANSPORT_FAILED",
      "PTP_TETHER_TIMEOUT",
      "PTP_STAGING_FAILED",
      "CAMERA_SESSION_ENDED",
      "PTP_TETHER_BUSY",
    ] {
      XCTAssertFalse(
        PtpImageCaptureFallbackPolicy.shouldTry(
          code: code,
          handle: 42,
          expectedSize: 4096
        )
      )
    }

    XCTAssertFalse(
      PtpImageCaptureFallbackPolicy.shouldTry(
        code: "PTP_INCOMPLETE_FILE",
        handle: 0,
        expectedSize: 4096
      )
    )
    XCTAssertFalse(
      PtpImageCaptureFallbackPolicy.shouldTry(
        code: "PTP_INCOMPLETE_FILE",
        handle: 42,
        expectedSize: 0
      )
    )
  }

  func testPtpCommandUsesLittleEndianAndLetsImageCaptureCoreAssignTransaction() throws {
    let packet = try PtpTetherCodec.command(opcode: 0x9107, parameters: [0xFFFFC001, 0x100000, 1024])
    XCTAssertEqual(Array(packet), [
      24, 0, 0, 0, 1, 0, 7, 0x91, 0, 0, 0, 0,
      1, 0xC0, 0xFF, 0xFF, 0, 0, 0x10, 0, 0, 4, 0, 0,
    ])
    XCTAssertThrowsError(try PtpTetherCodec.command(opcode: 0x1007, parameters: Array(repeating: 0, count: 6)))
  }

  func testPtpAcceptsSystemAssignedTransactionAndPreservesResponseParameters() throws {
    // Apple assigns this ID, independently of the zero in the command packet.
    let reply = try PtpTetherCodec.decode(
      response: ptpResponse(transaction: 791, parameters: [4096, UInt32.max]),
      data: Data([9, 8, 7]), maximumData: 4096
    )
    XCTAssertEqual(reply.responseCode, 0x2001)
    XCTAssertEqual(reply.parameters, [4096, UInt32.max])
    XCTAssertEqual(reply.data, Data([9, 8, 7]))
  }

  func testPtpPayloadThatLooksLikeUsbHeaderIsNeverStripped() throws {
    // ImageCaptureCore already removes the USB data header. These bytes belong
    // to the dataset or photograph, even if they resemble another container.
    let payload = Data([16, 0, 0, 0, 2, 0, 9, 0x10, 0x51, 0x73, 0, 0, 8, 7, 6, 5])
    let reply = try PtpTetherCodec.decode(response: ptpResponse(), data: payload, maximumData: 16)
    XCTAssertEqual(reply.data, payload)
  }

  func testPtpMissingResponseAndMalformedEnvelopeCannotBecomeSuccess() {
    var wrongLength = ptpResponse()
    wrongLength[0] = 16
    var wrongType = ptpResponse()
    wrongType[4] = 2
    var fractionalParameter = ptpResponse()
    fractionalParameter.append(0)
    fractionalParameter[0] = 13
    let tooManyParameters = ptpResponse(parameters: Array(repeating: 0, count: 6))
    for response in [Data(), Data([0x01, 0x20]), wrongLength, wrongType, fractionalParameter, tooManyParameters] {
      XCTAssertThrowsError(try PtpTetherCodec.decode(response: response, data: Data(), maximumData: 16)) { error in
        XCTAssertEqual((error as? PtpTetherFailure)?.code, "PTP_INVALID_RESPONSE")
      }
    }
  }

  func testPtpBusyIsReturnedAsCameraResponseAndOversizedDataIsRejected() throws {
    let reply = try PtpTetherCodec.decode(response: ptpResponse(code: 0x2019), data: Data(), maximumData: 8)
    XCTAssertEqual(reply.responseCode, 0x2019)
    XCTAssertThrowsError(try PtpTetherCodec.decode(
      response: ptpResponse(), data: Data(repeating: 1, count: 9), maximumData: 8
    )) { error in
      XCTAssertEqual((error as? PtpTetherFailure)?.code, "PTP_DATA_LIMIT")
    }
  }

  func testPartialPhotoAcceptsActualBytesWithinRequestedMaximum() throws {
    let complete = PtpTetherReply(responseCode: 0x2001, parameters: [4], data: Data([1, 2, 3, 4]))
    XCTAssertNoThrow(try PtpTetherCodec.validateChunk(complete, opcode: 0x101B, requested: 4))
    XCTAssertNoThrow(try PtpTetherCodec.validateChunk(complete, opcode: 0x101B, requested: 5))
    XCTAssertNoThrow(try PtpTetherCodec.validateChunk(complete, opcode: 0x9107, requested: 5))
    let wrongCount = PtpTetherReply(responseCode: 0x2001, parameters: [3], data: complete.data)
    XCTAssertThrowsError(try PtpTetherCodec.validateChunk(wrongCount, opcode: 0x101B, requested: 4))
    let claimedMaximum = PtpTetherReply(responseCode: 0x2001, parameters: [5], data: complete.data)
    XCTAssertThrowsError(try PtpTetherCodec.validateChunk(claimedMaximum, opcode: 0x101B, requested: 5))
    // Canon's 0x9107 response parameters are not defined as a byte count.
    XCTAssertNoThrow(try PtpTetherCodec.validateChunk(wrongCount, opcode: 0x9107, requested: 4))
  }

  func testPartialPhotoRejectsZeroProgressAndOversizedPayloads() {
    let empty = PtpTetherReply(responseCode: 0x2001, parameters: [0], data: Data())
    let oversized = PtpTetherReply(responseCode: 0x2001, parameters: [5], data: Data(repeating: 1, count: 5))
    for opcode in [UInt16(0x101B), 0x9107] {
      XCTAssertThrowsError(try PtpTetherCodec.validateChunk(empty, opcode: opcode, requested: 4))
      XCTAssertThrowsError(try PtpTetherCodec.validateChunk(oversized, opcode: opcode, requested: 4))
    }
  }

  func testWholePhotoStillRequiresItsExactExpectedSize() {
    let photo = PtpTetherReply(responseCode: 0x2001, parameters: [], data: Data([1, 2, 3, 4]))
    XCTAssertNoThrow(try PtpTetherCodec.validateChunk(photo, opcode: 0x1009, requested: 4))
    XCTAssertThrowsError(try PtpTetherCodec.validateChunk(photo, opcode: 0x1009, requested: 5))
    XCTAssertThrowsError(try PtpTetherCodec.validateChunk(photo, opcode: 0x1009, requested: 3))
  }

  func testLostTetherListenerExpiresOnceAfterItsGracePeriod() {
    var scheduled: [DispatchWorkItem] = []
    let lease = PtpTetherListenerLease(schedule: { scheduled.append($0) })
    var releases = 0
    lease.detach { releases += 1 }
    XCTAssertTrue(lease.isDetached)
    XCTAssertEqual(releases, 0)
    scheduled[0].perform()
    scheduled[0].perform()
    XCTAssertEqual(releases, 1)
  }

  func testReattachedTetherListenerInvalidatesOldReleaseTimer() {
    var scheduled: [DispatchWorkItem] = []
    let lease = PtpTetherListenerLease(schedule: { scheduled.append($0) })
    var releases = 0
    lease.detach { releases += 1 }
    lease.attach()
    scheduled[0].perform()
    XCTAssertFalse(lease.isDetached)
    XCTAssertEqual(releases, 0)
    lease.detach { releases += 1 }
    scheduled[0].perform()
    XCTAssertEqual(releases, 0)
    scheduled[1].perform()
    XCTAssertEqual(releases, 1)
  }

  func testExplicitTetherCloseInvalidatesPendingListenerRelease() {
    var scheduled: [DispatchWorkItem] = []
    let lease = PtpTetherListenerLease(schedule: { scheduled.append($0) })
    var releases = 0
    lease.detach { releases += 1 }
    lease.invalidate()
    scheduled[0].perform()
    XCTAssertEqual(releases, 0)
    XCTAssertFalse(lease.isDetached)
  }

  private final class PtpReleaseProbe {
    var connected = true
    var opening = false
    var open = true
    var scheduled: [DispatchWorkItem] = []
    var nativeCompletions: [(Error?) -> Void] = []
    var results: [String] = []
    var releasedIDs: [String] = []
    var failures: [String] = []

    func makeRelease(sessionID: String = "session") -> PtpTetherSessionRelease {
      PtpTetherSessionRelease(
        sessionID: sessionID,
        state: { .init(connected: self.connected, opening: self.opening, open: self.open) },
        requestClose: { self.nativeCompletions.append($0) },
        schedule: { self.scheduled.append($0) },
        onReleased: { self.releasedIDs.append($0.sessionID) },
        onFailure: { _, failure in self.failures.append(failure.code) }
      )
    }

    func observe(_ release: PtpTetherSessionRelease) {
      release.wait { outcome in
        switch outcome {
        case .success: self.results.append("released")
        case .failure(let error): self.results.append(error.code)
        }
      }
    }
  }

  func testTetherCloseWaitsForActualNativeRelease() {
    let probe = PtpReleaseProbe()
    let release = probe.makeRelease()
    probe.observe(release)
    release.begin()
    XCTAssertEqual(probe.nativeCompletions.count, 1)
    XCTAssertTrue(probe.results.isEmpty)
    XCTAssertFalse(release.isReleased)

    probe.open = false
    probe.nativeCompletions[0](nil)
    XCTAssertTrue(release.isReleased)
    XCTAssertEqual(probe.results, ["released"])
    XCTAssertEqual(probe.releasedIDs, ["session"])
    probe.scheduled[0].perform()
    XCTAssertEqual(probe.results, ["released"])
  }

  func testTetherCloseErrorRetainsOwnerUntilActualClosure() {
    let probe = PtpReleaseProbe()
    let release = probe.makeRelease()
    probe.observe(release)
    release.begin()
    probe.nativeCompletions[0](NSError(domain: "CameraTest", code: 7))
    XCTAssertFalse(release.isReleased)
    XCTAssertEqual(release.failure?.code, "PTP_CLOSE_FAILED")
    XCTAssertEqual(probe.results, ["PTP_CLOSE_FAILED"])
    XCTAssertTrue(probe.releasedIDs.isEmpty)

    // A second Stop receives the same failure instead of issuing a second
    // close that could race with the next session.
    probe.observe(release)
    release.cameraStateChanged()
    XCTAssertEqual(probe.nativeCompletions.count, 1)
    XCTAssertEqual(probe.results, ["PTP_CLOSE_FAILED", "PTP_CLOSE_FAILED"])
    probe.open = false
    release.cameraStateChanged()
    XCTAssertTrue(release.isReleased)
    XCTAssertNil(release.failure)
    XCTAssertEqual(probe.releasedIDs, ["session"])
    XCTAssertEqual(probe.results.count, 2)
    probe.observe(release)
    XCTAssertEqual(probe.results.last, "released")
  }

  func testSuccessfulCloseCallbackCannotReleaseCameraStillOpen() {
    let probe = PtpReleaseProbe()
    let release = probe.makeRelease()
    probe.observe(release)
    release.begin()
    probe.nativeCompletions[0](nil)
    XCTAssertEqual(probe.results, ["PTP_CLOSE_FAILED"])
    XCTAssertFalse(release.isReleased)
    XCTAssertTrue(probe.releasedIDs.isEmpty)
  }

  func testCloseErrorDoesNotOverrideConfirmedClosedState() {
    let probe = PtpReleaseProbe()
    let release = probe.makeRelease()
    probe.observe(release)
    release.begin()
    probe.open = false
    probe.nativeCompletions[0](NSError(domain: "CameraTest", code: 7))
    XCTAssertEqual(probe.results, ["released"])
    XCTAssertTrue(release.isReleased)
    XCTAssertTrue(probe.failures.isEmpty)
  }

  func testTetherCloseTimeoutKeepsOwnerAndLateCompletionResolvesItOnce() {
    let probe = PtpReleaseProbe()
    let release = probe.makeRelease()
    probe.observe(release)
    release.begin()
    probe.scheduled[0].perform()
    probe.scheduled[0].perform()
    XCTAssertEqual(probe.results, ["PTP_CLOSE_TIMEOUT"])
    XCTAssertEqual(probe.failures, ["PTP_CLOSE_TIMEOUT"])
    XCTAssertFalse(release.isReleased)
    XCTAssertTrue(probe.releasedIDs.isEmpty)

    probe.open = false
    probe.nativeCompletions[0](nil)
    probe.nativeCompletions[0](nil)
    XCTAssertTrue(release.isReleased)
    XCTAssertEqual(probe.releasedIDs, ["session"])
    // The failed MethodChannel call cannot receive a second result.
    XCTAssertEqual(probe.results, ["PTP_CLOSE_TIMEOUT"])
    probe.observe(release)
    XCTAssertEqual(probe.results, ["PTP_CLOSE_TIMEOUT", "released"])
  }

  func testStopDuringOpenClosesLateOpenedCameraBeforeReleasing() {
    let probe = PtpReleaseProbe()
    probe.opening = true
    probe.open = false
    let release = probe.makeRelease()
    probe.observe(release)
    release.begin()
    XCTAssertTrue(probe.results.isEmpty)
    XCTAssertTrue(probe.nativeCompletions.isEmpty)
    XCTAssertFalse(release.isReleased)

    probe.opening = false
    probe.open = true
    release.cameraStateChanged()
    release.cameraStateChanged()
    XCTAssertEqual(probe.nativeCompletions.count, 1)
    XCTAssertTrue(probe.results.isEmpty)
    probe.open = false
    probe.nativeCompletions[0](nil)
    XCTAssertEqual(probe.results, ["released"])
  }

  func testLateOpenAfterReleaseTimeoutStillGetsClosed() {
    let probe = PtpReleaseProbe()
    probe.opening = true
    probe.open = false
    let release = probe.makeRelease()
    probe.observe(release)
    release.begin()
    probe.scheduled[0].perform()
    XCTAssertEqual(probe.results, ["PTP_CLOSE_TIMEOUT"])
    XCTAssertTrue(probe.nativeCompletions.isEmpty)

    probe.opening = false
    probe.open = true
    release.cameraStateChanged()
    XCTAssertEqual(probe.nativeCompletions.count, 1)
    XCTAssertFalse(release.isReleased)
    probe.open = false
    probe.nativeCompletions[0](nil)
    XCTAssertTrue(release.isReleased)
    XCTAssertEqual(probe.releasedIDs, ["session"])
    XCTAssertEqual(probe.results, ["PTP_CLOSE_TIMEOUT"])
  }

  func testFailedPendingOpenReleasesWithoutIssuingClose() {
    let probe = PtpReleaseProbe()
    probe.opening = true
    probe.open = false
    let release = probe.makeRelease()
    probe.observe(release)
    release.begin()
    probe.opening = false
    release.cameraStateChanged()
    XCTAssertEqual(probe.results, ["released"])
    XCTAssertTrue(probe.nativeCompletions.isEmpty)
  }

  func testDetachedOrAlreadyClosedCameraNeedsNoNativeClose() {
    for disconnected in [false, true] {
      let probe = PtpReleaseProbe()
      probe.connected = !disconnected
      probe.opening = disconnected
      probe.open = disconnected
      let release = probe.makeRelease()
      probe.observe(release)
      release.begin()
      XCTAssertEqual(probe.results, ["released"])
      XCTAssertTrue(release.isReleased)
      XCTAssertTrue(probe.nativeCompletions.isEmpty)
    }
  }

  func testUnrelatedDelegateNotificationCannotFailOrDuplicateNativeClose() {
    let probe = PtpReleaseProbe()
    let release = probe.makeRelease()
    probe.observe(release)
    release.begin()
    release.cameraStateChanged()
    XCTAssertEqual(probe.nativeCompletions.count, 1)
    XCTAssertTrue(probe.results.isEmpty)
    XCTAssertNil(release.failure)
    probe.nativeCompletions[0](NSError(domain: "CameraTest", code: 7))
    XCTAssertEqual(probe.results, ["PTP_CLOSE_FAILED"])
    XCTAssertFalse(release.isReleased)
    probe.connected = false
    release.cameraStateChanged()
    XCTAssertTrue(release.isReleased)
    XCTAssertEqual(probe.releasedIDs, ["session"])
  }

  func testRepeatedStopWaitersShareSingleNativeClose() {
    let probe = PtpReleaseProbe()
    let release = probe.makeRelease()
    probe.observe(release)
    release.begin()
    probe.observe(release)
    release.begin()
    XCTAssertEqual(probe.nativeCompletions.count, 1)
    XCTAssertEqual(probe.scheduled.count, 1)
    probe.open = false
    probe.nativeCompletions[0](nil)
    XCTAssertEqual(probe.results, ["released", "released"])
    XCTAssertEqual(probe.releasedIDs, ["session"])
  }

  func testCancelledWaitingStartKeepsItsExactCloseOutcomeReachable() {
    let probe = PtpReleaseProbe()
    let release = probe.makeRelease(sessionID: "predecessor")
    release.begin()
    release.includeEndedOwner("cancelled-start")
    XCTAssertTrue(release.includesOwner("predecessor"))
    XCTAssertTrue(release.includesOwner("cancelled-start"))
    XCTAssertFalse(release.includesOwner("unrelated-start"))
    XCTAssertFalse(release.includesOwner(nil))
    probe.observe(release)
    probe.nativeCompletions[0](NSError(domain: "CameraTest", code: 7))
    XCTAssertEqual(probe.results, ["PTP_CLOSE_FAILED"])
    XCTAssertTrue(release.includesOwner("cancelled-start"))
    XCTAssertEqual(probe.nativeCompletions.count, 1)
    XCTAssertFalse(release.isReleased)
  }

  func testOldCloseCallbackAndDeadlineCannotReleaseNewOwner() {
    let probe = PtpReleaseProbe()
    let old = probe.makeRelease(sessionID: "old")
    probe.observe(old)
    old.begin()
    probe.open = false
    old.cameraStateChanged()
    XCTAssertEqual(probe.releasedIDs, ["old"])

    probe.open = true
    let current = probe.makeRelease(sessionID: "current")
    probe.observe(current)
    current.begin()
    XCTAssertEqual(probe.nativeCompletions.count, 2)
    probe.nativeCompletions[0](NSError(domain: "LateOldCallback", code: 7))
    probe.scheduled[0].perform()
    XCTAssertFalse(current.isReleased)
    XCTAssertNil(current.failure)
    XCTAssertEqual(probe.releasedIDs, ["old"])
    XCTAssertEqual(probe.results, ["released"])

    probe.open = false
    probe.nativeCompletions[1](nil)
    XCTAssertTrue(current.isReleased)
    XCTAssertEqual(probe.releasedIDs, ["old", "current"])
    XCTAssertEqual(probe.results, ["released", "released"])
  }

  func testWholeObjectFallbackAcceptsOnlyAnUnusedSupportedPartialOperation() {
    let unsupported = PtpTetherReply(responseCode: 0x2005, parameters: [], data: Data())
    XCTAssertTrue(PtpTetherCodec.canFallbackToWholeObject(unsupported, partialOpcode: 0x101B, receivedBytes: 0))
    XCTAssertTrue(PtpTetherCodec.canFallbackToWholeObject(unsupported, partialOpcode: 0x9107, receivedBytes: 0))
    XCTAssertFalse(PtpTetherCodec.canFallbackToWholeObject(unsupported, partialOpcode: nil, receivedBytes: 0))
    XCTAssertFalse(PtpTetherCodec.canFallbackToWholeObject(unsupported, partialOpcode: 0x1009, receivedBytes: 0))
  }

  func testWholeObjectFallbackRejectsDataReturnedWithUnsupportedResponse() {
    let ambiguous = PtpTetherReply(responseCode: 0x2005, parameters: [], data: Data([0xFF]))
    XCTAssertFalse(PtpTetherCodec.canFallbackToWholeObject(ambiguous, partialOpcode: 0x101B, receivedBytes: 0))
    XCTAssertFalse(PtpTetherCodec.canFallbackToWholeObject(ambiguous, partialOpcode: 0x9107, receivedBytes: 0))
  }

  func testWholeObjectFallbackDoesNotTreatUnsupportedParameterOrBusyAsUnsupportedOperation() {
    for code in [UInt16(0x2006), 0x2019, 0x2001] {
      let reply = PtpTetherReply(responseCode: code, parameters: [], data: Data())
      XCTAssertFalse(PtpTetherCodec.canFallbackToWholeObject(reply, partialOpcode: 0x101B, receivedBytes: 0))
    }
  }

  func testWholeObjectFallbackRejectsAnAlreadyStartedPhoto() {
    let unsupported = PtpTetherReply(responseCode: 0x2005, parameters: [], data: Data())
    for received in [1, PtpTetherCodec.partialChunkSize] {
      XCTAssertFalse(PtpTetherCodec.canFallbackToWholeObject(unsupported, partialOpcode: 0x101B, receivedBytes: received))
      XCTAssertFalse(PtpTetherCodec.canFallbackToWholeObject(unsupported, partialOpcode: 0x9107, receivedBytes: received))
    }
  }

  func testPtpEventRequiresCompleteEventEnvelope() {
    var event = ptpResponse(code: 0x4002, transaction: UInt32.max, parameters: [123])
    event[4] = 4
    XCTAssertTrue(PtpTetherCodec.validEvent(event))
    XCTAssertFalse(PtpTetherCodec.validEvent(ptpResponse()))
    XCTAssertFalse(PtpTetherCodec.validEvent(Data(event.dropLast())))
    XCTAssertFalse(PtpTetherCodec.validEvent(Data()))
  }

  func testPtpStagingRetainsDistinctTransfersForRepeatedSonyHandle() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let firstURL = directory.appendingPathComponent("first.jpg")
    let secondURL = directory.appendingPathComponent("second.jpg")
    try Data([1, 2, 3]).write(to: firstURL)
    try Data([4, 5, 6]).write(to: secondURL)
    let store = PtpTetherStagingStore()
    store.save(PtpTetherStagedFile(path: firstURL.path, name: "DSC0001.JPG", size: 3), sessionID: "old", transferID: "ram-1", handle: 0xFFFFC001)
    store.save(PtpTetherStagedFile(path: secondURL.path, name: "DSC0001.JPG", size: 3), sessionID: "old", transferID: "ram-2", handle: 0xFFFFC001)
    XCTAssertEqual(try store.lookup(sessionID: "old", transferID: "ram-1")?.path, firstURL.path)
    XCTAssertEqual(try store.lookup(sessionID: "old", transferID: "ram-2")?.path, secondURL.path)
    XCTAssertNil(try store.lookup(sessionID: "new", transferID: "ram-1"))
    XCTAssertThrowsError(try store.lookup(sessionID: "old", transferID: "ram-1", handle: 12)) { error in
      XCTAssertEqual((error as? PtpTetherFailure)?.code, "PTP_TRANSFER_ID_REUSED")
    }
    XCTAssertThrowsError(try store.lookup(sessionID: "old", transferID: "ram-1", expectedSize: 6))

    // A late old-session acknowledgement releases only its exact delivery.
    store.acknowledge(sessionID: "old", transferIDs: ["ram-1"])
    XCTAssertNil(try store.lookup(sessionID: "old", transferID: "ram-1"))
    XCTAssertNotNil(try store.lookup(sessionID: "old", transferID: "ram-2"))
    XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))
  }

  func testMissingOrTruncatedStagingCannotSilentlyRefetchNextSonyPhoto() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let store = PtpTetherStagingStore()
    store.save(PtpTetherStagedFile(path: url.path, name: "DSC0001.JPG", size: 4), sessionID: "session", transferID: "ram-1", handle: 0xFFFFC001)
    for bytes in [Data(), Data([1, 2])] {
      try bytes.write(to: url)
      XCTAssertThrowsError(try store.lookup(sessionID: "session", transferID: "ram-1")) { error in
        XCTAssertEqual((error as? PtpTetherFailure)?.code, "PTP_STAGED_FILE_MISSING")
      }
    }
    try FileManager.default.removeItem(at: url)
    XCTAssertThrowsError(try store.lookup(sessionID: "session", transferID: "ram-1"))
  }

  func testConsumedSonyReadWithDiskFailureCannotBeRetriedAsNextPhoto() {
    let store = PtpTetherStagingStore()
    store.markConsumedFailure(sessionID: "session", transferID: "ram-1")
    XCTAssertThrowsError(try store.lookup(sessionID: "session", transferID: "ram-1")) { error in
      XCTAssertEqual((error as? PtpTetherFailure)?.code, "PTP_STAGING_FAILED")
    }
    XCTAssertNil(try store.lookup(sessionID: "session", transferID: "ram-2"))
  }

}
