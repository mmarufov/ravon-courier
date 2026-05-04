import SwiftUI
import RavonCore

struct EarningsView: View {
    private var earningsService = EarningsService.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Период", selection: Binding(
                        get: { earningsService.selectedPeriod },
                        set: { earningsService.setPeriod($0) }
                    )) {
                        ForEach(EarningsPeriod.allCases, id: \.self) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    summaryCards
                }

                Section("Последние доставки") {
                    if earningsService.earnings.isEmpty {
                        Text("Нет доставок за этот период")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(earningsService.earnings) { earning in
                            earningRow(earning)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Доходы")
            .refreshable {
                await earningsService.fetchEarnings()
            }
            .task {
                await earningsService.fetchEarnings()
            }
        }
    }

    private var summaryCards: some View {
        let summary = earningsService.summary

        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                summaryCard(
                    title: "Заработок",
                    value: String(format: "%.0f сом.", summary.totalEarned),
                    icon: "banknote.fill",
                    color: .green
                )

                summaryCard(
                    title: "Доставки",
                    value: "\(summary.totalDeliveries)",
                    icon: "bag.fill",
                    color: .ravonRed
                )
            }

            if summary.totalClawbacks > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                    Text("Удержания: \(summary.totalClawbacks, specifier: "%.0f") сом.")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func earningRow(_ earning: CourierEarning) -> some View {
        let isClawback = earning.isClawback
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(earningTitle(earning))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(isClawback ? .red : .primary)
                if earning.tipAmount > 0 {
                    Text("Чаевые: \(earning.tipAmount, specifier: "%.0f") сом.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(amountString(earning))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(isClawback ? .red : .green)
                Text(earning.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func earningTitle(_ earning: CourierEarning) -> String {
        let pct = earning.tierPct
        let display = earning.earningType.localizedDisplayName
        // For clawback the tier_pct is negative on the server — render as "(100%)" magnitude.
        let pctLabel = pct == 0 ? "" : " (\(abs(pct))%)"
        return display + pctLabel
    }

    private func amountString(_ earning: CourierEarning) -> String {
        let prefix = earning.totalEarned >= 0 ? "+" : ""
        return "\(prefix)\(earning.totalEarned.formatted(.number.precision(.fractionLength(0)))) сом."
    }
}

#Preview {
    EarningsView()
}
