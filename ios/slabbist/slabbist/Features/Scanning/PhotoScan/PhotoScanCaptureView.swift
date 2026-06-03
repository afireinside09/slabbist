import SwiftUI

/// Capture screen for the photo-scan flow: pick the grader, frame the slabs,
/// tap the shutter. Camera concerns only — OCR + parsing happen in the
/// coordinator (`PhotoScanView`). Mirrors `BulkScanView`'s camera-permission
/// and simulator handling.
struct PhotoScanCaptureView: View {
    @Binding var grader: Grader
    let camera: StillPhotoCamera
    let isCapturing: Bool
    /// Real shutter — coordinator captures a still then OCRs it.
    let onShutter: () -> Void
    /// Simulator-only — feed fixture OCR strings straight to the parser.
    let onSimulate: ([String]) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            AppColor.ink.ignoresSafeArea()
            VStack(spacing: Spacing.l) {
                graderPicker
                cameraArea
                    .clipShape(RoundedRectangle(cornerRadius: Radius.l))
                shutterRow
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.vertical, Spacing.l)
        }
        .overlay(alignment: .topLeading) {
            SecondaryIconButton(systemIcon: "xmark", accessibilityLabel: "Cancel") {
                onCancel()
            }
            .padding(.top, Spacing.l)
            .padding(.leading, Spacing.l)
        }
    }

    private var graderPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("Grading company")
            Picker("Grader", selection: $grader) {
                ForEach(Grader.allCases, id: \.self) { g in
                    Text(g.rawValue).tag(g)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("photo-scan-grader-picker")
        }
    }

    @ViewBuilder
    private var cameraArea: some View {
        #if targetEnvironment(simulator)
        ZStack {
            AppColor.surface
            VStack(spacing: Spacing.m) {
                Image(systemName: "camera.metering.center.weighted")
                    .font(.system(size: 40))
                    .foregroundStyle(AppColor.gold.opacity(0.7))
                Text("Simulator — no camera")
                    .font(SlabFont.sans(size: 13))
                    .foregroundStyle(AppColor.dim)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        switch camera.authorization {
        case .authorized:
            CameraPreview(session: camera.captureSession)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .denied, .restricted:
            VStack(spacing: Spacing.m) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(AppColor.dim)
                Text("Camera access is required to scan slabs.")
                    .font(SlabFont.sans(size: 15))
                    .foregroundStyle(AppColor.muted)
                    .multilineTextAlignment(.center)
                PrimaryGoldButton(title: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
            .padding(Spacing.xxl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .notDetermined:
            ProgressView()
                .tint(AppColor.gold)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        @unknown default:
            ProgressView()
                .tint(AppColor.gold)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #endif
    }

    private var shutterRow: some View {
        VStack(spacing: Spacing.m) {
            #if targetEnvironment(simulator)
            Button("Simulate photo") {
                // Two PSA-shaped certs + a year to prove filtering, so the
                // simulator exercises the full parse → review path.
                onSimulate(["GEM MT 10", "09812345", "POKEMON 2022", "081234567"])
            }
            .font(SlabFont.sans(size: 14, weight: .semibold))
            .foregroundStyle(AppColor.ink)
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.md)
            .background(AppColor.gold, in: Capsule())
            .accessibilityIdentifier("photo-scan-simulate")
            #else
            Button(action: onShutter) {
                ZStack {
                    Circle().fill(AppColor.gold).frame(width: 68, height: 68)
                    if isCapturing {
                        ProgressView().tint(AppColor.ink)
                    } else {
                        Circle().stroke(AppColor.ink, lineWidth: 3).frame(width: 56, height: 56)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isCapturing)
            .accessibilityLabel("Capture photo")
            .accessibilityIdentifier("photo-scan-shutter")
            #endif
        }
    }
}
