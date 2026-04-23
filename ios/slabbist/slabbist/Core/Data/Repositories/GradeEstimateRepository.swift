import Foundation
import Supabase

nonisolated struct SupabaseGradeEstimateRepository: GradeEstimateRepository, Sendable {
    static let tableName = "grade_estimates"
    static let functionName = "grade-estimate"

    private let base: SupabaseRepository<GradeEstimateDTO>
    private let client: SupabaseClient

    init(client: SupabaseClient = AppSupabase.shared.client) {
        self.client = client
        self.base = SupabaseRepository(tableName: Self.tableName, client: client)
    }

    func listForCurrentUser(
        page: Page = .default,
        includeTotalCount: Bool = false
    ) async throws -> PagedResult<GradeEstimateDTO> {
        try await base.findPage(
            page: page,
            orderBy: "created_at",
            ascending: false,
            includeTotalCount: includeTotalCount
        )
    }

    func find(id: UUID) async throws -> GradeEstimateDTO? {
        try await base.find(id: id)
    }

    func setStarred(id: UUID, starred: Bool) async throws {
        do {
            _ = try await client.from(Self.tableName)
                .update(["is_starred": starred], returning: .minimal)
                .eq("id", value: id.uuidString)
                .execute()
        } catch {
            throw SupabaseError.map(error)
        }
    }

    func delete(id: UUID) async throws {
        try await base.delete(id: id)
    }

    func requestEstimate(
        frontPath: String,
        backPath: String,
        centeringFront: CenteringRatios,
        centeringBack: CenteringRatios,
        includeOtherGraders: Bool
    ) async throws -> GradeEstimateDTO {
        struct Body: Encodable {
            let front_image_path: String
            let back_image_path: String
            let centering_front: CenteringRatios
            let centering_back: CenteringRatios
            let include_other_graders: Bool
        }
        let body = Body(
            front_image_path: frontPath,
            back_image_path: backPath,
            centering_front: centeringFront,
            centering_back: centeringBack,
            include_other_graders: includeOtherGraders
        )
        do {
            let response: GradeEstimateDTO = try await client.functions
                .invoke(Self.functionName, options: FunctionInvokeOptions(body: body))
            return response
        } catch {
            throw SupabaseError.map(error)
        }
    }
}
