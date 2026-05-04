import SwiftUI
import RavonCore

// MARK: - Delay reason sheet (banner explanation)

struct DelayReasonSheet: View {
    var onSelect: (CourierDelayReason) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Что происходит?")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.top, 8)

            Text("Выберите причину — клиент увидит её в чате.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(CourierDelayReason.allCases, id: \.self) { reason in
                    Button {
                        onSelect(reason)
                        dismiss()
                    } label: {
                        HStack {
                            Text(reason.localizedDisplayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationDetents([.medium])
    }
}

// MARK: - Courier cancel / report-problem sheet

/// Used both for pre-pickup self-cancel and post-pickup "report problem"
/// — the chip list is the same; the action that fires on tap differs.
struct CourierCancelReasonSheet: View {
    enum Mode { case cancel, reportProblem }

    let mode: Mode
    var onSelect: (CancellationReason) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode == .cancel ? "Отменить заказ?" : "Сообщить о проблеме")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.top, 8)

            Text(mode == .cancel
                 ? "Заказ вернётся в общий пул либо будет закрыт. Выберите причину."
                 : "Доставка продолжается. Поддержка и клиент увидят сообщение.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(Array(CancellationReason.courierAllowed), id: \.self) { reason in
                    Button {
                        onSelect(reason)
                        dismiss()
                    } label: {
                        HStack {
                            Text(reason.localizedDisplayName)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Restaurant-delay sheet

struct RestaurantDelaySheet: View {
    let cumulativeMinutes: Int
    var onSelect: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    private let options = [5, 10, 15]
    private let cap = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ресторан задерживает")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.top, 8)

            Text("Текущая задержка: \(cumulativeMinutes) мин. Максимум 30 мин — после этого заказ отменяется автоматически (50% оплаты).")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ForEach(options, id: \.self) { minutes in
                    let disabled = (cumulativeMinutes + minutes) > cap
                    Button {
                        onSelect(minutes)
                        dismiss()
                    } label: {
                        Text("+\(minutes) мин")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(disabled ? Color(.systemGray5) : Color.ravonRed.opacity(0.12))
                            .foregroundStyle(disabled ? .secondary : Color.ravonRed)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(disabled)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationDetents([.height(220)])
    }
}
