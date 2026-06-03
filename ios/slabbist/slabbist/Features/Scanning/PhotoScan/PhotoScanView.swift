import SwiftUI
import OSLog

/// Cover-root coordinator for the photo-scan flow. Owns the grader selection,
/// the still camera, and the capture→OCR→parse→review phase machine. Confirmed
/// certs are recorded through the existing `BulkScanViewModel.record` path.
struct PhotoScanView: View {
    let viewModel: BulkScanViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var grader: Grader = .PSA
    @State private var phase: Phase = .capture
    @State private var camera = StillPhotoCamera()
    @State private var isCapturing = false

    enum Phase: Equatable {
        case capture
        case review([String])
    }

    var body: some View {
        Group {
            switch phase {
            case .capture:
                PhotoScanCaptureView(
                    grader: $grader,
                    camera: camera,
                    isCapturing: isCapturing,
                    onShutter: shutter,
                    onSimulate: { strings in process(recognizedStrings: strings) },
                    onCancel: { dismiss() }
                )
            case .review(let certs):
                PhotoScanReviewView(
                    grader: grader,
                    detectedCerts: certs,
                    existingCertsInLot: existingCerts(for: grader),
                    onCommit: commit,
                    onRetake: { phase = .capture }
                )
            }
        }
        .task {
            #if !targetEnvironment(simulator)
            await camera.requestAuthorization()
            guard camera.authorization == .authorized else { return }
            try? camera.configure()
            camera.start()
            #endif
        }
        .onDisappear { camera.stop() }
    }

    private func shutter() {
        guard !isCapturing else { return }
        isCapturing = true
        Task {
            let image = await camera.capture()
            let strings: [String]
            if let image {
                strings = await Task.detached { PhotoTextRecognizer.recognizeText(in: image) }.value
            } else {
                strings = []
            }
            isCapturing = false
            process(recognizedStrings: strings)
        }
    }

    private func process(recognizedStrings: [String]) {
        let certs = PhotoCertParser.extractCerts(from: recognizedStrings, grader: grader)
        phase = .review(certs)
    }

    /// Records each confirmed cert through the existing pipeline (dedup →
    /// cert-lookup → comp), then dismisses back to the live scanner.
    private func commit(_ certs: [String]) {
        for cert in certs {
            let candidate = CertCandidate(
                grader: grader,
                certNumber: cert,
                confidence: 1.0,
                rawText: "photo scan"
            )
            do {
                try viewModel.record(candidate: candidate)
            } catch {
                AppLog.scans.error("photo-scan record failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        dismiss()
    }

    /// Certs already in the lot for the chosen grader, so the review list can
    /// pre-exclude them.
    private func existingCerts(for grader: Grader) -> Set<String> {
        Set(viewModel.recentScans.filter { $0.grader == grader }.map(\.certNumber))
    }
}
