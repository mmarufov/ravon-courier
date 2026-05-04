import SwiftUI
import RavonCore

struct OrderRowView: View {
    let order: Order
    @State private var showDetail = false

    var body: some View {
        Button {
            showDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Заказ #\(order.shortId)")
                        .font(.headline)

                    Spacer()

                    Text("\(order.deliveryFee, specifier: "%.0f") сом.")
                        .font(.headline)
                        .foregroundStyle(Color.ravonRed)
                }

                HStack(spacing: 4) {
                    Image(systemName: "building.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(order.restaurant?.name ?? "Ресторан")
                        .font(.subheadline)
                }

                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(order.deliveryAddressSnapshot?.shortAddress ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("\(order.itemCount) позиц. · \(order.total, specifier: "%.0f") сом.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(order.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            OrderDetailSheet(order: order)
        }
    }
}

// MARK: - Order Detail Sheet
struct OrderDetailSheet: View {
    let order: Order
    @Environment(\.dismiss) private var dismiss
    @State private var isClaiming = false
    @State private var claimError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Ресторан") {
                    HStack {
                        Image(systemName: "building.2.fill")
                            .foregroundStyle(Color.ravonRed)
                        VStack(alignment: .leading) {
                            Text(order.restaurant?.name ?? "Ресторан")
                                .font(.headline)
                            Text(order.restaurant?.address ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Позиции") {
                    ForEach(order.orderItems ?? []) { item in
                        HStack {
                            Text("\(item.quantity)x")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(width: 30, alignment: .leading)
                            Text(item.itemName)
                                .font(.subheadline)
                            Spacer()
                            Text("\(item.totalPrice, specifier: "%.0f") сом.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Доставка") {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text("Адрес клиента")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(order.deliveryAddressSnapshot?.shortAddress ?? "")
                                .font(.subheadline)
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Сумма заказа")
                        Spacer()
                        Text("\(order.total, specifier: "%.0f") сом.")
                    }
                    HStack {
                        Text("Ваш заработок")
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(order.deliveryFee, specifier: "%.0f") сом.")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.ravonRed)
                    }
                }
            }
            .navigationTitle("Заказ #\(order.shortId)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
            }
            .overlay(alignment: .top) {
                if let error = claimError {
                    toastView(message: error)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    claimOrder()
                } label: {
                    if isClaiming {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Принять заказ")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.ravonRed)
                .controlSize(.large)
                .disabled(isClaiming)
                .padding()
            }
        }
        .presentationDetents([.large])
    }

    private func claimOrder() {
        isClaiming = true
        claimError = nil

        Task {
            do {
                try await OrderService.shared.claimOrder(order)
                dismiss()
            } catch {
                let message: String = {
                    if let svc = error as? ServiceError {
                        if case .orderAlreadyClaimed = svc { return "Заказ уже занят" }
                        return svc.errorDescription ?? error.localizedDescription
                    }
                    if let mapped = ServiceError.from(serverError: error),
                       case .orderAlreadyClaimed = mapped {
                        return "Заказ уже занят"
                    }
                    return error.localizedDescription
                }()
                withAnimation { claimError = message }
                try? await Task.sleep(for: .seconds(2))
                withAnimation { claimError = nil }
            }
            isClaiming = false
        }
    }

    private func toastView(message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.red, in: Capsule())
            .padding(.top, 8)
    }
}
