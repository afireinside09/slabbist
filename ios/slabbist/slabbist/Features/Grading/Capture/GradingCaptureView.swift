import SwiftUI
import UIKit
import AVFoundation
import os

struct GradingCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session = CameraSession()
    @State private var stillCapture: StillImageCapture?
    @State private var qualityMessage: String?
    @State private var showConsent: Bool = !UserDefaults.standard.bool(forKey: "preGradeConsentAccepted_v1")
    @State private var includeOtherGraders: Bool = false
    /// Holds the in-flight analysis/retry Task so Cancel can `.cancel()`
    /// it. Without this, a user tapping Cancel mid-analysis would
    /// dismiss the sheet but the background Task would keep running and
    /// possibly call `onComplete` on a dismissed view (P0.2).
    @State private var analysisTask: Task<Void, Never>?
    @State private var liveAnalyzer: LiveReadinessAnalyzer?
    /// One-shot guard so `onComplete` fires exactly once per produced
    /// estimate — `onChange(of:phase)` can observe `.done` more than once
    /// (e.g. a retry that re-enters analysis), and a double-fire would
    /// re-present the report.
    @State private var didComplete = false

    let viewModel: GradingCaptureViewModel
    /// Delivers the finished estimate so the host can show the report
    /// in-flow. Carries the whole DTO (the VM already has it) rather than
    /// just an id, so the host doesn't re-fetch what we just computed.
    let onComplete: (GradeEstimateDTO) -> Void

    private let detector = CardRectangleDetector()
    private let gate = CaptureQualityGate()

    /// True when the analysis overlay is the foreground UI. The camera
    /// session is paused while this is true to stop AV preview frames
    /// streaming behind the 86%-opaque scrim for no reason (P0.1).
    private var overlayPhase: Bool {
        switch viewModel.phase {
        case .uploading, .analyzing, .failed: return true
        default: return false
        }
    }

    /// True while the full-screen centering editor is up. The camera is
    /// paused and its content hidden behind the (opaque) editor.
    private var isAdjusting: Bool {
        switch viewModel.phase {
        case .adjustFront, .adjustBack: return true
        default: return false
        }
    }

    /// Camera should be paused whenever a full-screen layer covers it —
    /// the analysis overlay or the centering editor.
    private var cameraPaused: Bool { overlayPhase || isAdjusting }

    var body: some View {
        ZStack {
            cameraContent
                .accessibilityHidden(cameraPaused)
            CardOutlineOverlay(aligned: chipMessage == nil)
                .accessibilityHidden(cameraPaused)
            VStack {
                Spacer()
                QualityChip(message: chipMessage)
                    .padding(.bottom, Spacing.s)
                captureButton
                    .padding(.bottom, Spacing.xxxl)
            }
            .accessibilityHidden(cameraPaused)
        }
        .overlay {
            AnalysisOverlay(
                phase: viewModel.phase,
                error: viewModel.lastError,
                onRetry: { startAnalysisTask { try await viewModel.retry() } },
                onCancel: {
                    analysisTask?.cancel()
                    analysisTask = nil
                    dismiss()
                }
            )
        }
        .overlay {
            if isAdjusting,
               let image = viewModel.pendingAdjustImage,
               let guides = viewModel.pendingAdjustGuides {
                CenteringEditorView(
                    image: image,
                    guides: guides,
                    title: viewModel.phase == .adjustFront ? "Front centering" : "Back centering",
                    confirmLabel: "Use this centering",
                    onConfirm: { ratios in confirmAdjustedCentering(ratios) },
                    onCancel: { viewModel.cancelAdjust() }
                )
                .transition(.opacity)
            }
        }
        .task {
            await session.requestAuthorization()
            guard session.authorization == .authorized else { return }
            try? session.configure()
            // E1: attach the photo output while the session is configured
            // but not yet running. Mutating the session config via
            // begin/commitConfiguration on a running session pauses the
            // preview for ~200ms — and a capture tap during that pause
            // historically hung the continuation because AVFoundation
            // dropped the request without invoking the delegate. Building
            // the still-capture and attaching here keeps the capture
            // button correctly disabled (`captureEnabled` is false while
            // `stillCapture == nil`) until the attach has committed.
            let capture = StillImageCapture(session: session)
            do {
                try capture.attachIfNeeded()
                stillCapture = capture
            } catch {
                AppLog.camera.error("GradingCaptureView: still-image attach failed: \(String(describing: error), privacy: .public)")
                // P2.7: surface the failure to the user via the existing
                // QualityChip channel. Without this the capture button
                // would stay greyed out with no explanation — North Star
                // violation. The string mirrors how other capture-side
                // gates (blur, resolution) phrase themselves: short,
                // actionable, no jargon.
                qualityMessage = "Camera unavailable. Close and try again."
            }
            session.start()
            let analyzer = LiveReadinessAnalyzer { readiness in
                Task { @MainActor in viewModel.updateLiveReadiness(readiness) }
            }
            liveAnalyzer = analyzer
            session.setOnSampleBuffer { analyzer.handle($0) }
        }
        .onChange(of: cameraPaused) { _, paused in
            // Pause the AV session while a full-screen layer (analysis
            // overlay or the centering editor) is up; restart when the
            // user returns to a capture phase. The existing onDisappear
            // handles the sheet-leaving case — this only manages the
            // in-sheet overlay window. (P0.1)
            if paused {
                session.stop()
            } else if session.authorization == .authorized {
                session.start()
            }
        }
        .onDisappear {
            analysisTask?.cancel()
            analysisTask = nil
            session.setOnSampleBuffer(nil)
            liveAnalyzer = nil
            session.stop()
        }
        .sheet(isPresented: $showConsent) {
            FirstRunConsentView {
                UserDefaults.standard.set(true, forKey: "preGradeConsentAccepted_v1")
                showConsent = false
            }
            .interactiveDismissDisabled(true)
        }
        .onChange(of: viewModel.phase) { _, phase in
            if case .done = phase, !didComplete, let result = viewModel.result {
                didComplete = true
                onComplete(result)
            }
        }
    }

    /// Starts an analysis-related Task and stores its handle so Cancel
    /// can interrupt it. Cancellation of any previous task happens
    /// before the new one starts, so a fast double-tap on "Try again"
    /// doesn't fan out parallel uploads.
    private func startAnalysisTask(_ work: @escaping () async throws -> Void) {
        analysisTask?.cancel()
        analysisTask = Task {
            // `runAnalysis` / `retry` already write to viewModel.phase
            // (.failed) and viewModel.lastError on throw, so we just
            // swallow here. CancellationError is the expected path on
            // explicit Cancel — also swallow it.
            try? await work()
        }
    }

    @ViewBuilder
    private var cameraContent: some View {
        switch session.authorization {
        case .authorized, .notDetermined:
            CameraPreview(session: session.captureSession)
                .ignoresSafeArea()
        case .denied, .restricted:
            permissionRequired
        @unknown default:
            permissionRequired
        }
    }

    private var permissionRequired: some View {
        VStack(spacing: Spacing.l) {
            Image(systemName: "camera.fill")
                .font(SlabFont.sans(size: 36, weight: .regular))
                .foregroundStyle(AppColor.dim)
            VStack(spacing: Spacing.s) {
                Text("Camera access needed")
                    .slabRowTitle()
                Text("Slabbist uses your camera to photograph the front and back of the card. Open Settings to enable access.")
                    .font(SlabFont.sans(size: 13))
                    .foregroundStyle(AppColor.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PrimaryGoldButton(title: "Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
        .padding(.horizontal, Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.ink)
    }

    /// Big hollow gold ring with a radial-gradient inner disc — the
    /// "shutter" treatment from the design brief, shared with bulk scan.
    private var captureButton: some View {
        Button {
            Task { await captureCurrentSide() }
        } label: {
            ZStack {
                Circle()
                    .stroke(AppColor.gold, lineWidth: 4)
                    .frame(width: 78, height: 78)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [AppColor.gold, AppColor.goldDim],
                            center: .center,
                            startRadius: 0,
                            endRadius: 32
                        )
                    )
                    .frame(width: 64, height: 64)
                    .shadow(color: AppColor.ink.opacity(0.4), radius: 4, y: 2)
            }
        }
        .opacity(captureEnabled ? 1.0 : 0.4)
        .disabled(!captureEnabled)
        .accessibilityLabel(viewModel.phase == .front ? "Capture front" : "Capture back")
    }

    /// Explicit capture/attach errors take precedence over the live readiness
    /// reason so a "Camera unavailable" message isn't overwritten by "Card not
    /// detected".
    private var chipMessage: String? {
        qualityMessage ?? viewModel.liveReadiness?.message
    }

    private var captureEnabled: Bool {
        stillCapture != nil && qualityMessage == nil && (viewModel.liveReadiness?.isReady ?? false)
    }

    private func captureCurrentSide() async {
        guard let stillCapture else { return }
        do {
            let captured = try await stillCapture.capture()
            // Normalize to an upright pixel space so detection, metrics, and
            // centering all agree. AVCapture stills are sensor-landscape tagged
            // .right; analyzing the raw cgImage with Vision `.up` inverts the
            // card's aspect ratio and fails detection. No-op when already .up.
            let image = captured.uprightCGImage().map { UIImage(cgImage: $0) } ?? captured
            let detection = try await detector.detect(in: image)
            let metrics = CaptureMetrics.measure(image: image, cardRect: detection?.boundingBox)
            let outcome = gate.evaluate(
                image: image,
                cardDetection: detection,
                blurScore: metrics.blurScore,
                glareRatio: metrics.glareRatio
            )
            if case .rejected(let reason) = outcome {
                qualityMessage = reason
                return
            }
            qualityMessage = nil
            guard let det = detection else { return }
            let imageRect = CGRect(
                origin: .zero,
                size: CGSize(width: image.size.width * image.scale,
                             height: image.size.height * image.scale)
            )
            // Seed the eight guides from Vision (outer card edge) + the
            // inner-frame heuristic, then hand the still to the centering
            // editor. The centering the user dials in there — not the raw
            // auto-measurement — is what feeds the estimate.
            let guides = seedGuides(cardRect: det.boundingBox, imageRect: imageRect)
            viewModel.beginAdjust(image: image, guides: guides)
        } catch {
            qualityMessage = "Capture failed. Try again."
        }
    }

    /// Build normalized 8-guide seeds: outer lines on the Vision card rect,
    /// inner lines from `InnerFrameDetector`'s border heuristic.
    private func seedGuides(cardRect: CGRect, imageRect: CGRect) -> CenteringGuides {
        let w = imageRect.width, h = imageRect.height
        guard w > 0, h > 0 else { return .centeredDefault }
        let outer = CenteringGuides(
            outerLeft: cardRect.minX / w, innerLeft: cardRect.minX / w,
            innerRight: cardRect.maxX / w, outerRight: cardRect.maxX / w,
            outerTop: cardRect.minY / h, innerTop: cardRect.minY / h,
            innerBottom: cardRect.maxY / h, outerBottom: cardRect.maxY / h
        )
        return InnerFrameDetector.bestGuess(outer: outer)
    }

    /// Commit the centering the user confirmed in the editor. On the front
    /// we advance to back capture; on the back we kick the (cancellable)
    /// analysis just as the old auto-measured path did.
    private func confirmAdjustedCentering(_ ratios: CenteringRatios) {
        switch viewModel.phase {
        case .adjustFront:
            viewModel.confirmFront(centering: ratios)
        case .adjustBack:
            viewModel.confirmBack(centering: ratios)
            let includeFlag = includeOtherGraders
            startAnalysisTask {
                try await viewModel.runAnalysis(includeOtherGraders: includeFlag)
            }
        default:
            break
        }
    }
}
