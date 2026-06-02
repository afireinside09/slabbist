import Foundation

enum GradeGainSection: Equatable {
    case idle
    case loading
    case loaded([GradeGainDTO])
    case error(String)
}
