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
        .background(AppColor.ink)
        .navigationTitle(lot.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            bootstrapViewModel()
            Task { await configureCamera() }
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
    }

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

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
