import Combine
import Foundation
import RavonCore

@MainActor
@Observable
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var inputText = ""
    var isLoading = false
    var errorMessage: String?

    let orderId: UUID
    private var cancellable: AnyCancellable?

    var currentUserId: UUID? { AuthService.shared.userId }

    init(orderId: UUID) {
        self.orderId = orderId
    }

    func start() async {
        await loadMessages()
        await subscribeToRealtime()
        await markAsRead()
    }

    func stop() async {
        cancellable?.cancel()
        cancellable = nil
        await RealtimeService.shared.unsubscribeFromChat()
    }

    func loadMessages() async {
        isLoading = messages.isEmpty
        do {
            messages = try await SupabaseService.shared.fetchMessages(orderId: orderId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""

        do {
            let sent = try await SupabaseService.shared.sendMessage(orderId: orderId, body: text)
            if !messages.contains(where: { $0.id == sent.id }) {
                messages.append(sent)
            }
        } catch {
            errorMessage = error.localizedDescription
            inputText = text
        }
    }

    func markAsRead() async {
        try? await SupabaseService.shared.markMessagesAsRead(orderId: orderId)
    }

    private func subscribeToRealtime() async {
        try? await RealtimeService.shared.subscribeToChat(orderId: orderId)

        cancellable = RealtimeService.shared.$lastChatMessage
            .compactMap { $0?.message }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                guard let self else { return }
                if message.orderId == self.orderId,
                   !self.messages.contains(where: { $0.id == message.id }) {
                    self.messages.append(message)
                    Task { await self.markAsRead() }
                }
            }
    }
}
