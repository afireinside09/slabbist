import SwiftUI
import SwiftData
import AVFoundation
import Vision
// `import os` is required for `OSAllocatedUnfairLock` used by
// `BulkScanController.crossThread`. The project enables
// `MemberImportVisibility`, so even though `os` is transitively pulled
// in by other modules we keep it explicit here.
import os

/// Holds scan-path state that must survive being captured by a `@Sendable`
/// closure fired off the MainActor. We keep the recognizer, view model,
/// and the reusable Vision request here so the sample-queue callback can
/// hold a single reference and read them after hopping to MainActor.
///
/// `@Observable` so SwiftUI re-renders `BulkScanView.body` when
/// `viewModel` transitions from `nil` to a live instance on bootstrap.
@MainActor
@Observable
final class BulkScanController {
    /// `permissive: true` so the recognizer fires on stable digit-only
    /// patterns even when Vision misreads the "PSA" keyword as "PEA" / "FA"
    /// (observed in production logs). The downstream review card lets the
    /// user override the inferred grader before the scan commits.
    let recognizer = CertOCRRecognizer(permissive: true)
    var viewModel: BulkScanViewModel?

    /// Live status driving the corner-bracket overlay and the status pill.
    /// Updated from the OCR pipeline (`reading` ⇄ `idle`) and from the
    /// view-model's lookup callback (`lookingUp` → `resolved` / `failed`).
    var status: ScannerStatus = .idle

    /// When the recognizer fires we capture the candidate here and pause
    /// further OCR. The review card UI surfaces the detected cert + grader
    /// for the user to confirm or edit before the scan commits — nothing
    /// auto-records anymore.
    var pendingReview: CertCandidate?

    /// Vision-detected slab rectangle in screen-space points. Drives the
    /// floating corner-bracket overlay. `nil` when no rectangle is detected
    /// this frame (or the most recent detection has decayed).
    var detectedSlabRect: CGRect?

    /// Cross-thread fields shared between MainActor writes and sample-queue
    /// reads. Held inside a single `OSAllocatedUnfairLock` so the
    /// non-Sendable `previewLayer` (UIKit) can be assigned from MainActor
    /// and read from the sample queue without `nonisolated(unsafe)` or a
    /// MainActor hop, and so the `ocrPaused` test-and-set in
    /// `presentReview` is atomic. `lastRectAt`, `lastTextSeenAt`, and
    /// `lastFrameLogAt` are eventually-consistent freshness timers —
    /// torn reads across the lock boundary are harmless (worst case: one
    /// extra debounce window). Mirrors `CameraSession.callbackStorage`.
    /// `uncheckedState` keeps the lock `Sendable` despite the
    /// `AVCaptureVideoPreviewLayer?` inside.
    nonisolated struct CrossThreadState {
        var previewLayer: AVCaptureVideoPreviewLayer?
        var lastRectAt: Date = .distantPast
        var ocrPaused: Bool = false
        var lastTextSeenAt: Date = .distantPast
        var lastFrameLogAt: Date = .distantPast
        /// Timestamp of the most recent scenePhase backgrounding. `nil`
        /// means the user has not yet left the scan view — first-time
        /// entry does NOT show the resume gate. Set on `.background` /
        /// `.inactive`, cleared only when the user taps to resume.
        var lastBackgroundedAt: Date?
        /// `true` while the resume gate is visible. The sample-queue OCR
        /// path consults this through `shouldSkipOCR()` so recognizer
        /// frames are dropped while the gate is up — auto-resume is
        /// forbidden by spec (the phone could be pocket-pointed).
        var ocrSuspendedForResume: Bool = false

        init() {}
    }
    @ObservationIgnored
    nonisolated let crossThread = OSAllocatedUnfairLock<CrossThreadState>(uncheckedState: CrossThreadState())

    /// Show the review card for a stable cert candidate. Returns `true`
    /// when this caller won the review window — false means another caller
    /// already presented for this window and this call was a no-op. The
    /// test-and-set on `ocrPaused` is atomic with the assignment so
    /// multiple concurrent stable hits (e.g. queued sample-queue hops)
    /// can't all flip `pendingReview` and the recognizer reset, which
    /// would double-record the same cert.
    @discardableResult
    func presentReview(_ candidate: CertCandidate) -> Bool {
        let won = crossThread.withLock { state -> Bool in
            guard !state.ocrPaused else { return false }
            state.ocrPaused = true
            return true
        }
        guard won else { return false }
        pendingReview = candidate
        // Reset the recognizer's stable window so it doesn't immediately
        // re-fire the same candidate when OCR resumes.
        recognizer.reset()
        return true
    }

    func dismissReview() {
        pendingReview = nil
        crossThread.withLock { $0.ocrPaused = false }
    }

    /// `true` while the resume-gate scrim is visible. Observable so the
    /// view can bind directly; the same boolean is mirrored into
    /// `crossThread.ocrSuspendedForResume` so the sample-queue OCR path
    /// can read it under the lock without a MainActor hop.
    var resumeGateActive: Bool = false

    /// Arm the gate after a `.background → .active` transition. The gate
    /// suppresses OCR until the user taps to resume; auto-resume is
    /// explicitly forbidden by spec (the phone could be pocket-pointed
    /// in the user's pocket). Also resets the recognizer so stale
    /// stable-frame windows can't fire across the background.
    func armResumeGate() {
        crossThread.withLock { $0.ocrSuspendedForResume = true }
        recognizer.reset()
        resumeGateActive = true
    }

    /// Dismiss the gate. The only path back to live OCR after a
    /// background — scenePhase changes never clear `ocrSuspendedForResume`.
    ///
    /// **Ordering matters.** Flip the observable `resumeGateActive` to
    /// `false` *before* releasing the lock-protected suppression flag.
    /// SwiftUI removes the scrim on the next render after the observable
    /// flip; if we cleared the suppression first, the sample queue could
    /// dispatch an OCR frame while the user still sees the "paused"
    /// scrim — a North-Star violation ("a confirmation flash through a
    /// paused scrim").
    func dismissResumeGate() {
        resumeGateActive = false
        crossThread.withLock {
            $0.ocrSuspendedForResume = false
            $0.lastBackgroundedAt = nil
        }
    }

    /// Record a backgrounding timestamp AND drop any stale review card.
    /// A `pendingReview` from N minutes ago is no longer actionable for a
    /// returning user; force-confirming it would record an offer against
    /// a card the user can't even see anymore. Wiping it here also
    /// releases `ocrPaused` (via the same path `dismissReview` uses), so
    /// once the gate is dismissed live scanning resumes cleanly instead
    /// of staying paused behind an invisible review modal.
    ///
    /// Only invoked from the `.background` scenePhase branch (not
    /// `.inactive`) — a Notification Center pulldown doesn't count as
    /// "user left the app", so it shouldn't arm the gate or drop the
    /// review card.
    func recordBackgrounded() {
        crossThread.withLock { $0.lastBackgroundedAt = Date() }
        // `dismissReview` no-ops when `pendingReview` is already nil,
        // so calling it unconditionally is safe and keeps the
        // `ocrPaused = false` reset in one place.
        dismissReview()
    }

    /// `true` when the most recent scenePhase visited `.background` or
    /// `.inactive` since the last gate dismissal. MainActor-only — the
    /// scenePhase handler reads this synchronously.
    var wasBackgrounded: Bool {
        crossThread.withLock { $0.lastBackgroundedAt != nil }
    }

    /// Single source of truth for "should the sample-queue OCR path
    /// drop this frame". Reads both pause flags under one lock so the
    /// pair is consistent — without this, the OCR loop could race
    /// `ocrPaused` clearing while the resume gate is up and process
    /// a frame anyway. Called nonisolated from the sample queue.
    nonisolated func shouldSkipOCR() -> Bool {
        crossThread.withLock { $0.ocrPaused || $0.ocrSuspendedForResume }
    }

    /// `resolved` and `failed` are dwell-states — once we enter them we
    /// hold the UI for ~2s so the user actually sees the outcome before a
    /// new OCR frame can flip us back to `reading`.
    @ObservationIgnored
    private var statusLockUntil: Date = .distantPast

    /// One reusable Vision request for the entire scan session. Allocating
    /// a new `VNRecognizeTextRequest` on every frame at ~30 FPS dominates
    /// the sample-queue budget; reuse drops per-frame cost to the request
    /// reset plus the actual recognition pass.
    ///
    /// `recognitionLevel = .accurate` is critical for cert digits: the
    /// `.fast` mode reads "12345678" as garbled mixed-case junk on small
    /// labels (confirmed in user trace logs) and confidence caps near 0.50,
    /// below the recognizer's stable-fire threshold.
    ///
    /// `nonisolated(unsafe)` because the request is read from the sample
    /// queue (background) inside the OCR closure. `VNRecognizeTextRequest`
    /// isn't Sendable, but exclusive ownership lives on the sample queue —
    /// the MainActor never touches it after initial assignment.
    @ObservationIgnored
    nonisolated(unsafe) let textRequest: VNRecognizeTextRequest = {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        return request
    }()

    /// Update status with respect to the dwell-lock on resolved/failed.
    /// Reading-state transitions (`reading` ⇄ `idle`) are blocked while a
    /// dwell-locked status is active so the user sees the outcome.
    func setStatus(_ next: ScannerStatus, dwellSeconds: Double = 0) {
        let now = Date()
        let isDwellRespecting = next == .reading || next == .idle
        if isDwellRespecting && now < statusLockUntil { return }
        status = next
        statusLockUntil = dwellSeconds > 0 ? now.addingTimeInterval(dwellSeconds) : .distantPast
    }
}

struct BulkScanView: View {
    let lot: Lot
    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session
    @Environment(OutboxKicker.self) private var kicker
    @Environment(Reachability.self) private var reachability
    @Environment(TabRouter.self) private var tabRouter
    @Environment(\.scenePhase) private var scenePhase

    @State private var cameraSession = CameraSession()
    @State private var controller = BulkScanController()
    @State private var lastCaptureFlash = false
    /// Owns the in-flight flash reset hop. Each call to `triggerFlash`
    /// cancels the prior task before spawning a new one so rapid captures
    /// can't race the reset back to `false` over the next `true`.
    @State private var flashTask: Task<Void, Never>?
    @State private var showingManualEntry = false
    @State private var showingPhotoScan = false
    /// Scan whose `ManualPriceSheet` is currently being presented from the
    /// inline `SetPricePill` on a queue row. `.sheet(item:)` drives
    /// presentation so multiple rapid taps land on a stable target.
    @State private var manualPriceTarget: Scan?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if targetEnvironment(simulator)
    @State private var simulatorFixtureIndex = 0
    #endif

    var body: some View {
        ZStack {
            ZStack(alignment: .bottom) {
                cameraArea
                    .ignoresSafeArea(edges: [.top, .horizontal])
                    .overlay(alignment: .center) {
                        AppColor.text
                            .opacity(lastCaptureFlash ? 0.35 : 0)
                            .allowsHitTesting(false)
                            .animation(.easeOut(duration: 0.25), value: lastCaptureFlash)
                    }
                    .overlay {
                        SlabFinderOverlay(
                            tone: controller.status.tone,
                            detectedRect: controller.detectedSlabRect
                        )
                    }
                    .overlay(alignment: .top) {
                        ScannerStatusPill(status: controller.status)
                            .padding(.top, Spacing.l)
                            .padding(.horizontal, Spacing.xxl)
                    }

                VStack(spacing: Spacing.m) {
                    #if targetEnvironment(simulator)
                    simulatorScanButton
                    #endif
                    if let viewModel = controller.viewModel {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            summaryHeader(for: viewModel)
                            ScanQueueView(
                                scans: viewModel.recentScans,
                                onRetry: { scan in viewModel.retryValidation(scan: scan) },
                                onRetryCompFetch: { scan in retryCompFetch(scan: scan) },
                                onPresentManualPrice: { scan in
                                    // P2.8 — the captured-review modal
                                    // and the manual-price sheet would
                                    // otherwise race for presentation
                                    // priority. Defer the sheet until
                                    // the review is resolved.
                                    guard controller.pendingReview == nil else { return }
                                    manualPriceTarget = scan
                                }
                            )
                        }
                        .padding(.horizontal, Spacing.xxl)
                        .padding(.vertical, Spacing.m)
                        .background(AppColor.ink.opacity(0.92))
                    }
                }
            }

            // Review modal lives in the outer ZStack so it paints above the
            // queue panel below. The previous layout nested the modal as an
            // overlay on `cameraArea`, which sits *behind* the bottom panel
            // in z-order — once enough scans landed, the queue grew over
            // the centered modal and obscured the confirm/discard buttons.
            if let pending = controller.pendingReview {
                CapturedReviewCard(
                    candidate: pending,
                    onConfirm: handleReviewConfirm,
                    onCancel: handleReviewCancel
                )
                .padding(.horizontal, Spacing.xxl)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

            // Resume gate is the topmost overlay so it covers the camera
            // AND any in-flight review card after a background → active
            // transition. The user has to tap to dismiss; OCR is held
            // suspended until then per spec ("phone might be in pocket").
            if controller.resumeGateActive {
                ResumeScanGate(onResume: { controller.dismissResumeGate() })
                    .transition(reduceMotion ? .identity : .opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: controller.pendingReview)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: controller.resumeGateActive)
        .background(AppColor.ink)
        .navigationDestination(for: Scan.self) { scan in
            ScanDetailView(scan: scan)
        }
        .navigationTitle(lot.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingPhotoScan = true
                } label: {
                    Image(systemName: "text.viewfinder")
                        .foregroundStyle(AppColor.gold)
                }
                .accessibilityLabel("Scan from photo")
                .accessibilityIdentifier("photo-scan-button")
                .disabled(controller.viewModel == nil)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingManualEntry = true
                } label: {
                    Image(systemName: "keyboard")
                        .foregroundStyle(AppColor.gold)
                }
                .accessibilityLabel("Manual entry")
                .accessibilityIdentifier("manual-entry-button")
                .disabled(controller.viewModel == nil)
            }
            // Finish scanning → jump straight to the lot the user just
            // built (Lots tab → lot detail) instead of making them back
            // out and navigate there by hand. The lot always exists (it's
            // passed in), so this is enabled regardless of scan count.
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    tabRouter.openLot(lot.id)
                }
                .font(SlabFont.sans(size: 16, weight: .semibold))
                .foregroundStyle(AppColor.gold)
                .accessibilityLabel("Done scanning")
                .accessibilityIdentifier("done-scanning-button")
            }
        }
        .sheet(isPresented: $showingManualEntry) {
            ManualEntrySheet { candidate in
                guard let viewModel = controller.viewModel else { return }
                try viewModel.record(candidate: candidate)
                triggerFlash()
            }
        }
        .fullScreenCover(isPresented: $showingPhotoScan, onDismiss: {
            #if !targetEnvironment(simulator)
            if cameraSession.authorization == .authorized,
               cameraSession.isConfigured,
               !cameraSession.isRunning {
                cameraSession.start()
            }
            #endif
        }) {
            if let viewModel = controller.viewModel {
                PhotoScanView(viewModel: viewModel)
            }
        }
        .onChange(of: showingPhotoScan) { _, isPresented in
            #if !targetEnvironment(simulator)
            if isPresented { cameraSession.stop() }
            #endif
        }
        .sheet(item: $manualPriceTarget) { scan in
            ManualPriceSheet(initialCents: scan.vendorAskCents) { cents in
                try setVendorAskCents(cents, on: scan)
            }
        }
        .onAppear {
            bootstrapViewModel()
            recoverLegacyFetchingRows()
            #if !targetEnvironment(simulator)
            Task { await configureCamera() }
            #endif
        }
        .onDisappear {
            cameraSession.stop()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Pause the capture stream when the app is backgrounded or
            // inactive — keeps the camera LED off and stops burning
            // battery on the OCR pipeline while the user is away. On
            // return to `.active`, if the user *was* backgrounded, arm
            // the resume gate — auto-resume is forbidden by spec so
            // OCR stays suspended until the user taps to confirm.
            //
            // **Why gate only on `.background`?** Notification Center
            // pulldown and Control Center swipes flip to `.inactive`
            // for ~1 second without ever leaving the app — gating on
            // `.inactive` would re-arm the resume scrim after every
            // shade pulldown. Real "user left the app" is `.background`.
            // `.inactive` only stops the camera (battery hygiene).
            switch newPhase {
            case .active:
                let wasBackgrounded = controller.wasBackgrounded
                if cameraSession.authorization == .authorized,
                   cameraSession.isConfigured,
                   !cameraSession.isRunning {
                    cameraSession.start()
                }
                // Only arm the gate when the camera will actually start —
                // if permission was revoked while backgrounded, the
                // `.denied` branch of `cameraArea` paints instead and
                // a tap-to-resume gate is meaningless.
                if wasBackgrounded,
                   cameraSession.authorization == .authorized,
                   cameraSession.isConfigured {
                    controller.armResumeGate()
                }
            case .background:
                controller.recordBackgrounded()
                cameraSession.stop()
            case .inactive:
                cameraSession.stop()
            @unknown default:
                break
            }
        }
    }

    @ViewBuilder
    private var cameraArea: some View {
        #if targetEnvironment(simulator)
        simulatorPreviewPlaceholder
        #else
        switch cameraSession.authorization {
        case .authorized:
            CameraPreview(
                session: cameraSession.captureSession,
                onPreviewLayer: { [controller] layer in
                    // Sample-queue rect detection reads this to convert
                    // Vision normalized rects → screen-space.
                    controller.crossThread.withLock { $0.previewLayer = layer }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .denied, .restricted:
            VStack(spacing: Spacing.m) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(AppColor.dim)
                Text("Camera access is required to scan slabs.")
                    .font(SlabFont.sans(size: 15))
                    .foregroundStyle(AppColor.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxl)
                PrimaryGoldButton(title: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .padding(.horizontal, Spacing.xxl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColor.ink)
        case .notDetermined:
            ProgressView()
                .tint(AppColor.gold)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColor.ink)
        @unknown default:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColor.ink)
        }
        #endif
    }

    #if targetEnvironment(simulator)
    private var simulatorPreviewPlaceholder: some View {
        ZStack {
            AppColor.ink
            VStack(spacing: Spacing.m) {
                Image(systemName: "camera.metering.center.weighted")
                    .font(.system(size: 44))
                    .foregroundStyle(AppColor.gold.opacity(0.7))
                Text("Simulator mode")
                    .font(SlabFont.sans(size: 15, weight: .semibold))
                    .foregroundStyle(AppColor.muted)
                Text("The iOS Simulator has no camera. Tap \"Simulate scan\" below to feed a fixture cert through the pipeline.")
                    .font(SlabFont.sans(size: 13))
                    .foregroundStyle(AppColor.dim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var simulatorScanButton: some View {
        Button(action: fireSimulatedScan) {
            Label("Simulate scan", systemImage: "wand.and.stars")
                .font(SlabFont.sans(size: 14, weight: .semibold))
                .foregroundStyle(AppColor.ink)
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.md)
                .background(AppColor.gold, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("simulate-scan")
    }

    private func fireSimulatedScan() {
        let fixtures: [(grader: Grader, keyword: String)] = [
            (.PSA, "PSA"), (.BGS, "BGS"), (.SGC, "SGC"), (.CGC, "CGC"),
        ]
        let pick = fixtures[simulatorFixtureIndex % fixtures.count]
        simulatorFixtureIndex += 1

        // Randomize cert digits so repeat taps don't trip local dedup.
        let certNumber: String
        switch pick.grader {
        case .PSA: certNumber = String(Int.random(in: 10_000_000...99_999_999))
        case .BGS, .CGC: certNumber = String(Int.random(in: 1_000_000_000...9_999_999_999))
        case .SGC: certNumber = String(Int.random(in: 10_000_000...99_999_999))
        case .TAG: certNumber = String(Int.random(in: 10_000_000...99_999_999))
        }

        let candidate = CertCandidate(
            grader: pick.grader,
            certNumber: certNumber,
            confidence: 0.95,
            rawText: "\(pick.keyword) \(certNumber) (simulator fixture)"
        )
        do {
            try controller.viewModel?.record(candidate: candidate)
            triggerFlash()
        } catch {
            AppLog.scans.error("simulated record failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    #endif

    private func summaryHeader(for viewModel: BulkScanViewModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            KickerLabel("Queue")
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text("\(viewModel.recentScans.count)").slabMetric()
                Text("scanned")
                    .font(SlabFont.sans(size: 13))
                    .foregroundStyle(AppColor.muted)
            }
        }
    }

    private func bootstrapViewModel() {
        guard controller.viewModel == nil, let userId = session.userId else { return }
        let comp = CompRepository.live()
        let cert = CertLookupRepository.live()
        let reach = self.reachability
        let viewModel = BulkScanViewModel(
            context: context,
            kicker: kicker,
            lot: lot,
            currentUserId: userId,
            compRepository: comp,
            certLookupRepository: cert,
            reachabilityStatus: { reach.status }
        )
        viewModel.onLookupEvent = { [weak controller] event in
            guard let controller else { return }
            switch event {
            case .started(let grader, let cert):
                controller.setStatus(.lookingUp(grader: grader, certNumber: cert))
            case .resolved(let label):
                controller.setStatus(.resolved(productLabel: label), dwellSeconds: 2.5)
            case .failed(let reason):
                controller.setStatus(.failed(message: reason), dwellSeconds: 2.5)
            }
        }
        controller.viewModel = viewModel
    }

    private func configureCamera() async {
        await cameraSession.requestAuthorization()
        guard cameraSession.authorization == .authorized else { return }
        do {
            try cameraSession.configure()
            // The callback fires on CameraSession's sample queue (background).
            // Vision runs there; we hop to MainActor only with plain Sendable
            // primitives (`[String]` + `Double`) so the UI thread never sees
            // per-frame OCR work.
            cameraSession.setOnSampleBuffer { [weak controller] sampleBuffer in
                guard let controller else { return }
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

                // Back-camera buffers arrive in the sensor's native landscape
                // orientation; with the device held portrait (the bulk-scan
                // UI is portrait-locked in practice), Vision needs `.right`
                // to upright the frame. Passing `.up` makes Vision try to
                // read text sideways and produces zero observations on a
                // vertical slab — that was the original "camera opens but
                // nothing happens" bug.
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)

                // Run rect detection unconditionally — drives the floating
                // corner brackets even while a review is pending so the user
                // sees the bracket "stay" on the slab they're confirming.
                // Read `previewLayer` inside the helper's MainActor hop so
                // the non-Sendable AVCaptureVideoPreviewLayer is never
                // captured by this @Sendable closure.
                Self.detectAndPublishSlabRect(
                    handler: handler,
                    controller: controller
                )

                // Skip OCR while a review card is up OR the resume gate
                // is armed after a background → foreground hop. Both
                // flags are pair-read under one lock inside
                // `shouldSkipOCR()` so the OCR loop can't race a partial
                // pause-state visible across the two flags.
                if controller.shouldSkipOCR() { return }

                let request = controller.textRequest
                do {
                    try handler.perform([request])
                } catch {
                    return
                }

                guard let results = request.results else { return }
                var texts: [String] = []
                var maxConfidence: Double = 0
                for obs in results {
                    guard let cand = obs.topCandidates(1).first else { continue }
                    texts.append(cand.string)
                    maxConfidence = max(maxConfidence, Double(cand.confidence))
                }

                let nowFrame = Date()
                if texts.isEmpty {
                    // No text this frame. If we've gone ~600ms without any
                    // text observation at all, drop the pill back to idle so
                    // the user knows to reposition.
                    let lastTextSeenAt = controller.crossThread.withLock { $0.lastTextSeenAt }
                    if nowFrame.timeIntervalSince(lastTextSeenAt) > 0.6 {
                        Task { @MainActor [weak controller] in
                            controller?.setStatus(.idle)
                        }
                    }
                    return
                }
                controller.crossThread.withLock { $0.lastTextSeenAt = nowFrame }
                Task { @MainActor [weak controller] in
                    controller?.setStatus(.reading)
                }

                // Vision returns one observation per detected text region —
                // "PSA", "MINT 10", and "12345678" land in separate strings.
                // `CertOCRPatterns.match` requires keyword AND digits in the
                // same string, so we join with newlines before handing off.
                let joinedText = texts.joined(separator: "\n")

                // Debounced diagnostic log: once a second, dump observation
                // count + max confidence + a short preview so a tester can
                // confirm OCR is alive (and correctly oriented) from
                // Console.app without a trace recording. `AppLog.ocr` is a
                // MainActor-isolated static, so hop to MainActor for the
                // log call — at ~1Hz the Task allocation is negligible.
                let shouldLog = controller.crossThread.withLock { state -> Bool in
                    if nowFrame.timeIntervalSince(state.lastFrameLogAt) >= 1.0 {
                        state.lastFrameLogAt = nowFrame
                        return true
                    }
                    return false
                }
                if shouldLog {
                    let preview = String(joinedText.prefix(120)).replacingOccurrences(of: "\n", with: " | ")
                    let obsCount = texts.count
                    let confSnapshot = maxConfidence
                    Task { @MainActor in
                        AppLog.ocr.debug(
                            "frame: \(obsCount, privacy: .public) obs, maxConf \(String(format: "%.2f", confSnapshot), privacy: .public) — \(preview, privacy: .public)"
                        )
                    }
                }

                // Send the Sendable primitives into the MainActor hop. The
                // recognizer and view model are read off the weakly-held
                // controller inside the hop.
                let capturedTexts = [joinedText]
                let capturedConfidence = maxConfidence
                Task { @MainActor [weak controller] in
                    guard let controller else { return }
                    guard let cert = controller.recognizer.ingest(
                        textCandidates: capturedTexts,
                        visionConfidence: capturedConfidence
                    ) else { return }
                    // `presentReview` test-and-sets `ocrPaused` internally;
                    // a `false` return means another concurrent stable hit
                    // already opened the review window for this cert.
                    guard controller.presentReview(cert) else { return }
                    AppLog.ocr.info("stable hit: \(cert.grader.rawValue, privacy: .public) \(cert.certNumber, privacy: .public) — presenting review")
                    triggerFlash()
                }
            }
            cameraSession.start()
        } catch {
            AppLog.camera.error("camera configure failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleReviewConfirm(_ candidate: CertCandidate) {
        defer { controller.dismissReview() }
        guard let viewModel = controller.viewModel else { return }
        do {
            try viewModel.record(candidate: candidate)
        } catch {
            AppLog.scans.error("review confirm record failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleReviewCancel() {
        controller.dismissReview()
    }

    /// Persist a per-scan manual price from the inline `SetPricePill`'s
    /// sheet. Routes through `LotsViewModel.setOfferCents` so the outbox
    /// patch + offline-first invariants match the path the detail screen
    /// uses — F3 introduces a new entry point but no new write surface.
    /// Throws `LotsViewModel.ResolveError` when no store has synced yet
    /// so `ManualPriceSheet` can render the error inline instead of
    /// swallowing the tap (P0.2).
    private func setVendorAskCents(_ cents: Int64?, on scan: Scan) throws {
        let viewModel = try LotsViewModel.requireResolve(context: context, kicker: kicker, session: session)
        try viewModel.setOfferCents(scan: scan, cents: cents)
    }

    /// Re-fire the comp fetch for a scan whose persisted state is stuck
    /// on `.fetching` because the originating task died with the app.
    /// Builds a fresh `CompRepository` so the call shares the singleton's
    /// in-flight de-dup keyset with every other comp fetch in the process.
    private func retryCompFetch(scan: Scan) {
        CompFetchService.fetch(scan: scan, repository: CompRepository.live(), context: context, kicker: kicker)
    }

    /// P1.5 — first-paint recovery for `compFetchStartedAt == nil` rows
    /// in the queue. Mirrors the same hatch in `LotDetailView` so users
    /// upgrading mid-session don't see a wall of negative Retry pills
    /// the moment they reopen the scan tab. `CompFetchService.fetch`
    /// de-dupes by `(identityId, service, grade)` so even repeated
    /// invocations across the bulk-scan VM's `recentScans` collapse to
    /// one upstream call per slab tier.
    private func recoverLegacyFetchingRows() {
        guard let viewModel = controller.viewModel else { return }
        let legacy = viewModel.recentScans.filter { scan in
            scan.compFetchState == CompFetchState.fetching.rawValue &&
            scan.compFetchStartedAt == nil &&
            scan.gradedCardIdentityId != nil &&
            scan.grade != nil
        }
        guard !legacy.isEmpty else { return }
        let repo = CompRepository.live()
        for scan in legacy {
            CompFetchService.fetch(scan: scan, repository: repo, context: context, kicker: kicker)
        }
    }

    /// Run `VNDetectRectanglesRequest` on the same VNImageRequestHandler the
    /// OCR pipeline already built. Cheap re-use because Vision caches the
    /// pixel buffer ingestion; an additional rectangle pass adds ~1–2ms on
    /// modern hardware. Publishes the screen-space rect onto the controller
    /// so the corner-bracket overlay can animate to it.
    static nonisolated func detectAndPublishSlabRect(
        handler: VNImageRequestHandler,
        controller: BulkScanController
    ) {
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.55   // slabs are ~0.65–0.75 (W/H portrait)
        request.maximumAspectRatio = 0.85
        request.minimumConfidence = 0.7
        request.minimumSize = 0.25
        request.maximumObservations = 1

        do {
            try handler.perform([request])
        } catch {
            return
        }

        guard let observation = request.results?.first else {
            // No detection this frame. If we've been without one for ~400ms
            // clear the published rect so the brackets fade.
            let now = Date()
            let lastRectAt = controller.crossThread.withLock { $0.lastRectAt }
            if now.timeIntervalSince(lastRectAt) > 0.4 {
                Task { @MainActor [weak controller] in
                    controller?.detectedSlabRect = nil
                }
            }
            return
        }

        controller.crossThread.withLock { $0.lastRectAt = Date() }

        // Vision: normalized 0–1, origin bottom-left, in the rotated portrait
        // frame (because we passed `.right` orientation). Convert to
        // metadata-output coords (origin top-left) for the AVCapture helper.
        let bb = observation.boundingBox
        let metadataRect = CGRect(
            x: bb.minX,
            y: 1 - bb.maxY,
            width: bb.width,
            height: bb.height
        )

        // Hop to MainActor to touch the non-Sendable preview layer. Compute
        // the screen-space rect inside the lock so only the Sendable CGRect
        // crosses the `withLock` boundary — CALayer itself is not Sendable
        // on iOS.
        Task { @MainActor [weak controller] in
            guard let controller else { return }
            let screenRect: CGRect? = controller.crossThread.withLock { state in
                state.previewLayer?.layerRectConverted(fromMetadataOutputRect: metadataRect)
            }
            guard let screenRect else { return }
            controller.detectedSlabRect = screenRect
        }
    }

    /// Pulse the capture flash overlay. Cancels the prior sleeper before
    /// spawning a new one so rapid captures don't race a stale `false`
    /// reset over the new `true`.
    private func triggerFlash() {
        flashTask?.cancel()
        lastCaptureFlash = true
        flashTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            lastCaptureFlash = false
        }
    }
}

