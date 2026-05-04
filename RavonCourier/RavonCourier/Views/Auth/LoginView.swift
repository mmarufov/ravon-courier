import SwiftUI
import RavonCore

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @Bindable var authService: CourierAuth

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Logo
                VStack(spacing: 12) {
                    Image(systemName: "bicycle")
                        .font(.system(size: 60))
                        .foregroundStyle(Color.ravonRed)

                    Text("Ravon Courier")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Доставка еды в Душанбе")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Form
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)

                    SecureField("Пароль", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                }
                .padding(.horizontal)

                if let error = authService.errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                // Sign in button
                Button {
                    Task {
                        await authService.signIn(email: email, password: password)
                    }
                } label: {
                    if authService.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 20)
                    } else {
                        Text("Войти")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.ravonRed)
                .controlSize(.large)
                .disabled(email.isEmpty || password.isEmpty || authService.isLoading)
                .padding(.horizontal)

                // Register link
                NavigationLink {
                    RegisterView(authService: authService)
                } label: {
                    HStack(spacing: 4) {
                        Text("Нет аккаунта?")
                            .foregroundStyle(.secondary)
                        Text("Зарегистрироваться")
                            .foregroundStyle(Color.ravonRed)
                            .fontWeight(.medium)
                    }
                }
                .font(.subheadline)

                Spacer()
                Spacer()
            }
        }
    }
}

#Preview {
    LoginView(authService: .shared)
}
