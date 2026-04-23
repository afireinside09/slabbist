import SwiftUI

struct SettingsView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    header

                    SlabCard {
                        Button {
                            Task { await session.signOut() }
                        } label: {
                            HStack {
                                Text("Sign out").slabRowTitle()
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(AppColor.dim)
                            }
                            .padding(.horizontal, Spacing.l)
                            .padding(.vertical, Spacing.md)
                        }
                        .buttonStyle(.plain)
                    }

                    SlabCard {
                        VStack(spacing: 0) {
                            infoRow(label: "Version", value: Self.versionString)
                            SlabCardDivider()
                            infoRow(label: "Build", value: Self.buildString)
                        }
                    }

                    Spacer(minLength: Spacing.xxxl)
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.top, Spacing.l)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("More")
            Text("Settings").slabTitle()
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label).slabRowTitle()
            Spacer()
            Text(value).slabMetric().foregroundStyle(AppColor.muted)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.md)
    }

    private static var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private static var buildString: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}

#Preview {
    SettingsView()
        .environment(SessionStore())
}
