import SwiftUI
import UIKit

/// Full-screen launch splash for important messages and optional force-update.
struct LaunchMessageView: View {
    let config: AppLaunchConfig
    var isForceUpdate: Bool
    var onContinue: (() -> Void)?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("CoKeep")
                            .font(Theme.brandFont(size: 28))
                            .foregroundStyle(Theme.ink)
                            .padding(.bottom, 4)

                        if !config.title.isEmpty {
                            Text(config.title)
                                .font(.system(.title2, design: .rounded).weight(.semibold))
                                .foregroundStyle(Theme.ink)
                        }

                        MarkdownBody(markdown: config.bodyMarkdown)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 48)
                    .padding(.bottom, 24)
                }

                VStack(spacing: 12) {
                    if isForceUpdate {
                        Button {
                            openUpdateURL()
                        } label: {
                            Text(L10n.string("launch.update"))
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Text(L10n.string("launch.updateHint"))
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                    } else {
                        Button {
                            onContinue?()
                        } label: {
                            Text(L10n.string("launch.continue"))
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
                .padding(.top, 8)
            }
        }
        .interactiveDismissDisabled(true)
    }

    private func openUpdateURL() {
        let raw = config.updateUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = URL(string: raw), !raw.isEmpty else { return }
        UIApplication.shared.open(url)
    }
}

/// Renders Markdown via `AttributedString` (links, bold, lists).
private struct MarkdownBody: View {
    let markdown: String

    var body: some View {
        Text(attributed)
            .font(.system(.body, design: .rounded))
            .foregroundStyle(Theme.ink)
            .tint(Theme.accent)
            .textSelection(.enabled)
    }

    private var attributed: AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        if let parsed = try? AttributedString(markdown: markdown, options: options) {
            return parsed
        }
        return AttributedString(markdown)
    }
}
