import SwiftUI
import RavonCore

struct SuspensionBlocker: View {
    let until: Date?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)

            VStack(spacing: 12) {
                Text("Аккаунт временно приостановлен")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if let until {
                    Text("До \(formatted(until))")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                Text("Вы получили 3 отметки о неответе за 14 дней. Свяжитесь с поддержкой.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}

#Preview {
    SuspensionBlocker(until: Date().addingTimeInterval(3600 * 48))
}
