import Foundation
import Testing
@testable import slabbist

/// E1: validate the continuation-safety contract introduced when the
/// photo output moved to eager-attach. A real `AVCaptureSession` path
/// can't be exercised in a unit test (no camera in the simulator), so
/// these tests pin down the two failure paths that previously left the
/// continuation captured-but-never-resumed.
@MainActor
struct StillImageCaptureTests {
    /// Before E1, `capture()` called against an unattached output would
    /// invoke `photoOutput.capturePhoto(with:delegate:)` against an
    /// output that wasn't on a running session — the delegate never
    /// fires and the continuation hangs forever. The fix surfaces the
    /// failure as `StillImageCaptureError.notAttached` synchronously,
    /// BEFORE any continuation is installed.
    ///
    /// P1.4: `.notAttached` is a synchronous Swift guard at the top of
    /// `capture()`; a correct implementation returns within microseconds
    /// of the call site, not seconds. We bound the race generously
    /// (3 seconds) to absorb parallel-test scheduler jitter while still
    /// catching regressions that actually hang on a continuation — the
    /// pre-fix bug had no upper bound, so 3s vs. infinity is what
    /// matters; 3s vs. 200ms doesn't.
    @Test func captureBeforeAttachThrowsNotAttached() async throws {
        let session = CameraSession()
        let capture = StillImageCapture(session: session)
        // Deliberately NOT calling `attachIfNeeded()` — that's the bug
        // shape: a regression that constructs the capture but skips the
        // attach hook must fail loudly, not hang.
        let result = try await runBoundedSync(milliseconds: 3000) {
            do {
                _ = try await capture.capture()
                return "no-throw"
            } catch let error as StillImageCaptureError {
                return String(describing: error)
            } catch {
                return "other:\(error)"
            }
        }
        #expect(result == "notAttached")
    }

    /// P1.5: `.alreadyInFlight` is a PURE-SWIFT guard on the second call
    /// — it fires before `photoOutput.capturePhoto` is ever invoked, so
    /// it's safely testable without AVFoundation hardware. We use the
    /// DEBUG-only `_testOnly_startPinnedInFlightCapture` seam to install
    /// a non-nil continuation in the slot, then call `capture()` from
    /// the MainActor and assert the second call throws `.alreadyInFlight`
    /// instead of overwriting the first continuation (the bug shape that
    /// originally hung the first caller forever).
    @Test func captureWhileInFlightThrowsAlreadyInFlight() async throws {
        let session = CameraSession()
        let capture = StillImageCapture(session: session)
        let pinTask = capture._testOnly_startPinnedInFlightCapture()
        // Yield so the pin Task gets to install its continuation into
        // the slot before we race the second `capture()`. Without this,
        // the guard would race the pin and could observe an empty slot.
        await Task.yield()
        await Task.yield()

        let result = try await runBoundedSync(milliseconds: 3000) {
            do {
                _ = try await capture.capture()
                return "no-throw"
            } catch let error as StillImageCaptureError {
                return String(describing: error)
            } catch {
                return "other:\(error)"
            }
        }
        #expect(result == "alreadyInFlight")

        // Cancel the pin Task so the test scope can unwind. The pinned
        // continuation isn't resumed here — the SUT's deinit handles it
        // when `capture` falls out of scope at end of test.
        pinTask.cancel()
    }

    /// Sanity: these cases must remain distinct so callers (and the
    /// continuation-safety contract) can pattern-match meaningfully. If
    /// a future refactor collapses two cases together, the precise fail
    /// reason — "attach never happened" vs "double-tap during in-flight"
    /// — would be lost from the failures-sheet `lastError`.
    @Test func errorEnumDistinctCases() {
        #expect(StillImageCaptureError.notAttached != StillImageCaptureError.cannotAttach)
        #expect(StillImageCaptureError.notAttached != StillImageCaptureError.alreadyInFlight)
        #expect(StillImageCaptureError.cannotAttach != StillImageCaptureError.alreadyInFlight)
    }
}

/// P1.4: a bounded race that lets the operation complete OR fails the
/// test if it exceeds `milliseconds`. The `.notAttached` and
/// `.alreadyInFlight` guards are synchronous Swift checks — a correct
/// implementation returns in microseconds. The bound is generous (a few
/// seconds) so parallel-test scheduler jitter doesn't flake; the load-
/// bearing property is "fail in finite time" vs. the pre-fix "hang
/// forever on the continuation", not the precise wall-clock value.
@MainActor
private func runBoundedSync<T>(
    milliseconds: Int,
    _ operation: @escaping @MainActor () async -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { @MainActor in
            await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
            throw BoundedSyncTimeout()
        }
        guard let first = try await group.next() else {
            throw BoundedSyncTimeout()
        }
        group.cancelAll()
        return first
    }
}

private struct BoundedSyncTimeout: Error {}
