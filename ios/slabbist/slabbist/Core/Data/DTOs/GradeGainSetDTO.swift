import Foundation

/// One row from `get_grade_gain_sets` — an English set with ≥1
/// positive-spread product. `gainsCount` is the number of such products.
nonisolated struct GradeGainSetDTO: Codable, Sendable, Identifiable, Equatable, Hashable {
    let groupId: Int
    let groupName: String
    let gainsCount: Int
    let publishedOn: Date?

    var id: Int { groupId }

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case groupName = "group_name"
        case gainsCount = "gains_count"
        case publishedOn = "published_on"
    }
}
