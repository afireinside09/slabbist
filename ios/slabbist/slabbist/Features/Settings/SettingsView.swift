import SwiftUI

struct SettingsView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        SlabbedRoot {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    header

                    accountSection
                    aboutSection

                    Spacer(minLength: Spacing.xxxl)
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.xxl)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            KickerLabel("More")
            Text("Settings").slabTitle()
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            KickerLabel("Account")
            SlabCard {
                Button {
                    Task { await session.signOut() }
                } label: {
                    settingsRow(
                        icon: "rectangle.portrait.and.arrow.right",
                        title: "Sign out",
                        detail: nil,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            KickerLabel("About")
            SlabCard {
                VStack(spacing: 0) {
                    settingsRow(
                        icon: "app.badge",
                        title: "Version",
                        detail: Self.versionString,
                        showsChevron: false
                    )
                    SlabCardDivider()
                    settingsRow(
                        icon: "hammer",
                        title: "Build",
                        detail: Self.buildString,
                        showsChevron: false
                    )
                }
            }
        }
    }

    // MARK: - Row

    private func settingsRow(
        icon: String,
        title: String,
        detail: String?,
        showsChevron: Bool
    ) -> some View {
        HStack(spacing: Spacing.m) {
            iconTile(icon)
            Text(title).slabRowTitle()
            Spacer(minLength: Spacing.s)
            if let detail {
                Text(detail)
                    .font(SlabFont.mono(size: 13, weight: .medium))
                    .foregroundStyle(AppColor.muted)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppColor.dim)
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.md)
        .contentShape(Rectangle())
    }

    private func iconTile(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(SlabFont.sans(size: 14, weight: .regular))
            .foregroundStyle(AppColor.gold)
            .frame(width: 28, height: 28)
            .background(AppColor.elev2)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    .stroke(AppColor.hairline, lineWidth: 1)
            )
    }

    // MARK: - Bundle helpers

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
