import Foundation
import Testing
import Supabase
@testable import slabbist

/// Smoke tests for the Supabase data layer. These deliberately do
/// **not** hit the network — they verify construction and that the
/// repositories agree on table names and client wiring. Integration
/// tests against a live Supabase stack live separately.
@Suite("Supabase Repository")
struct SupabaseRepositoryTests {
    @Test("exposes the table name it was constructed with")
    func tableName() {
        let repo = SupabaseRepository<StoreDTO>(tableName: "stores")
        #expect(repo.tableName == "stores")
    }

    @Test("query() returns a builder for the same table")
    func queryBuilder() {
        let repo = SupabaseRepository<LotDTO>(tableName: "lots")
        _ = repo.query() // just confirm the call doesn't trap
    }

    @Test("concrete repositories declare the correct table names")
    func concreteTableNames() {
        #expect(SupabaseStoreRepository.tableName == "stores")
        #expect(SupabaseStoreMemberRepository.tableName == "store_members")
        #expect(SupabaseLotRepository.tableName == "lots")
        #expect(SupabaseScanRepository.tableName == "scans")
    }

    @Test("AppRepositories.live builds a full bundle")
    func appRepositoriesLive() {
        let bundle = AppRepositories.live()
        // Types are protocol-erased; existence check only.
        _ = bundle.stores
        _ = bundle.members
        _ = bundle.lots
        _ = bundle.scans
    }

    @Test("AuthService constructs against the shared Supabase client")
    func authServiceConstructs() {
        let service = AuthService()
        _ = service.stateChanges // touch the async stream accessor
    }
}
