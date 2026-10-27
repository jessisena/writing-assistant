import Foundation

/// Heading level (1–6) of a line, set on every character of a heading line.
public enum HeadingLevelAttribute: AttributedStringKey {
    public typealias Value = Int
    public static let name = "WritingAssistant.headingLevel"
}

extension AttributeScopes {
    /// Attributes the app adds on top of Foundation's for rich text.
    public struct RichTextAttributes: AttributeScope {
        public let headingLevel: HeadingLevelAttribute
        public let foundation: FoundationAttributes
    }

    /// The rich text attribute scope, for `AttributedString(_:including:)` and friends.
    public var richText: RichTextAttributes.Type { RichTextAttributes.self }
}

extension AttributeDynamicLookup {
    /// Gives `run.headingLevel` and `container.headingLevel` key-path access.
    public subscript<T: AttributedStringKey>(
        dynamicMember keyPath: KeyPath<AttributeScopes.RichTextAttributes, T>
    ) -> T {
        self[T.self]
    }
}

/// Converts between the Markdown subset the app exchanges with Claude, `AttributedString`,
/// HTML for the clipboard, and plain text.
///
/// Supported: bold, italic, strikethrough and inline code (`inlinePresentationIntent`), links
/// (`link`), bullet lines (a literal `"• "` prefix in the attributed string) and headings
/// (`headingLevel`). Everything else is kept as literal text.
public enum RichText {
    static let bulletPrefix = "• "
    static let supportedIntents: InlinePresentationIntent = [
        .stronglyEmphasized, .emphasized, .strikethrough, .code,
    ]

    /// Parses Markdown line by line into an attributed string.
    ///
    /// `- ` and `* ` lines become `"• "` bullets and `#`–`######` lines become headings. Never
    /// fails: a line the parser rejects is kept as plain text, since model output is untrusted.
    ///
    /// - Parameter markdown: Markdown text, with `\n` or `\r\n` line endings.
    /// - Returns: The formatted text, with lines separated by `\n`.
    public static func attributedString(fromMarkdown markdown: String) -> AttributedString {
        var result = AttributedString()
        let lines = markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        for (index, line) in lines.enumerated() {
            if index > 0 {
                result += AttributedString("\n")
            }
            result += parseLine(line)
        }
        return result
    }

    /// Writes an attributed string as Markdown, escaping literal Markdown characters.
    ///
    /// - Parameter text: Text using the supported attributes.
    /// - Returns: Markdown that `attributedString(fromMarkdown:)` parses back to the same text.
    public static func markdown(from text: AttributedString) -> String {
        lines(of: text).map(markdownLine).joined(separator: "\n")
    }

    /// Writes an attributed string as an HTML fragment for the clipboard.
    ///
    /// All text and link targets are escaped. Consecutive bullet lines become one `<ul>`,
    /// headings become bold paragraphs, and other line breaks become `<br>`. Links with a
    /// scheme other than http, https or mailto are written as plain text.
    ///
    /// - Parameter text: Text using the supported attributes.
    /// - Returns: UTF-8 HTML, starting with a charset declaration so emoji survive pasting.
    public static func html(from text: AttributedString) -> String {
        HTMLWriter.document(lines: lines(of: text).map(RichTextLine.init))
    }

    /// Returns the text without formatting; bullets keep their `"• "` prefix.
    ///
    /// - Parameter text: Text using the supported attributes.
    /// - Returns: The characters of `text`.
    public static func plainText(from text: AttributedString) -> String {
        String(text.characters)
    }

    static func lines(of text: AttributedString) -> [AttributedSubstring] {
        text.characters
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { text[$0.startIndex..<$0.endIndex] }
    }
}

// MARK: - Parsing

extension RichText {
    static func parseLine(_ line: Substring) -> AttributedString {
        if let (level, content) = headingParts(of: line) {
            var heading = parseInline(content)
            heading.headingLevel = level
            return heading
        }
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return AttributedString(bulletPrefix) + parseInline(line.dropFirst(2))
        }
        return parseInline(line)
    }

    static func headingParts(of line: Substring) -> (Int, Substring)? {
        let level = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level) else {
            return nil
        }
        let rest = line.dropFirst(level)
        guard rest.first == " " else {
            return nil
        }
        return (level, rest.dropFirst())
    }

    static func parseInline(_ markdown: Substring) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard var parsed = try? AttributedString(markdown: String(markdown), options: options)
        else {
            return AttributedString(String(markdown))
        }
        for run in parsed.runs {
            let kept = run.inlinePresentationIntent?.intersection(supportedIntents)
            parsed[run.range].inlinePresentationIntent = kept?.isEmpty == false ? kept : nil
        }
        return parsed
    }
}

// MARK: - Markdown output

extension RichText {
    enum Marker: Equatable {
        case link(URL)
        case bold
        case italic
        case strike

        var open: String {
            switch self {
            case .link: "["
            case .bold: "**"
            case .italic: "*"
            case .strike: "~~"
            }
        }

        var close: String {
            switch self {
            case .link(let url): "](\(linkDestination(url)))"
            case .bold: "**"
            case .italic: "*"
            case .strike: "~~"
            }
        }
    }

    /// Markers for a run, outermost first. Links go innermost: Foundation's parser drops
    /// emphasis written inside link text, but keeps a link written inside emphasis.
    static func markers(of run: AttributedString.Runs.Run) -> [Marker] {
        let intent = run.inlinePresentationIntent ?? []
        var result: [Marker] = []
        if intent.contains(.stronglyEmphasized) {
            result.append(.bold)
        }
        if intent.contains(.emphasized) {
            result.append(.italic)
        }
        if intent.contains(.strikethrough) {
            result.append(.strike)
        }
        if let url = run.link {
            result.append(.link(url))
        }
        return result
    }

    static func markdownLine(_ line: AttributedSubstring) -> String {
        let line = RichTextLine(line)
        var writer = MarkdownLineWriter()
        for run in line.content.runs {
            let text = String(line.content[run.range].characters)
            let isCode = run.inlinePresentationIntent?.contains(.code) == true
            writer.write(text, markers: markers(of: run), isCode: isCode)
        }
        let inline = escapeLineStart(writer.finish())
        switch line.kind {
        case .heading(let level): return String(repeating: "#", count: level) + " " + inline
        case .bullet: return "- " + inline
        case .plain: return inline
        }
    }

    static func escapeMarkdown(_ text: String) -> String {
        var result = ""
        for character in text {
            if "\\*_~`[]<&".contains(character) {
                result.append("\\")
            }
            result.append(character)
        }
        return result
    }

    static func escapeLineStart(_ inline: String) -> String {
        if inline.hasPrefix("#") || inline.hasPrefix("- ") {
            return "\\" + inline
        }
        return inline
    }

    static func codeSpan(_ text: String) -> String {
        var longestRun = 0
        var currentRun = 0
        for character in text {
            currentRun = character == "`" ? currentRun + 1 : 0
            longestRun = max(longestRun, currentRun)
        }
        let fence = String(repeating: "`", count: longestRun + 1)
        let needsPadding =
            text.hasPrefix("`") || text.hasSuffix("`")
            || (text.hasPrefix(" ") && text.hasSuffix(" "))
        let padding = needsPadding ? " " : ""
        return fence + padding + text + padding + fence
    }

    static func linkDestination(_ url: URL) -> String {
        let destination = url.absoluteString
        if destination.contains(where: { "() ".contains($0) }) {
            return "<\(destination)>"
        }
        return destination
    }
}

/// Writes the inline Markdown of one line, keeping markers open across runs that share them.
///
/// Whitespace at the edge of a styled run is written outside the markers, because CommonMark
/// doesn't treat `**` next to inner whitespace as emphasis.
struct MarkdownLineWriter {
    private var output = ""
    private var open: [RichText.Marker] = []
    private var pendingSpace = ""

    mutating func write(_ text: String, markers: [RichText.Marker], isCode: Bool) {
        if !isCode && text.allSatisfy(\.isWhitespace) {
            pendingSpace += text
            return
        }
        let parts = isCode ? ("", Substring(text), "") : Self.splitWhitespace(text)
        let kept = open.prefix(while: { markers.contains($0) }).count
        closeMarkers(downTo: kept)
        output += pendingSpace + parts.0
        for marker in markers where !open.contains(marker) {
            output += marker.open
            open.append(marker)
        }
        let core = String(parts.1)
        output += isCode ? RichText.codeSpan(core) : RichText.escapeMarkdown(core)
        pendingSpace = String(parts.2)
    }

    mutating func finish() -> String {
        closeMarkers(downTo: 0)
        output += pendingSpace
        pendingSpace = ""
        return output
    }

    private mutating func closeMarkers(downTo count: Int) {
        while open.count > count {
            output += open.removeLast().close
        }
    }

    private static func splitWhitespace(_ text: String) -> (Substring, Substring, Substring) {
        let start = text.firstIndex(where: { !$0.isWhitespace }) ?? text.endIndex
        let end = text.lastIndex(where: { !$0.isWhitespace }).map(text.index(after:)) ?? start
        return (text[..<start], text[start..<end], text[end...])
    }
}

// MARK: - Line structure

/// One line of rich text, split into its block kind and inline content.
struct RichTextLine {
    enum Kind: Equatable {
        case plain
        case bullet
        case heading(Int)
    }

    let kind: Kind
    let content: AttributedSubstring

    init(_ line: AttributedSubstring) {
        if line.characters.starts(with: RichText.bulletPrefix) {
            let start = line.characters.index(
                line.startIndex, offsetBy: RichText.bulletPrefix.count)
            kind = .bullet
            content = line[start..<line.endIndex]
        } else if let level = line.runs.first?.headingLevel {
            kind = .heading(level)
            content = line
        } else {
            kind = .plain
            content = line
        }
    }
}

// MARK: - HTML output

enum HTMLWriter {
    static let prefix = "<meta charset=\"utf-8\">"
    static let safeSchemes: Set<String> = ["http", "https", "mailto"]

    static func document(lines: [RichTextLine]) -> String {
        var output = prefix
        for (index, line) in lines.enumerated() {
            let previous = index > 0 ? lines[index - 1].kind : nil
            let next = index + 1 < lines.count ? lines[index + 1].kind : nil
            output += block(line, previous: previous, next: next)
        }
        return output
    }

    static func block(_ line: RichTextLine, previous: RichTextLine.Kind?, next: RichTextLine.Kind?)
        -> String
    {
        let inline = inlineHTML(line.content)
        switch line.kind {
        case .bullet:
            let open = previous == .bullet ? "" : "<ul>"
            let close = next == .bullet ? "" : "</ul>"
            return open + "<li>" + inline + "</li>" + close
        case .heading:
            return "<p><b>" + inline + "</b></p>"
        case .plain:
            return next == .plain ? inline + "<br>" : inline
        }
    }

    static func inlineHTML(_ content: AttributedSubstring) -> String {
        var output = ""
        for run in content.runs {
            var html = escape(String(content[run.range].characters))
            let intent = run.inlinePresentationIntent ?? []
            let tags: [(InlinePresentationIntent, String)] = [
                (.code, "code"), (.strikethrough, "s"), (.emphasized, "i"),
                (.stronglyEmphasized, "b"),
            ]
            for (flag, tag) in tags where intent.contains(flag) {
                html = "<\(tag)>\(html)</\(tag)>"
            }
            if let url = run.link, safeSchemes.contains(url.scheme?.lowercased() ?? "") {
                html = "<a href=\"\(escape(url.absoluteString))\">\(html)</a>"
            }
            output += html
        }
        return output
    }

    static func escape(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
        return result
    }
}
