import SwiftUI
import UIKit
import AVFoundation

struct GradingCaptureView: View {
    @State private var session = CameraSession()
    @State private var stillCapture: StillImageCapture?
    @State private var qualityMessage: String?
    @State private var showConsent: Bool = !UserDefaults.standard.bool(forKey: "preGradeConsentAccepted_v1")
    @State private var includeOtherGraders: Bool = false

    let viewModel: GradingCaptureViewModel
    let onComplete: (UUID) -> Void

    private let detector = CardRectangleDetector()
    private let gate = CaptureQualityGate()

    var body: some View {
        ZStack {
            cameraContent
            CardOutlineOverlay(aligned: qualityMessage == nil)
            VStack {
                Spacer()
                QualityChip(message: qualityMessage)
                    .padding(.bottom, Spacing.s)
                captureButton
                    .padding(.bottom, Spacing.xxxl)
            }
        }
        .task {
            await session.requestAuthorization()
            guard session.authorization == .authorized else { return }
            try? session.configure()
            stillCapture = StillImageCapture(session: session)
            session.start()
        }
        .onDisappear { session.stop() }
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
                .font(.system(size: 36, weight: .regular))
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
            // Real blur/glare scoring is wired in a follow-up; for now we pass safe defaults
            // through the gate so it only short-circuits on resolution + card detection.
            let outcome = gate.evaluate(image: image, cardDetection: detection, blurScore: 200, glareRatio: 0)
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
                try await viewModel.runAnalysis(includeOtherGraders: includeOtherGraders)
            default:
                break
            }
        } catch {
            qualityMessage = "Capture failed. Try again."
        }
    }
}
