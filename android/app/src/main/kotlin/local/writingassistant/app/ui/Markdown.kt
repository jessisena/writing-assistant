package local.writingassistant.app.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle

/**
 * Converts the Markdown subset Claude returns into an [AnnotatedString] for display, and into
 * HTML plus a plain-text fallback for the clipboard. Mirrors `RichText.swift`.
 *
 * Supported: `**bold**`/`__bold__`, `*italic*`/`_italic_`, `~~strike~~`, inline code, links
 * written as `[text](url)` or `<url>` (bare URLs stay plain text), `- `/`* ` bullet lines,
 * `1. ` numbered lines and `#` headings. Anything else, including unclosed markers, stays
 * literal text. Only http, https and mailto links are kept; others keep just their label.
 */
object Markdown {
    private const val BULLET_PREFIX = "• "
    private const val HTML_PREFIX = "<meta charset=\"utf-8\">"
    private val safeSchemes = setOf("http", "https", "mailto")

    /** Renders [markdown] for display; links are styled with [linkColor] and open on tap. */
    fun toAnnotatedString(
        markdown: String,
        linkColor: Color = Color.Unspecified,
    ): AnnotatedString {
        val linkStyles = TextLinkStyles(SpanStyle(color = linkColor, textDecoration = UNDERLINE))
        return buildAnnotatedString {
            parse(markdown).forEachIndexed { index, line ->
                if (index > 0) append('\n')
                val prefix = linePrefix(line.kind)
                if (line.kind is LineKind.Heading) {
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold)) {
                        appendSpans(prefix, line.spans, linkStyles)
                    }
                } else {
                    appendSpans(prefix, line.spans, linkStyles)
                }
            }
        }
    }

    /**
     * Writes [markdown] as an HTML fragment for the clipboard. Text and link targets are
     * escaped; consecutive bullet or numbered lines become one list, headings become bold
     * paragraphs and other line breaks become `<br>`.
     */
    fun toHtml(markdown: String): String {
        val lines = parse(markdown)
        val html = StringBuilder(HTML_PREFIX)
        lines.forEachIndexed { index, line ->
            val previous = lines.getOrNull(index - 1)?.kind
            val next = lines.getOrNull(index + 1)?.kind
            html.append(htmlBlock(line, previous, next))
        }
        return html.toString()
    }

    /**
     * Returns the plain text for apps that don't read HTML: list markers stay, and a link
     * keeps its target as `label (url)` unless the label already is the target.
     */
    fun toClipboardText(markdown: String): String =
        parse(markdown).joinToString("\n") { line ->
            linePrefix(line.kind) + line.spans.joinToString("") { plainSpan(it) }
        }

    internal fun parse(markdown: String): List<MarkdownLine> =
        markdown.replace("\r\n", "\n").split('\n').map(::parseLine)

    private fun parseLine(line: String): MarkdownLine {
        HEADING.matchAt(line, 0)?.let { match ->
            val level = match.groupValues[1].length
            return MarkdownLine(
                LineKind.Heading(level),
                InlineParser.parse(line.substring(level + 1)),
            )
        }
        if (line.startsWith("- ") || line.startsWith("* ")) {
            return MarkdownLine(LineKind.Bullet, InlineParser.parse(line.substring(2)))
        }
        NUMBERED.matchAt(line, 0)?.let { match ->
            val kind = LineKind.Numbered(match.groupValues[1].toInt(), match.value)
            return MarkdownLine(kind, InlineParser.parse(line.substring(match.value.length)))
        }
        return MarkdownLine(LineKind.Plain, InlineParser.parse(line))
    }

    private fun linePrefix(kind: LineKind): String =
        when (kind) {
            LineKind.Bullet -> BULLET_PREFIX
            is LineKind.Numbered -> kind.marker
            LineKind.Plain, is LineKind.Heading -> ""
        }

    private fun AnnotatedString.Builder.appendSpans(
        prefix: String,
        spans: List<InlineSpan>,
        linkStyles: TextLinkStyles,
    ) {
        append(prefix)
        for (span in spans) {
            val url = span.style.link?.takeIf(::isSafe)
            if (url == null) {
                withStyle(spanStyle(span.style)) { append(span.text) }
            } else {
                withLink(LinkAnnotation.Url(url, linkStyles)) {
                    withStyle(spanStyle(span.style)) { append(span.text) }
                }
            }
        }
    }

    private fun spanStyle(style: InlineStyle): SpanStyle =
        SpanStyle(
            fontWeight = if (style.bold) FontWeight.Bold else null,
            fontStyle = if (style.italic) FontStyle.Italic else null,
            fontFamily = if (style.code) FontFamily.Monospace else null,
            textDecoration = if (style.strike) TextDecoration.LineThrough else null,
        )

    private fun htmlBlock(
        line: MarkdownLine,
        previous: LineKind?,
        next: LineKind?,
    ): String {
        val inline = line.spans.joinToString("") { htmlSpan(it) }
        return when (val kind = line.kind) {
            LineKind.Bullet -> {
                val open = if (previous == LineKind.Bullet) "" else "<ul>"
                val close = if (next == LineKind.Bullet) "" else "</ul>"
                "$open<li>$inline</li>$close"
            }

            is LineKind.Numbered -> {
                val open = if (previous is LineKind.Numbered) "" else orderedListOpen(kind.number)
                val close = if (next is LineKind.Numbered) "" else "</ol>"
                "$open<li>$inline</li>$close"
            }

            is LineKind.Heading -> {
                "<p><b>$inline</b></p>"
            }

            LineKind.Plain -> {
                if (next == LineKind.Plain) "$inline<br>" else inline
            }
        }
    }

    private fun orderedListOpen(start: Int): String =
        if (start ==
            1
        ) {
            "<ol>"
        } else {
            "<ol start=\"$start\">"
        }

    private fun htmlSpan(span: InlineSpan): String {
        val style = span.style
        var html = escapeHtml(span.text)
        val tags =
            listOf(
                style.code to "code",
                style.strike to "s",
                style.italic to "i",
                style.bold to "b",
            )
        for ((enabled, tag) in tags) {
            if (enabled) html = "<$tag>$html</$tag>"
        }
        val url = style.link?.takeIf(::isSafe) ?: return html
        return "<a href=\"${escapeHtml(url)}\">$html</a>"
    }

    private fun plainSpan(span: InlineSpan): String {
        val url = span.style.link?.takeIf(::isSafe)
        if (url == null || url == span.text || url == "mailto:${span.text}") return span.text
        return "${span.text} ($url)"
    }

    private fun isSafe(url: String): Boolean =
        url.substringBefore(':', "").lowercase() in safeSchemes

    private fun escapeHtml(text: String): String =
        buildString {
            for (character in text) {
                when (character) {
                    '&' -> append("&amp;")
                    '<' -> append("&lt;")
                    '>' -> append("&gt;")
                    '"' -> append("&quot;")
                    '\'' -> append("&#39;")
                    else -> append(character)
                }
            }
        }

    private val UNDERLINE = TextDecoration.Underline
    private val HEADING = Regex("(#{1,6}) ")
    private val NUMBERED = Regex("(\\d{1,9})[.)] ")
}

internal sealed interface LineKind {
    data object Plain : LineKind

    data object Bullet : LineKind

    /** A numbered list line; [marker] is the literal prefix, such as `"3. "`. */
    data class Numbered(
        val number: Int,
        val marker: String,
    ) : LineKind

    data class Heading(
        val level: Int,
    ) : LineKind
}

internal data class MarkdownLine(
    val kind: LineKind,
    val spans: List<InlineSpan>,
)

internal data class InlineStyle(
    val bold: Boolean = false,
    val italic: Boolean = false,
    val code: Boolean = false,
    val strike: Boolean = false,
    val link: String? = null,
)

internal data class InlineSpan(
    val text: String,
    val style: InlineStyle,
)
