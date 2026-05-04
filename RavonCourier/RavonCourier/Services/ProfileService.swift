import Foundation
import RavonCore

@MainActor
@Observable
final class ProfileService {
    static let shared = ProfileService()

    var profile: Profile?
    var isLoading = false

    private init() {}

    func fetchProfile() async {
        isLoading = true
        defer { isLoading = false }
        profile = try? await SupabaseService.shared.fetchProfile()
    }

    var isSuspended: Bool { profile?.isSuspended ?? false }
    var suspendedUntil: Date? { profile?.isSuspendedUntil }
}
