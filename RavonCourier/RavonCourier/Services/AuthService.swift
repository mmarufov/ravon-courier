import Foundation
import RavonCore

@MainActor
@Observable
final class CourierAuth {
    static let shared = CourierAuth()

    var isLoading = false
    var errorMessage: String?

    private var auth: AuthService { .shared }

    var isAuthenticated: Bool { auth.isSignedIn }
    var currentUserId: UUID? { auth.userId }
    var isLoaded: Bool { auth.isLoaded }

    private init() {}

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            try await auth.signIn(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    var didSignUp = false

    func signUp(email: String, password: String, fullName: String) async {
        isLoading = true
        errorMessage = nil
        didSignUp = false
        do {
            try await auth.signUp(email: email, password: password, fullName: fullName, role: .courier)
            didSignUp = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func signOut() async {
        do {
            try await auth.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
