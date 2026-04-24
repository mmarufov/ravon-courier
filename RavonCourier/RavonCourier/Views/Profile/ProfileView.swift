import SwiftUI
import RavonCore
import Auth

struct ProfileView: View {
    @State private var profile: Profile?
    @State private var isLoading = true
    @ObservedObject private var auth = AuthService.shared

    var body: some View {
        NavigationStack {
            Group {
                if let profile {
                    profileContent(profile)
                } else if isLoading {
                    ProgressView("Загрузка профиля...")
                } else {
                    Text("Не удалось загрузить профиль")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Профиль")
        }
        .task {
            do {
                profile = try await SupabaseService.shared.fetchProfile()
            } catch {}
            isLoading = false
        }
    }

    private func profileContent(_ profile: Profile) -> some View {
        List {
            // Avatar + name
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.ravonRed)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.fullName)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text(profile.role.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            // Info
            Section("Информация") {
                if let email = auth.session?.user.email {
                    infoRow(icon: "envelope.fill", title: "Email", value: email)
                }
                if let phone = profile.phone, !phone.isEmpty {
                    infoRow(icon: "phone.fill", title: "Телефон", value: phone)
                }
            }

            // Sign out
            Section {
                Button(role: .destructive) {
                    Task {
                        await CourierAuth.shared.signOut()
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text("Выйти")
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(Color.ravonRed)
                .frame(width: 24)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }
}

#Preview {
    ProfileView()
}
