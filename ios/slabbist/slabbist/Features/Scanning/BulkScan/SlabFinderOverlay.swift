import SwiftUI

/// Floating corner-bracket reticle drawn over the camera preview. Gives the
/// user a target to align the slab to and reflects pipeline state through
/// color: neutral (white-dim) while searching, gold while actively reading
/// or looking up, green on a successful cert resolve, red on failure.
///
/// We use a fixed-position card-aspect rectangle (same aesthetic as the
/// grading-capture overlay) rather than snapping to a per-frame Vision
/// rectangle detection. Snapping reads as jittery on a hand-held device and
/// the camera-preview's aspectFill crop makes coordinate conversion fiddly;
/// a static reticle is what the user actually wants for alignment.
struct SlabFinderOverlay: View {
    let tone: ScannerStatus.Tone
    /// Live rectangle from `VNDetectRectanglesRequest`, in screen-space
    /// points (already converted via `AVCaptureVideoPreviewLayer
    /// .layerRectConverted(fromMetadataOutputRect:)`). When non-nil the
    /// brackets float to the detected slab; when nil they fall back to a
    /// centered card-aspect guide so the user has a target to align to.
    let detectedRect: CGRect?

    @State private var pulse: CGFloat = 1.0

    var body: some View {
        GeometryReader { proxy in
            let rect = detectedRect.flatMap { clamp($0, in: proxy.size) }
                ?? defaultReticleRect(in: proxy.size)
            CornerBrackets(rect: rect, color: color, lineWidth: lineWidth, length: bracketLength(for: rect))
                .scaleEffect(detectedRect == nil && tone == .neutral ? pulse : 1.0, anchor: .center)
                .animation(detectedRect == nil && tone == .neutral
                           ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
                           : .easeOut(duration: 0.18),
                           value: pulse)
                .animation(.spring(response: 0.28, dampingFraction: 0.82), value: rect)
                .animation(.easeOut(duration: 0.18), value: tone)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear { pulse = 1.04 }
    }

    /// Vision occasionally returns rects with a few pixels off-screen due to
    /// the buffer-vs-aspect-fill-crop conversion. Snap them back into the
    /// preview bounds so the brackets don't visually leave the screen.
    private func clamp(_ r: CGRect, in size: CGSize) -> CGRect {
        let minX = max(0, r.minX)
        let minY = max(0, r.minY)
        let maxX = min(size.width, r.maxX)
        let maxY = min(size.height, r.maxY)
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    private func defaultReticleRect(in container: CGSize) -> CGRect {
        let cardSize = reticleSize(in: container)
        return CGRect(
            x: (container.width - cardSize.width) / 2,
            y: (container.height - cardSize.height) / 2,
            width: cardSize.width,
            height: cardSize.height
        )
    }

    private var color: Color {
        switch tone {
        case .neutral: return Color.white.opacity(0.55)
        case .active:  return AppColor.gold
        case .success: return AppColor.positive
        case .error:   return AppColor.negative
        }
    }

    private var lineWidth: CGFloat {
        switch tone {
        case .neutral: return 3
        case .active, .success, .error: return 4
        }
    }

    private func reticleSize(in container: CGSize) -> CGSize {
        let aspect: CGFloat = 0.71428  // standard trading-card 2.5x3.5
        let maxW = container.width * 0.78
        let maxH = container.height * 0.62
        if maxW / aspect <= maxH {
            return CGSize(width: maxW, height: maxW / aspect)
        }
        return CGSize(width: maxH * aspect, height: maxH)
    }

    private func bracketLength(for rect: CGRect) -> CGFloat {
        // Bracket arms cover ~14% of the shorter side. Keeps the corners
        // readable without enclosing the slab.
        min(rect.width, rect.height) * 0.14
    }
}

private nonisolated struct CornerBrackets: Shape {
    let rect: CGRect
    let color: Color   // unused in path; the View applies stroke. Kept for API symmetry.
    let lineWidth: CGFloat
    let length: CGFloat

    func path(in _: CGRect) -> Path {
        var path = Path()
        let radius: CGFloat = 14

        // Top-left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        // Top-right
        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        // Bottom-right
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))

        // Bottom-left
        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))

        return path
    }
}

extension CornerBrackets: View {
    var body: some View {
        path(in: .zero)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }
}

/// Status text shown above the reticle. Pinned near the top of the camera
/// area, just below the nav bar.
struct ScannerStatusPill: View {
    let status: ScannerStatus

    var body: some View {
        HStack(spacing: Spacing.s) {
            indicator
            Text(status.pillText)
                .font(SlabFont.sans(size: 14, weight: .semibold))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
        .background(Capsule().fill(AppColor.ink.opacity(0.78)))
        .overlay(Capsule().stroke(borderColor, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
        .animation(.easeOut(duration: 0.2), value: status)
    }

    @ViewBuilder
    private var indicator: some View {
        switch status.tone {
        case .neutral:
            Image(systemName: "viewfinder")
                .foregroundStyle(Color.white.opacity(0.7))
        case .active:
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(AppColor.gold)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppColor.positive)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppColor.negative)
        }
    }

    private var textColor: Color {
        switch status.tone {
        case .neutral: return Color.white.opacity(0.85)
        case .active:  return AppColor.text
        case .success: return AppColor.positive
        case .error:   return AppColor.negative
        }
    }

    private var borderColor: Color {
        switch status.tone {
        case .neutral: return Color.white.opacity(0.18)
        case .active:  return AppColor.gold.opacity(0.45)
        case .success: return AppColor.positive.opacity(0.55)
        case .error:   return AppColor.negative.opacity(0.55)
        }
    }
}
