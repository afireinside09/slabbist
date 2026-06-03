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

    let viewModel: GradingCaptureViewModel
    let onComplete: (UUID) -> Void

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

    var body: some View {
        ZStack {
            cameraContent
                .accessibilityHidden(overlayPhase)
            CardOutlineOverlay(aligned: qualityMessage == nil)
                .accessibilityHidden(overlayPhase)
            VStack {
                Spacer()
                QualityChip(message: qualityMessage)
                    .padding(.bottom, Spacing.s)
                captureButton
                    .padding(.bottom, Spacing.xxxl)
            }
            .accessibilityHidden(overlayPhase)
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
        }
        .onChange(of: overlayPhase) { _, isOverlay in
            // Pause the AV session while the overlay is up; restart
            // when the user returns to capture phase (e.g. they Cancel
            // and the host pops them back, or they retry through to
            // .done which dismisses). The existing onDisappear handles
            // the sheet-leaving case — this only manages the in-sheet
            // overlay window. (P0.1)
            if isOverlay {
                session.stop()
            } else if session.authorization == .authorized {
                session.start()
            }
        }
        .onDisappear {
            analysisTask?.cancel()
            analysisTask = nil
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
            if case let .done(id) = phase {
                onComplete(id)
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

    private var captureEnabled: Bool {
        qualityMessage == nil && stillCapture != nil
    }

    private func captureCurrentSide() async {
        guard let stillCapture else { return }
        do {
            let image = try await stillCapture.capture()
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
            let psaRatios = CenteringMeasurement.measure(cardRect: det.boundingBox, in: imageRect)
            let centering = CenteringRatios(
                left: psaRatios.left,
                right: psaRatios.right,
                top: psaRatios.top,
                bottom: psaRatios.bottom
            )
            switch viewModel.phase {
            case .front:
                viewModel.recordFront(image: image, centering: centering)
            case .back:
                viewModel.recordBack(image: image, centering: centering)
                // Route through the cancellable Task handle so a Cancel
                // tap during the initial analyze can interrupt the
                // upload too (not just retries). `runAnalysis` writes
                // viewModel.lastError on throw — no need for a view
                // mirror. (P0.2 + P1.7)
                let includeFlag = includeOtherGraders
                startAnalysisTask {
                    try await viewModel.runAnalysis(includeOtherGraders: includeFlag)
                }
            default:
                break
            }
        } catch {
            qualityMessage = "Capture failed. Try again."
        }
    }
}
