import Foundation
import Testing
@testable import slabbist

@Suite("GradeEstimateDTO")
struct GradeEstimateDTOTests {
    @Test("decodes a Postgrest row payload")
    func decodes() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "user_id": "22222222-2222-2222-2222-222222222222",
          "scan_id": null,
          "front_image_path": "u/e/front.jpg",
          "back_image_path":  "u/e/back.jpg",
          "front_thumb_path": "u/e/front_thumb.jpg",
          "back_thumb_path":  "u/e/back_thumb.jpg",
          "images_purged_at": null,
          "centering_front": {"left": 0.5, "right": 0.5, "top": 0.5, "bottom": 0.5},
          "centering_back":  {"left": 0.5, "right": 0.5, "top": 0.5, "bottom": 0.5},
          "sub_grades": {"centering": 8, "corners": 7, "edges": 8, "surface": 9},
          "sub_grade_notes": {"centering": "ok", "corners": "ok", "edges": "ok", "surface": "ok"},
          "composite_grade": 8,
          "confidence": "high",
          "verdict": "submit_value",
          "verdict_reasoning": "ok",
          "other_graders": null,
          "model_version": "claude-sonnet-4-6@2026-04-23-v1",
          "is_starred": false,
          "created_at": "2026-04-23T10:00:00Z"
        }
        """.data(using: .utf8)!

        let dto = try JSONCoders.decoder.decode(GradeEstimateDTO.self, from: json)
        #expect(dto.frontImagePath == "u/e/front.jpg")
        #expect(dto.subGrades.centering == 8)
        #expect(dto.compositeGrade == 8)
        #expect(dto.confidence == "high")
        #expect(dto.verdict == "submit_value")
        #expect(dto.scanId == nil)
        #expect(dto.imagesPurgedAt == nil)
    }
}
