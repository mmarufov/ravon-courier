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

        return HStack(spacing: 12) {
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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Доставка")
                    .font(.subheadline)
                    .fontWeight(.medium)
                if earning.tipAmount > 0 {
                    Text("Чаевые: \(earning.tipAmount, specifier: "%.0f") сом.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("+\(earning.totalEarned, specifier: "%.0f") сом.")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
                Text(earning.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    EarningsView()
}
