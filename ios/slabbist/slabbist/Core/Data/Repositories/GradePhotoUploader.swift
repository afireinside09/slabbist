import Foundation
import UIKit
import Supabase

/// Protocol for capture-flow injection (real uploader vs in-test fake).
nonisolated protocol PhotoUploader: Sendable {
    func upload(front: UIImage, back: UIImage, userId: UUID) async throws -> GradePhotoUploader.UploadResult
}

nonisolated struct GradePhotoUploader: Sendable {
    private let client: SupabaseClient

    init(client: SupabaseClient = AppSupabase.shared.client) {
        self.client = client
    }

    struct UploadResult: Sendable {
        let estimateId: UUID
        let frontPath: String
        let backPath: String
        let frontThumbPath: String
        let backThumbPath: String
    }

    private func jpegOrThrow(_ image: UIImage, quality: CGFloat) throws -> Data {
        guard let data = image.jpegData(compressionQuality: quality) else {
            throw NSError(domain: "GradePhotoUploader", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "jpeg encoding failed"])
        }
        return data
    }

    private func thumbnail(_ image: UIImage) -> UIImage {
        let target = CGSize(width: 400, height: 560)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1   // thumbnails are pixel-fixed; don't multiply by display scale
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

extension GradePhotoUploader: PhotoUploader {
    func upload(front: UIImage, back: UIImage, userId: UUID) async throws -> UploadResult {
        let estimateId = UUID()
        let prefix = "\(userId.uuidString.lowercased())/\(estimateId.uuidString.lowercased())"

        let frontPath = "\(prefix)/front.jpg"
        let backPath = "\(prefix)/back.jpg"
        let frontThumbPath = "\(prefix)/front_thumb.jpg"
        let backThumbPath = "\(prefix)/back_thumb.jpg"

        let frontData = try jpegOrThrow(front, quality: 0.9)
        let backData = try jpegOrThrow(back, quality: 0.9)
        let frontThumbData = try jpegOrThrow(thumbnail(front), quality: 0.85)
        let backThumbData = try jpegOrThrow(thumbnail(back), quality: 0.85)

        // Supabase Swift SDK 2.x: upload(_ path: String, data: Data, options: FileOptions)
        let bucket = client.storage.from("grade-photos")
        let jpegOptions = FileOptions(contentType: "image/jpeg")
        try await bucket.upload(frontPath, data: frontData, options: jpegOptions)
        try await bucket.upload(backPath, data: backData, options: jpegOptions)
        try await bucket.upload(frontThumbPath, data: frontThumbData, options: jpegOptions)
        try await bucket.upload(backThumbPath, data: backThumbData, options: jpegOptions)

        return UploadResult(
            estimateId: estimateId,
            frontPath: frontPath,
            backPath: backPath,
            frontThumbPath: frontThumbPath,
            backThumbPath: backThumbPath
        )
    }
}
