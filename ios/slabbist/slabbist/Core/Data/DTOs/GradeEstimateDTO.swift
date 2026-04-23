import Foundation

nonisolated struct CenteringRatios: Codable, Sendable, Equatable {
    var left: Double
    var right: Double
    var top: Double
    var bottom: Double
}

nonisolated struct SubGrades: Codable, Sendable, Equatable {
    var centering: Double
    var corners: Double
    var edges: Double
    var surface: Double
}

nonisolated struct SubGradeNotes: Codable, Sendable, Equatable {
    var centering: String
    var corners: String
    var edges: String
    var surface: String
}

nonisolated struct PerGraderReport: Codable, Sendable, Equatable {
    var subGrades: SubGrades
    var subGradeNotes: SubGradeNotes
    var compositeGrade: Double
    var confidence: String
    var verdict: String
    var verdictReasoning: String

    enum CodingKeys: String, CodingKey {
        case subGrades = "sub_grades"
        case subGradeNotes = "sub_grade_notes"
        case compositeGrade = "composite_grade"
        case confidence
        case verdict
        case verdictReasoning = "verdict_reasoning"
    }
}

nonisolated struct OtherGradersBundle: Codable, Sendable, Equatable {
    var bgs: PerGraderReport
    var cgc: PerGraderReport
    var sgc: PerGraderReport
}

/// Wire shape for the `grade_estimates` Postgres table.
nonisolated struct GradeEstimateDTO: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    var userId: UUID
    var scanId: UUID?

    var frontImagePath: String
    var backImagePath: String
    var frontThumbPath: String
    var backThumbPath: String
    var imagesPurgedAt: Date?

    var centeringFront: CenteringRatios
    var centeringBack: CenteringRatios

    var subGrades: SubGrades
    var subGradeNotes: SubGradeNotes
    var compositeGrade: Double
    var confidence: String
    var verdict: String
    var verdictReasoning: String

    var otherGraders: OtherGradersBundle?
    var modelVersion: String
    var isStarred: Bool
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case scanId = "scan_id"
        case frontImagePath = "front_image_path"
        case backImagePath = "back_image_path"
        case frontThumbPath = "front_thumb_path"
        case backThumbPath = "back_thumb_path"
        case imagesPurgedAt = "images_purged_at"
        case centeringFront = "centering_front"
        case centeringBack = "centering_back"
        case subGrades = "sub_grades"
        case subGradeNotes = "sub_grade_notes"
        case compositeGrade = "composite_grade"
        case confidence
        case verdict
        case verdictReasoning = "verdict_reasoning"
        case otherGraders = "other_graders"
        case modelVersion = "model_version"
        case isStarred = "is_starred"
        case createdAt = "created_at"
    }
}
