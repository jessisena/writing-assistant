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
/// (`headingLevel`). Images are kept as their literal `![alt](url)` text, and everything else
/// is kept as literal text too.
public enum RichText {
    static let bulletPrefix = "• "
    /// Link schemes written to the clipboard; other links are kept as their label only.
    static let safeSchemes: Set<String> = ["http", "https", "mailto"]
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
    /// Styling Markdown can't express is dropped (see `InlineMarkdown`), and a leading bullet
    /// prefix is written as an unstyled `- `.
    ///
    /// - Parameter text: Text using the supported attributes.
    /// - Returns: Markdown that `attributedString(fromMarkdown:)` parses back to the same
    ///   characters, with the same styling except what was dropped.
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

    /// Returns the text without formatting; bullets keep their `"• "` prefix. Link targets are
    /// left out, so the diff and history previews show only what the reader sees.
    ///
    /// - Parameter text: Text using the supported attributes.
    /// - Returns: The characters of `text`.
    public static func plainText(from text: AttributedString) -> String {
        String(text.characters)
    }

    /// Returns the plain text for the clipboard: like `plainText(from:)`, but a link keeps its
    /// target as `label (url)`, or only the label when it already is the target (`mailto:` is
    /// ignored for that comparison). Targets with a scheme the HTML leaves out are dropped too.
    ///
    /// - Parameter text: Text using the supported attributes.
    /// - Returns: Text for apps that don't read HTML.
    public static func clipboardText(from text: AttributedString) -> String {
        var result = ""
        for (link, range) in text.runs[\.link] {
            let label = String(text[range].characters)
            result += label
            guard let link, safeSchemes.contains(link.scheme?.lowercased() ?? "") else { continue }
            let target = link.absoluteString
            if label != target && "mailto:" + label != target {
                result += " (\(target))"
            }
        }
        return result
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
        restoreImageSources(in: &parsed)
        return parsed
    }

    /// Replaces each image, which the parser reduces to its alt text, with its `![alt](url)`
    /// source so the URL isn't lost.
    static func restoreImageSources(in text: inout AttributedString) {
        let images = text.runs[AttributeScopes.FoundationAttributes.ImageURLAttribute.self]
        for (url, range) in images.reversed() {
            guard let url else {
                continue
            }
            let alt = String(text[range].characters)
            text.replaceSubrange(range, with: AttributedString("![\(alt)](\(url.absoluteString))"))
        }
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

        var isLink: Bool {
            if case .link = self { true } else { false }
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
        let segments = line.content.runs.map { run in
            InlineSegment(
                text: String(line.content[run.range].characters),
                markers: markers(of: run),
                isCode: run.inlinePresentationIntent?.contains(.code) == true)
        }
        let inline = escapeLineStart(InlineMarkdown.render(segments))
        switch line.kind {
        case .heading(let level): return String(repeating: "#", count: level) + " " + inline
        case .bullet: return "- " + inline
        case .plain: return inline
        }
    }

    /// Escapes by code point, since the parser reads code points: the keycap emoji `*️⃣` starts
    /// with a `*` that would otherwise open emphasis.
    static func escapeMarkdown(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if "\\*_~`[]<&".unicodeScalars.contains(scalar) {
                result.append("\\")
            }
            result.append(scalar)
        }
        return String(result)
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
        let allSpaces = text.allSatisfy { $0 == " " }
        let needsPadding =
            text.hasPrefix("`") || text.hasSuffix("`")
            || (text.hasPrefix(" ") && text.hasSuffix(" ") && !allSpaces)
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

/// One run of a line: its text, its markers outermost first, and whether it is inline code.
struct InlineSegment: Equatable {
    var text: String
    var markers: [RichText.Marker]
    var isCode: Bool

    /// Whether the text is written as a code span; inside a link it is plain link text instead.
    var writesCodeSpan: Bool { isCode && link == nil }

    var isBlank: Bool { !writesCodeSpan && text.allSatisfy(\.isWhitespace) }

    var link: URL? {
        for case .link(let url) in markers {
            return url
        }
        return nil
    }

    /// The intent the written Markdown parses back to.
    var intent: InlinePresentationIntent {
        var intent: InlinePresentationIntent = []
        for marker in markers {
            switch marker {
            case .bold: intent.insert(.stronglyEmphasized)
            case .italic: intent.insert(.emphasized)
            case .strike: intent.insert(.strikethrough)
            case .link: break
            }
        }
        if writesCodeSpan {
            intent.insert(.code)
        }
        return intent
    }
}

/// Writes the inline Markdown of one line so that it parses back to the same text.
///
/// CommonMark only reads `*`, `**` and `~~` as emphasis when they are "flanking": an opening
/// marker must not be followed by whitespace, nor by punctuation unless whitespace or
/// punctuation precedes it, and a closing marker mirrors that. Styling that would break these
/// rules is normalized away, one marker at a time, until every marker flanks:
///
/// - Whitespace at the edge of a styled run is written outside its markers, and a run that is
///   only whitespace takes just the markers its neighbours keep open across it.
/// - Punctuation at the edge of a styled run is written outside the marker that touches a word
///   character across it, so bold `"foo."` before `"bar"` becomes `**foo**.bar`.
/// - When the marker's edge isn't movable text (inline code, a link, or another marker), that
///   marker is dropped from the run.
/// - Inline code inside a link is written as plain link text, since Foundation's parser drops
///   inline styles inside link text.
///
/// Flanking alone doesn't settle how CommonMark pairs markers that could both open and close,
/// such as the `***` in bold `"a"` followed by italic `"b"`. The result is parsed back to check
/// it; when the pairing came out wrong, the line is written again in strict mode, where a
/// marker that could both open and close is normalized away like a non-flanking one.
enum InlineMarkdown {
    static func render(_ segments: [InlineSegment]) -> String {
        let relaxed = render(segments, strict: false)
        if parsesBack(relaxed.markdown, as: relaxed.segments) {
            return relaxed.markdown
        }
        return render(segments, strict: true).markdown
    }

    private static func render(
        _ segments: [InlineSegment], strict: Bool
    ) -> (markdown: String, segments: [InlineSegment]) {
        var segments = segments
        while true {
            segments = coalesced(segments)
            var writer = MarkdownLineWriter()
            for (index, segment) in segments.enumerated() {
                writer.write(segment, index: index)
            }
            writer.finish()
            guard let failure = writer.firstMisplacedDelimiter(strict: strict) else {
                return (String(writer.output), segments)
            }
            segments = normalize(segments, fixing: failure)
        }
    }

    /// Joins neighbouring segments with the same styling, so two code spans never touch: their
    /// backtick fences would merge into one.
    private static func coalesced(_ segments: [InlineSegment]) -> [InlineSegment] {
        var result: [InlineSegment] = []
        for segment in segments {
            if let last = result.last, last.markers == segment.markers,
                last.isCode == segment.isCode
            {
                result[result.count - 1].text += segment.text
            } else {
                result.append(segment)
            }
        }
        return result
    }

    /// Whether `markdown` parses to the characters of `segments` with their styling. Whitespace
    /// styling is ignored, as are links the parser adds to bare URLs.
    private static func parsesBack(_ markdown: String, as segments: [InlineSegment]) -> Bool {
        let parsed = RichText.parseInline(Substring(markdown))
        let actual = parsed.runs.flatMap { run in
            parsed[run.range].characters.map {
                ($0, run.inlinePresentationIntent ?? [], run.link)
            }
        }
        let expected = segments.flatMap { segment in
            let intent = segment.intent
            let link = segment.link
            return segment.text.map { ($0, intent, link) }
        }
        guard actual.count == expected.count else {
            return false
        }
        return zip(actual, expected).allSatisfy { actual, expected in
            actual.0 == expected.0
                && (expected.0.isWhitespace
                    || (actual.1 == expected.1 && (expected.2 == nil || actual.2 == expected.2)))
        }
    }

    /// Takes `failure`'s marker off the run edge it sits on: moves edge punctuation outside it
    /// when there is any, else drops the marker from the run. Either way some character loses a
    /// marker, so `render` always terminates.
    static func normalize(
        _ segments: [InlineSegment], fixing failure: MarkdownLineWriter.Delimiter
    ) -> [InlineSegment] {
        var segments = segments
        let index = failure.segment
        let segment = segments[index]
        let split =
            segment.writesCodeSpan
            ? nil : splitEdgePunctuation(segment.text, leading: failure.isOpen)
        guard let split else {
            segments[index].markers.removeAll { $0 == failure.marker }
            return segments
        }
        let neighbour = neighbourMarkers(of: index, in: segments, before: failure.isOpen)
        let kept = segment.markers.filter { $0 != failure.marker && neighbour.contains($0) }
        guard !split.rest.isEmpty else {
            segments[index].markers = kept
            return segments
        }
        segments[index].text = split.rest
        let edge = InlineSegment(text: split.edge, markers: kept, isCode: false)
        segments.insert(edge, at: failure.isOpen ? index : index + 1)
        return segments
    }

    /// Splits whitespace plus a run of punctuation off one edge of `text`, or returns nil when
    /// that edge has no punctuation.
    static func splitEdgePunctuation(
        _ text: String, leading: Bool
    ) -> (edge: String, rest: String)? {
        let characters = leading ? Array(text) : Array(text.reversed())
        let spaces = characters.prefix(while: \.isWhitespace).count
        let marks = characters.dropFirst(spaces).prefix { character in
            let flanking = leading ? Flanking(after: character) : Flanking(before: character)
            return flanking == .punctuation
        }.count
        guard marks > 0 else {
            return nil
        }
        let edge = String(characters.prefix(spaces + marks))
        let rest = String(characters.dropFirst(spaces + marks))
        return leading ? (edge, rest) : (String(edge.reversed()), String(rest.reversed()))
    }

    private static func neighbourMarkers(
        of index: Int, in segments: [InlineSegment], before: Bool
    ) -> [RichText.Marker] {
        let candidates =
            before ? Array(segments[..<index].reversed()) : Array(segments[(index + 1)...])
        return candidates.first { !$0.isBlank }?.markers ?? []
    }
}

/// CommonMark's character classes for deciding whether a delimiter run can open or close.
///
/// The parser reads code points, so a character is classed by its code point next to the
/// delimiter: its last one when it comes before, its first one when it comes after. `‼️` is
/// punctuation plus a variation selector, so it counts as a word before a delimiter and as
/// punctuation after one.
enum Flanking {
    case space
    case punctuation
    case word

    /// The class of the character that comes before a delimiter run.
    init(before character: Character?) {
        self.init(character?.unicodeScalars.last)
    }

    /// The class of the character that comes after a delimiter run.
    init(after character: Character?) {
        self.init(character?.unicodeScalars.first)
    }

    private init(_ scalar: Unicode.Scalar?) {
        guard let scalar, !scalar.properties.isWhitespace else {
            self = .space
            return
        }
        self = Self.isPunctuation(scalar) ? .punctuation : .word
    }

    /// ASCII punctuation and symbols, plus Unicode punctuation (not other Unicode symbols).
    static func isPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
            .initialPunctuation, .finalPunctuation, .otherPunctuation:
            true
        case .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
            scalar.isASCII
        default:
            false
        }
    }

    static func canOpen(before: Flanking, after: Flanking) -> Bool {
        after != .space && (after != .punctuation || before != .word)
    }

    static func canClose(before: Flanking, after: Flanking) -> Bool {
        before != .space && (before != .punctuation || after != .word)
    }
}

/// Writes the inline Markdown of one line, keeping markers open across runs that share them,
/// and records where each emphasis marker went so `InlineMarkdown` can check it.
struct MarkdownLineWriter {
    struct Delimiter {
        let start: Int
        let end: Int
        let character: Character
        let isOpen: Bool
        let marker: RichText.Marker
        /// The segment whose edge the marker sits on.
        let segment: Int
    }

    private(set) var output: [Character] = []
    private var delimiters: [Delimiter] = []
    private var open: [RichText.Marker] = []
    private var pendingSpace = ""
    private var lastSegment = 0

    mutating func write(_ segment: InlineSegment, index: Int) {
        if segment.isBlank {
            pendingSpace += segment.text
            return
        }
        let parts =
            segment.writesCodeSpan
            ? ("", segment.text, "") : Self.splitWhitespace(segment.text)
        closeMarkers(downTo: keptCount(for: segment.markers))
        output += pendingSpace + parts.0
        for marker in segment.markers where !open.contains(marker) {
            emit(marker, isOpen: true, segment: index)
            open.append(marker)
        }
        let core = parts.1
        output += segment.writesCodeSpan ? RichText.codeSpan(core) : RichText.escapeMarkdown(core)
        pendingSpace = parts.2
        lastSegment = index
    }

    /// How many open markers stay open for a run with `markers`: the bottom of the stack that
    /// the run shares, cut below any link when the run opens emphasis, because Foundation's
    /// parser drops emphasis inside link text.
    private func keptCount(for markers: [RichText.Marker]) -> Int {
        let kept = open.prefix(while: { markers.contains($0) })
        let opensEmphasis = markers.contains { !$0.isLink && !kept.contains($0) }
        if opensEmphasis, let link = kept.firstIndex(where: \.isLink) {
            return link
        }
        return kept.count
    }

    mutating func finish() {
        closeMarkers(downTo: 0)
        output += pendingSpace
        pendingSpace = ""
    }

    /// The first emphasis marker whose delimiter run can't do its job: open or close. In strict
    /// mode, a run that could also do the opposite counts as misplaced too.
    func firstMisplacedDelimiter(strict: Bool) -> Delimiter? {
        var first = 0
        while first < delimiters.count {
            var last = first
            while last + 1 < delimiters.count, delimiters[last + 1].start == delimiters[last].end,
                delimiters[last + 1].character == delimiters[first].character
            {
                last += 1
            }
            let start = delimiters[first].start
            let end = delimiters[last].end
            let before = Flanking(before: start > 0 ? output[start - 1] : nil)
            let after = Flanking(after: end < output.count ? output[end] : nil)
            let canOpen = Flanking.canOpen(before: before, after: after)
            let canClose = Flanking.canClose(before: before, after: after)
            let failure = delimiters[first...last].first {
                $0.isOpen ? !canOpen || (strict && canClose) : !canClose || (strict && canOpen)
            }
            if let failure {
                return failure
            }
            first = last + 1
        }
        return nil
    }

    private mutating func emit(_ marker: RichText.Marker, isOpen: Bool, segment: Int) {
        let text = isOpen ? marker.open : marker.close
        if marker.isLink {
            if isOpen, output.last == "!" {
                output.insert("\\", at: output.count - 1)
            }
            output += text
            return
        }
        let start = output.count
        output += text
        delimiters.append(
            Delimiter(
                start: start, end: output.count, character: text.first ?? "*", isOpen: isOpen,
                marker: marker, segment: segment))
    }

    private mutating func closeMarkers(downTo count: Int) {
        while open.count > count {
            emit(open.removeLast(), isOpen: false, segment: lastSegment)
        }
    }

    private static func splitWhitespace(_ text: String) -> (String, String, String) {
        let start = text.firstIndex(where: { !$0.isWhitespace }) ?? text.endIndex
        let end = text.lastIndex(where: { !$0.isWhitespace }).map(text.index(after:)) ?? start
        return (String(text[..<start]), String(text[start..<end]), String(text[end...]))
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
        if let level = line.runs.first?.headingLevel {
            kind = .heading(level)
            content = line
        } else if line.characters.starts(with: RichText.bulletPrefix) {
            let start = line.characters.index(
                line.startIndex, offsetBy: RichText.bulletPrefix.count)
            kind = .bullet
            content = line[start..<line.endIndex]
        } else {
            kind = .plain
            content = line
        }
    }
}

// MARK: - HTML output

enum HTMLWriter {
    static let prefix = "<meta charset=\"utf-8\">"

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
            if let url = run.link, RichText.safeSchemes.contains(url.scheme?.lowercased() ?? "") {
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
