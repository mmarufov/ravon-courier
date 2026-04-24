import SwiftUI
import RavonCore

struct AvailableOrdersView: View {
    private var orderService = OrderService.shared

    var body: some View {
        Group {
            if orderService.isLoading {
                VStack {
                    Spacer()
                    ProgressView("Загрузка заказов...")
                    Spacer()
                }
            } else if orderService.availableOrders.isEmpty {
                VStack(spacing: 16) {
                    Spacer()

                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    Text("Нет доступных заказов")
                        .font(.title3)
                        .fontWeight(.medium)

                    Text("Новые заказы появятся здесь")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button("Обновить") {
                        Task {
                            await orderService.fetchAvailableOrders()
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.ravonRed)

                    Spacer()
                }
            } else {
                List {
                    Section {
                        ForEach(orderService.availableOrders) { order in
                            OrderRowView(order: order)
                        }
                    } header: {
                        Text("Доступные заказы (\(orderService.availableOrders.count))")
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await orderService.fetchAvailableOrders()
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AvailableOrdersView()
    }
}
