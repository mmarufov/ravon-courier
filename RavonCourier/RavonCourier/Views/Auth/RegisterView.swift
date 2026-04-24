import SwiftUI
import RavonCore

struct RegisterView: View {
    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showSuccess = false
    @Bindable var authService: CourierAuth
    @Environment(\.dismiss) private var dismiss

    private var passwordsMatch: Bool {
        password == confirmPassword
    }

    private var formIsValid: Bool {
        !fullName.isEmpty && !email.isEmpty && !password.isEmpty
            && !confirmPassword.isEmpty && passwordsMatch && !authService.isLoading
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Header
            VStack(spacing: 12) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 50))
                    .foregroundStyle(Color.ravonRed)

                Text("Создать аккаунт")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Зарегистрируйтесь как курьер")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Form
            VStack(spacing: 16) {
                TextField("Полное имя", text: $fullName)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.name)

                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)

                SecureField("Пароль", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.newPassword)

                SecureField("Подтвердите пароль", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.newPassword)

                if !confirmPassword.isEmpty && !passwordsMatch {
                    Text("Пароли не совпадают")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal)

            if let error = authService.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            // Sign up button
            Button {
                Task {
                    await authService.signUp(
                        email: email, password: password, fullName: fullName)
                    if authService.didSignUp {
                        showSuccess = true
                    }
                }
            } label: {
                if authService.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                } else {
                    Text("Зарегистрироваться")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.ravonRed)
            .controlSize(.large)
            .disabled(!formIsValid)
            .padding(.horizontal)

            Spacer()
            Spacer()
        }
        .navigationBarBackButtonHidden()
        .alert("Регистрация", isPresented: $showSuccess) {
            Button("OK") {
                authService.didSignUp = false
                dismiss()
            }
        } message: {
            Text("Письмо с подтверждением отправлено на вашу почту")
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    authService.errorMessage = nil
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Назад")
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        RegisterView(authService: .shared)
    }
}
