import SwiftUI

struct AuthView: View {
    @State private var viewModel = AuthViewModel()

    var body: some View {
        VStack(spacing: Spacing.l) {
            Text("Slabbist")
                .font(.largeTitle.bold())

            Picker("Mode", selection: $viewModel.mode) {
                Text("Sign In").tag(AuthViewModel.Mode.signIn)
                Text("Sign Up").tag(AuthViewModel.Mode.signUp)
            }
            .pickerStyle(.segmented)

            VStack(spacing: Spacing.m) {
                TextField("Email", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)

                SecureField("Password", text: $viewModel.password)
                    .textContentType(viewModel.mode == .signIn ? .password : .newPassword)

                if viewModel.mode == .signUp {
                    TextField("Store name (optional)", text: $viewModel.storeName)
                }
            }
            .textFieldStyle(.roundedBorder)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(AppColor.danger)
            }

            Button {
                Task { await viewModel.submit() }
            } label: {
                if viewModel.isSubmitting {
                    ProgressView()
                } else {
                    Text(viewModel.mode == .signIn ? "Sign in" : "Create account")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.email.isEmpty || viewModel.password.isEmpty || viewModel.isSubmitting)
        }
        .padding(Spacing.l)
    }
}

#Preview {
    AuthView()
}
