import Foundation
import RavonCore

@MainActor
@Observable
final class EarningsService {
    static let shared = EarningsService()

    var earnings: [CourierEarning] = []
    var summary = EarningsSummary(totalDeliveries: 0, totalDeliveryFees: 0, totalTips: 0, totalEarned: 0)
    var selectedPeriod: EarningsPeriod = .today
    var isLoading = false

    private init() {}

    func fetchEarnings() async {
        isLoading = true
        do {
            let period = mapPeriod(selectedPeriod)
            earnings = try await SupabaseService.shared.fetchEarnings(period: period)
            summary = try await SupabaseService.shared.fetchEarningsSummary(period: period)
        } catch {
            // Silently handle — earnings screen will show empty state
        }
        isLoading = false
    }

    func setPeriod(_ period: EarningsPeriod) {
        selectedPeriod = period
        Task {
            await fetchEarnings()
        }
    }

    private func mapPeriod(_ period: EarningsPeriod) -> SupabaseService.EarningsPeriod {
        switch period {
        case .today: .today
        case .week: .week
        case .month: .month
        case .all: .all
        }
    }
}
