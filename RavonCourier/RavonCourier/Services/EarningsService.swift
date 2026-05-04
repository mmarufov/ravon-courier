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
            let rows = try await SupabaseService.shared.fetchEarnings(period: period)
            earnings = rows
            summary = computeSummary(rows)
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

    /// Includes `totalClawbacks` (sum of magnitudes for negative-tier rows),
    /// which the shared `fetchEarningsSummary` helper doesn't compute.
    private func computeSummary(_ rows: [CourierEarning]) -> EarningsSummary {
        let clawbacks = rows.filter(\.isClawback).reduce(0.0) { $0 + abs($1.totalEarned) }
        return EarningsSummary(
            totalDeliveries: rows.count,
            totalDeliveryFees: rows.reduce(0) { $0 + $1.deliveryFee },
            totalTips: rows.reduce(0) { $0 + $1.tipAmount },
            totalEarned: rows.reduce(0) { $0 + $1.totalEarned },
            totalClawbacks: clawbacks
        )
    }
}
