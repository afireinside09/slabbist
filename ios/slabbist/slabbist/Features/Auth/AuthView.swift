import SwiftUI

struct AuthView: View {
    @State private var viewModel = AuthViewModel()

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxxl) {
                    brand

                    VStack(alignment: .leading, spacing: Spacing.m) {
                        KickerLabel(viewModel.mode == .signIn ? "Welcome back" : "Create account")
                        Text("Slabbist").slabTitle()
                        Text(subtitle)
                            .font(SlabFont.sans(size: 15))
                            .foregroundStyle(AppColor.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SlabCard {
                        VStack(spacing: 0) {
                            field(icon: "envelope") {
                                TextField("", text: $viewModel.email, prompt:
                                    Text("Email").foregroundStyle(AppColor.dim))
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                    .foregroundStyle(AppColor.text)
                                    .tint(AppColor.gold)
                            }
                            SlabCardDivider()
                            field(icon: "lock") {
                                SecureField("", text: $viewModel.password, prompt:
                                    Text("Password").foregroundStyle(AppColor.dim))
                                    .textContentType(viewModel.mode == .signIn ? .password : .newPassword)
                                    .foregroundStyle(AppColor.text)
                                    .tint(AppColor.gold)
                            }
                            if viewModel.mode == .signUp {
                                SlabCardDivider()
                                field(icon: "storefront") {
                                    TextField("", text: $viewModel.storeName, prompt:
                                        Text("Store name (optional)").foregroundStyle(AppColor.dim))
                                        .foregroundStyle(AppColor.text)
                                        .tint(AppColor.gold)
                                }
                            }
                        }
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(SlabFont.sans(size: 13))
                            .foregroundStyle(AppColor.negative)
                    }

                    PrimaryGoldButton(
                        title: viewModel.mode == .signIn ? "Sign in" : "Create account",
                        isLoading: viewModel.isSubmitting,
                        isEnabled: !viewModel.email.isEmpty && !viewModel.password.isEmpty
                    ) {
                        Task { await viewModel.submit() }
                    }

                    Button {
                        viewModel.mode = (viewModel.mode == .signIn) ? .signUp : .signIn
                    } label: {
                        Text(viewModel.mode == .signIn
                             ? "Don't have an account? Create one"
                             : "Already have an account? Sign in")
                            .font(SlabFont.sans(size: 14))
                            .foregroundStyle(AppColor.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.top, Spacing.xxxl)
                .padding(.bottom, Spacing.xxl)
            }
        }
        .ambientGoldBlob(.topTrailing)
    }

    private var subtitle: String {
        viewModel.mode == .signIn
        ? "Sign in to your store to continue scanning."
        : "Create your store to start bulk-scanning slabs."
    }

    private var brand: some View {
        HStack(spacing: Spacing.s) {
            SlabbistLogo(size: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text("SLABBIST")
                .font(SlabFont.sans(size: 14, weight: .medium))
                .tracking(1.6)
                .foregroundStyle(AppColor.text)
        }
    }

    private func field<Content: View>(icon: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: icon)
                .foregroundStyle(AppColor.dim)
                .frame(width: 18)
            content()
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.md)
    }
}

#Preview {
    AuthView()
}
