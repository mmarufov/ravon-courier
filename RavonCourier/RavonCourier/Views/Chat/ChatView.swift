import SwiftUI
import RavonCore

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool

    init(orderId: UUID) {
        _viewModel = State(wrappedValue: ChatViewModel(orderId: orderId))
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
            inputBar
        }
        .navigationTitle("Чат с клиентом")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.start()
        }
        .onDisappear {
            Task { await viewModel.stop() }
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else if viewModel.messages.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.messages) { message in
                            ChatBubble(
                                message: message,
                                isMine: message.isSentBy(viewModel.currentUserId ?? UUID())
                            )
                            .id(message.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Нет сообщений")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Напишите клиенту, если нужно уточнить детали доставки")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Сообщение...", text: $viewModel.inputText, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .focused($isInputFocused)

            Button {
                Task { await viewModel.sendMessage() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? Color.ravonRed : Color(.systemGray4))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let message: ChatMessage
    let isMine: Bool

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 60) }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                Text(message.body)
                    .font(.body)
                    .foregroundStyle(isMine ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isMine ? Color.ravonRed : Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                Text(timeString(message.createdAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            if !isMine { Spacer(minLength: 60) }
        }
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        ChatView(orderId: UUID())
    }
}
