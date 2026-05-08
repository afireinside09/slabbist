import SwiftUI
import SwiftData
import AVFoundation
import Vision
import OSLog
import Supabase
import Auth

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

    /// AVCaptureVideoPreviewLayer reference set by `CameraPreview`'s
    /// `onPreviewLayer` callback. Lives on the controller (a class) rather
    /// than as `@State` on the view so the sample-queue closure can read
    /// it lazily — the layer mounts after the first SwiftUI render pass,
    /// so capturing it `[weak]` from the view's `configureCamera()` would
    /// snapshot a nil before the layer was assigned.
    @ObservationIgnored
    nonisolated(unsafe) var previewLayer: AVCaptureVideoPreviewLayer?

    /// Most recent successful detection time. Used to fade the rect when no
    /// hit has come in for ~400ms so the brackets don't snap to stale coords.
    @ObservationIgnored
    nonisolated(unsafe) var lastRectAt: Date = .distantPast

    /// Cross-thread flag mirroring `pendingReview != nil`. The sample queue
    /// reads this synchronously to skip OCR while a review is up; the main
    /// actor flips it whenever it sets `pendingReview`.
    @ObservationIgnored
    nonisolated(unsafe) var ocrPaused: Bool = false

    func presentReview(_ candidate: CertCandidate) {
        pendingReview = candidate
        ocrPaused = true
        // Reset the recognizer's stable window so it doesn't immediately
        // re-fire the same candidate when OCR resumes.
        recognizer.reset()
    }

    func dismissReview() {
        pendingReview = nil
        ocrPaused = false
    }

    /// `resolved` and `failed` are dwell-states — once we enter them we
    /// hold the UI for ~2s so the user actually sees the outcome before a
    /// new OCR frame can flip us back to `reading`.
    @ObservationIgnored
    private var statusLockUntil: Date = .distantPast

    /// Last time a frame produced any text observations. After ~600ms of
    /// nothing we drop back to `.idle` so the user sees "Position slab in
    /// frame" again instead of a stale "Reading…".
    @ObservationIgnored
    nonisolated(unsafe) var lastTextSeenAt: Date = .distantPast

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

    /// Debounce for the per-frame OCR diagnostic log. Without this every frame
    /// at ~30 FPS would spam Console.app; we instead emit one summary line per
    /// second showing observation count + peak confidence so a tester can
    /// confirm the pipeline is alive without recording a trace.
    @ObservationIgnored
    nonisolated(unsafe) var lastFrameLogAt: Date = .distantPast

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
    @Environment(\.scenePhase) private var scenePhase

    @State private var cameraSession = CameraSession()
    @State private var controller = BulkScanController()
    @State private var lastCaptureFlash = false
    @State private var showingManualEntry = false
    #if targetEnvironment(simulator)
    @State private var simulatorFixtureIndex = 0
    #endif

    var body: some View {
        ZStack {
            ZStack(alignment: .bottom) {
                cameraArea
                    .ignoresSafeArea(edges: [.top, .horizontal])
                    .overlay(alignment: .center) {
                        Color.white
                            .opacity(lastCaptureFlash ? 0.35 : 0)
                            .allowsHitTesting(false)
                            .animation(.easeOut(duration: 0.18), value: lastCaptureFlash)
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
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            summaryHeader(for: viewModel)
                            ScanQueueView(scans: viewModel.recentScans)
                        }
                        .padding(.horizontal, Spacing.xxl)
                        .padding(.vertical, Spacing.l)
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
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: controller.pendingReview)
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
                    showingManualEntry = true
                } label: {
                    Image(systemName: "keyboard")
                        .foregroundStyle(AppColor.gold)
                }
                .accessibilityLabel("Manual entry")
                .accessibilityIdentifier("manual-entry-button")
                .disabled(controller.viewModel == nil)
            }
        }
        .sheet(isPresented: $showingManualEntry) {
            ManualEntrySheet { candidate in
                guard let viewModel = controller.viewModel else { return }
                try viewModel.record(candidate: candidate)
                triggerFlash()
            }
        }
        .onAppear {
            bootstrapViewModel()
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
            // battery on the OCR pipeline while the user is away.
            switch newPhase {
            case .active:
                if cameraSession.authorization == .authorized,
                   cameraSession.isConfigured,
                   !cameraSession.isRunning {
                    cameraSession.start()
                }
            case .inactive, .background:
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
                    // Stash the preview layer on the controller so the
                    // rect-detection helper (running on the sample queue)
                    // can convert Vision normalized rects → screen-space.
                    controller.previewLayer = layer
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
                .shadow(color: AppColor.gold.opacity(0.25), radius: 12, y: 6)
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
        let functionsBaseURL = AppEnvironment.supabaseURL.appendingPathComponent("/functions/v1")
        let tokenProvider: () async -> String? = {
            try? await AppSupabase.shared.client.auth.session.accessToken
        }
        let comp = CompRepository(baseURL: functionsBaseURL, authTokenProvider: tokenProvider)
        let cert = CertLookupRepository(baseURL: functionsBaseURL, authTokenProvider: tokenProvider)
        let viewModel = BulkScanViewModel(
            context: context,
            kicker: kicker,
            lot: lot,
            currentUserId: userId,
            compRepository: comp,
            certLookupRepository: cert
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

                // Skip OCR while a review card is up — accepting more reads
                // would race the user's confirm/edit decision and risk
                // double-recording. The flag is flipped on MainActor whenever
                // `pendingReview` changes; reading it from this queue is
                // racy but eventually consistent (worst case: one extra
                // frame's OCR runs).
                if controller.ocrPaused { return }

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
                    if nowFrame.timeIntervalSince(controller.lastTextSeenAt) > 0.6 {
                        Task { @MainActor [weak controller] in
                            controller?.setStatus(.idle)
                        }
                    }
                    return
                }
                controller.lastTextSeenAt = nowFrame
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
                if nowFrame.timeIntervalSince(controller.lastFrameLogAt) >= 1.0 {
                    controller.lastFrameLogAt = nowFrame
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
                    AppLog.ocr.info("stable hit: \(cert.grader.rawValue, privacy: .public) \(cert.certNumber, privacy: .public) — presenting review")
                    triggerFlash()
                    controller.presentReview(cert)
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
            if now.timeIntervalSince(controller.lastRectAt) > 0.4 {
                Task { @MainActor [weak controller] in
                    controller?.detectedSlabRect = nil
                }
            }
            return
        }

        controller.lastRectAt = Date()

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

        // Read the non-Sendable AVCaptureVideoPreviewLayer off the
        // controller inside the MainActor hop so it's never captured by
        // this @Sendable closure (Swift 6 errors on non-Sendable captures).
        Task { @MainActor [weak controller] in
            guard let controller, let previewLayer = controller.previewLayer else { return }
            let screenRect = previewLayer.layerRectConverted(fromMetadataOutputRect: metadataRect)
            controller.detectedSlabRect = screenRect
        }
    }

    /// Pulse the capture flash overlay. The animation on the overlay
    /// handles the fade; we drive it edge-to-edge with `lastCaptureFlash`
    /// and rely on `.animation(_:value:)` so overlapping triggers don't
    /// race a manual `Task.sleep`.
    private func triggerFlash() {
        lastCaptureFlash = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            lastCaptureFlash = false
        }
    }
}

