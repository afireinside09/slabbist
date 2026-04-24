import SwiftUI
import SwiftData
import AVFoundation
import Vision
import OSLog

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
    let recognizer = CertOCRRecognizer()
    var viewModel: BulkScanViewModel?

    /// One reusable Vision request for the entire scan session. Allocating
    /// a new `VNRecognizeTextRequest` on every frame at ~30 FPS dominates
    /// the sample-queue budget; reuse drops per-frame cost to the request
    /// reset plus the actual recognition pass.
    @ObservationIgnored
    let textRequest: VNRecognizeTextRequest = {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        return request
    }()
}

struct BulkScanView: View {
    let lot: Lot
    @Environment(\.modelContext) private var context
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    @State private var cameraSession = CameraSession()
    @State private var controller = BulkScanController()
    @State private var lastCaptureFlash = false
    #if targetEnvironment(simulator)
    @State private var simulatorFixtureIndex = 0
    #endif

    var body: some View {
        ZStack(alignment: .bottom) {
            cameraArea
                .ignoresSafeArea(edges: [.top, .horizontal])
                .overlay(alignment: .center) {
                    Color.white
                        .opacity(lastCaptureFlash ? 0.35 : 0)
                        .allowsHitTesting(false)
                        .animation(.easeOut(duration: 0.18), value: lastCaptureFlash)
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
        .background(AppColor.ink)
        .navigationDestination(for: Scan.self) { scan in
            ScanDetailView(scan: scan)
        }
        .navigationTitle(lot.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
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
            CameraPreview(session: cameraSession.captureSession)
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
        controller.viewModel = BulkScanViewModel(context: context, lot: lot, currentUserId: userId)
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

                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
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
                guard !texts.isEmpty else { return }

                // Send the Sendable primitives into the MainActor hop. The
                // recognizer and view model are read off the weakly-held
                // controller inside the hop.
                let capturedTexts = texts
                let capturedConfidence = maxConfidence
                Task { @MainActor [weak controller] in
                    guard let controller else { return }
                    guard let cert = controller.recognizer.ingest(
                        textCandidates: capturedTexts,
                        visionConfidence: capturedConfidence
                    ) else { return }
                    do {
                        try controller.viewModel?.record(candidate: cert)
                        triggerFlash()
                    } catch {
                        AppLog.scans.error("record capture failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
            cameraSession.start()
        } catch {
            AppLog.camera.error("camera configure failed: \(error.localizedDescription, privacy: .public)")
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

