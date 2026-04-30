import Foundation

/// One row from `public.get_movers_sets` — a Pokémon set (group) that
/// has at least one mover row in the requested category + sub_type.
/// `publishedOn` is nullable in Postgres (`tcg_groups.published_on`)
/// for sets without a known release date; iOS uses it only as the
/// secondary sort key, so a missing value is harmless.
nonisolated struct MoversSetDTO: Codable, Sendable, Identifiable, Equatable, Hashable {
    let groupId: Int
    let groupName: String
    let moversCount: Int
    let publishedOn: Date?

    var id: Int { groupId }

    enum CodingKeys: String, CodingKey {
        case groupId      = "group_id"
        case groupName    = "group_name"
        case moversCount  = "movers_count"
        case publishedOn  = "published_on"
    }

    init(groupId: Int, groupName: String, moversCount: Int, publishedOn: Date? = nil) {
        self.groupId = groupId
        self.groupName = groupName
        self.moversCount = moversCount
        self.publishedOn = publishedOn
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.groupId      = try c.decode(Int.self, forKey: .groupId)
        self.groupName    = try c.decode(String.self, forKey: .groupName)
        self.moversCount  = try c.decode(Int.self, forKey: .moversCount)
        // Postgres returns published_on as a date-only ISO string. The
        // shared decoder is configured for iso8601-with-time; fall back
        // to a manual parse so a date-only value doesn't fail the row.
        if let raw = try c.decodeIfPresent(String.self, forKey: .publishedOn) {
            self.publishedOn = Self.dateOnly.date(from: raw)
                ?? Self.fullIso.date(from: raw)
        } else {
            self.publishedOn = nil
        }
    }

    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let fullIso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
