import SwiftUI
import UIKit

/// Full-screen launch splash for important messages and optional force-update.
struct LaunchMessageView: View {
    let message: AppLaunchMessage
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

                        if !message.title.isEmpty {
                            Text(message.title)
                                .font(.system(.title2, design: .rounded).weight(.semibold))
                                .foregroundStyle(Theme.ink)
                        }

                        MarkdownBody(markdown: message.bodyMarkdown)
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
        let raw = message.updateUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = URL(string: raw), !raw.isEmpty else { return }
        UIApplication.shared.open(url)
    }
}

/// Renders Markdown with paragraph breaks, hard line breaks, and lists.
/// Foundation’s parser collapses single newlines (CommonMark soft breaks) and
/// is unreliable for lightly indented list markers from a textarea.
private struct MarkdownBody: View {
    let markdown: String

    var body: some View {
        Text(Self.attributed(from: markdown))
            .font(.system(.body, design: .rounded))
            .foregroundStyle(Theme.ink)
            .tint(Theme.accent)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
    }

    private static let listItemPattern = #"^\s*[-*+]\s+(.+)$"#

    static func attributed(from raw: String) -> AttributedString {
        let text = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return AttributedString() }

        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace

        var result = AttributedString()
        var pendingBlank = false

        for group in lineGroups(in: text) {
            if pendingBlank {
                result.append(AttributedString("\n\n"))
            }
            pendingBlank = true

            switch group {
            case .paragraph(let lines):
                for (index, line) in lines.enumerated() {
                    if index > 0 { result.append(AttributedString("\n")) }
                    result.append(inlineAttributed(line, options: options))
                }
            case .list(let items):
                for (index, item) in items.enumerated() {
                    if index > 0 { result.append(AttributedString("\n")) }
                    var row = AttributedString("• ")
                    row.append(inlineAttributed(item, options: options))
                    result.append(row)
                }
            }
        }

        return result
    }

    private enum LineGroup {
        case paragraph([String])
        case list([String])
    }

    private static func lineGroups(in text: String) -> [LineGroup] {
        let lines = text.components(separatedBy: "\n")
        var groups: [LineGroup] = []
        var paragraph: [String] = []
        var listItems: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            groups.append(.paragraph(paragraph))
            paragraph = []
        }

        func flushList() {
            guard !listItems.isEmpty else { return }
            groups.append(.list(listItems))
            listItems = []
        }

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushParagraph()
                flushList()
                continue
            }

            if let item = listItemText(line) {
                flushParagraph()
                listItems.append(item)
            } else {
                flushList()
                paragraph.append(line.trimmingCharacters(in: .whitespaces))
            }
        }

        flushParagraph()
        flushList()
        return groups
    }

    private static func listItemText(_ line: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: listItemPattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              match.numberOfRanges >= 2,
              let textRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[textRange]).trimmingCharacters(in: .whitespaces)
    }

    private static func inlineAttributed(
        _ text: String,
        options: AttributedString.MarkdownParsingOptions
    ) -> AttributedString {
        if let parsed = try? AttributedString(markdown: text, options: options) {
            return parsed
        }
        return AttributedString(text)
    }
}
