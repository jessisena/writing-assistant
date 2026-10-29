package local.writingassistant.app.ui

/**
 * Parses the inline Markdown of one line into styled spans. Never fails: a marker without a
 * valid partner, as model output often has, is kept as literal text.
 *
 * Emphasis follows a simplified CommonMark flanking rule: an opening marker must be followed by
 * a non-space character and a closing one preceded by one; `_` also can't open or close inside
 * a word. A marker run that can only open while looking for a closer is matched with its own
 * closer first, so `*a **b** c*` nests. Closer searches are memoised, so parsing stays
 * polynomial however many markers lack a partner.
 *
 * A link destination may contain balanced parentheses. An image, `![alt](url)`, isn't
 * rendered: it is kept as that literal text, with the alt text's styling dropped.
 */
internal class InlineParser private constructor(
    private val source: String,
) {
    private val spans = mutableListOf<InlineSpan>()
    private val closers = HashMap<CloserKey, Int>()
    private val codeSpanEnds = HashMap<Pair<Int, Int>, Int>()

    private data class CloserKey(
        val marker: Char,
        val width: Int,
        val from: Int,
        val end: Int,
    )

    private data class LinkParts(
        val labelEnd: Int,
        val end: Int,
        val url: String,
    )

    private fun parseRange(
        start: Int,
        end: Int,
        style: InlineStyle,
    ) {
        var index = start
        while (index < end) {
            index = parseAt(index, end, style)
        }
    }

    private fun parseAt(
        index: Int,
        end: Int,
        style: InlineStyle,
    ): Int {
        val next =
            when (source[index]) {
                '\\' -> escape(index, end, style)
                '`' -> codeSpan(index, end, style)
                '*', '_', '~' -> emphasis(index, end, style)
                '[' -> link(index, end, style)
                '!' -> image(index, end, style)
                '<' -> autolink(index, end, style)
                else -> null
            }
        if (next != null) return next
        emit(source[index].toString(), style)
        return index + 1
    }

    private fun escape(
        index: Int,
        end: Int,
        style: InlineStyle,
    ): Int? {
        val escaped = source.getOrNull(index + 1)?.takeIf { index + 1 < end && it in PUNCTUATION }
        escaped ?: return null
        emit(escaped.toString(), style)
        return index + 2
    }

    private fun codeSpan(
        index: Int,
        end: Int,
        style: InlineStyle,
    ): Int {
        val fence = runLength(index, end, '`')
        val close = findBacktickClose(index + fence, end, fence)
        if (close < 0) {
            emit(source.substring(index, index + fence), style)
            return index + fence
        }
        var content = source.substring(index + fence, close)
        if (content.startsWith(' ') && content.endsWith(' ') && content.isNotBlank()) {
            content = content.substring(1, content.length - 1)
        }
        emit(content, style.copy(code = true))
        return close + fence
    }

    private fun emphasis(
        index: Int,
        end: Int,
        style: InlineStyle,
    ): Int? {
        val marker = source[index]
        val run = runLength(index, end, marker)
        val width = markerWidth(marker, run)
        if (width == 0 || !canOpen(index, run, marker, end)) {
            emit(source.substring(index, index + run), style)
            return index + run
        }
        val close = findCloser(marker, width, index + width, end)
        if (close < 0) return null
        parseRange(index + width, close, styled(style, marker, width))
        return close + width
    }

    private fun markerWidth(
        marker: Char,
        run: Int,
    ): Int =
        when {
            marker == '~' -> if (run == 2) 2 else 0
            run > MAX_EMPHASIS -> 0
            else -> run
        }

    private fun styled(
        style: InlineStyle,
        marker: Char,
        width: Int,
    ): InlineStyle =
        when {
            marker == '~' -> style.copy(strike = true)
            width == 1 -> style.copy(italic = true)
            width == 2 -> style.copy(bold = true)
            else -> style.copy(bold = true, italic = true)
        }

    private fun findCloser(
        marker: Char,
        width: Int,
        from: Int,
        end: Int,
    ): Int =
        closers.getOrPut(CloserKey(marker, width, from, end)) {
            scanForCloser(marker, width, from, end)
        }

    private fun scanForCloser(
        marker: Char,
        width: Int,
        from: Int,
        end: Int,
    ): Int {
        var index = from
        while (index < end) {
            val run = if (source[index] == marker) runLength(index, end, marker) else 0
            index =
                when {
                    source[index] == '\\' -> index + 2
                    source[index] == '`' -> skipCodeSpan(index, end)
                    run == 0 -> index + 1
                    isOpenerOnly(index, run, marker, end) -> skipNested(marker, index, run, end)
                    run >= width && canClose(index, run, marker) -> return index
                    else -> index + run
                }
        }
        return -1
    }

    private fun skipNested(
        marker: Char,
        index: Int,
        run: Int,
        end: Int,
    ): Int {
        val width = markerWidth(marker, run)
        if (width == 0) return index + run
        val close = findCloser(marker, width, index + width, end)
        return if (close < 0) index + run else close + width
    }

    private fun canOpen(
        index: Int,
        run: Int,
        marker: Char,
        end: Int,
    ): Boolean {
        val after = source.getOrNull(index + run)?.takeIf { index + run < end } ?: return false
        if (after.isWhitespace()) return false
        return marker != '_' || source.getOrNull(index - 1)?.isLetterOrDigit() != true
    }

    private fun canClose(
        index: Int,
        run: Int,
        marker: Char,
    ): Boolean {
        val before = source.getOrNull(index - 1) ?: return false
        if (before.isWhitespace()) return false
        return marker != '_' || source.getOrNull(index + run)?.isLetterOrDigit() != true
    }

    private fun isOpenerOnly(
        index: Int,
        run: Int,
        marker: Char,
        end: Int,
    ): Boolean {
        if (!canOpen(index, run, marker, end)) return false
        val before = source.getOrNull(index - 1) ?: return true
        val after = source[index + run]
        return before.isWhitespace() || (before in PUNCTUATION && after !in PUNCTUATION)
    }

    private fun link(
        index: Int,
        end: Int,
        style: InlineStyle,
    ): Int? {
        if (style.link != null) return null
        val parts = linkParts(index, end) ?: return null
        parseRange(index + 1, parts.labelEnd, style.copy(link = parts.url))
        return parts.end
    }

    private fun image(
        index: Int,
        end: Int,
        style: InlineStyle,
    ): Int? {
        if (source.getOrNull(index + 1) != '[') return null
        val parts = linkParts(index + 1, end) ?: return null
        val alt = parse(source.substring(index + 2, parts.labelEnd)).joinToString("") { it.text }
        emit("![$alt](${parts.url})", style)
        return parts.end
    }

    private fun linkParts(
        index: Int,
        end: Int,
    ): LinkParts? {
        val closeBracket = findBracketClose(index + 1, end)
        if (closeBracket < 0 || source.getOrNull(closeBracket + 1) != '(') return null
        val closeParen = findDestinationClose(closeBracket + 2, end)
        if (closeParen < 0) return null
        val url = source.substring(closeBracket + 2, closeParen).trim()
        if (url.isEmpty() || url.any { it.isWhitespace() }) return null
        return LinkParts(closeBracket, closeParen + 1, url)
    }

    private fun findDestinationClose(
        from: Int,
        end: Int,
    ): Int {
        var depth = 0
        var index = from
        while (index < end) {
            when (source[index]) {
                '\\' -> index++
                '(' -> depth++
                ')' -> if (depth == 0) return index else depth--
            }
            index++
        }
        return -1
    }

    private fun autolink(
        index: Int,
        end: Int,
        style: InlineStyle,
    ): Int? {
        if (style.link != null) return null
        val close = source.indexOf('>', index + 1)
        if (close < 0 || close >= end) return null
        val content = source.substring(index + 1, close)
        val url =
            when {
                URI.matches(content) -> content
                EMAIL.matches(content) -> "mailto:$content"
                else -> return null
            }
        emit(content, style.copy(link = url))
        return close + 1
    }

    private fun findBracketClose(
        from: Int,
        end: Int,
    ): Int {
        var depth = 0
        var index = from
        while (index < end) {
            when (source[index]) {
                '\\' -> index++
                '`' -> index = skipCodeSpan(index, end) - 1
                '[' -> depth++
                ']' -> if (depth == 0) return index else depth--
            }
            index++
        }
        return -1
    }

    private fun skipCodeSpan(
        index: Int,
        end: Int,
    ): Int =
        codeSpanEnds.getOrPut(index to end) {
            val fence = runLength(index, end, '`')
            val close = findBacktickClose(index + fence, end, fence)
            if (close < 0) index + fence else close + fence
        }

    private fun findBacktickClose(
        from: Int,
        end: Int,
        fence: Int,
    ): Int {
        var index = from
        while (index < end) {
            if (source[index] != '`') {
                index++
                continue
            }
            val run = runLength(index, end, '`')
            if (run == fence) return index
            index += run
        }
        return -1
    }

    private fun runLength(
        index: Int,
        end: Int,
        char: Char,
    ): Int {
        var length = 0
        while (index + length < end && source[index + length] == char) length++
        return length
    }

    private fun emit(
        text: String,
        style: InlineStyle,
    ) {
        val last = spans.lastOrNull()
        if (last != null && last.style == style) {
            spans[spans.lastIndex] = last.copy(text = last.text + text)
        } else {
            spans += InlineSpan(text, style)
        }
    }

    companion object {
        private const val MAX_EMPHASIS = 3
        private const val PUNCTUATION = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
        private val URI = Regex("[A-Za-z][A-Za-z0-9+.-]{1,31}:[^\\s<>]*")
        private val EMAIL = Regex("[^\\s<>@]+@[^\\s<>@]+\\.[^\\s<>@]+")

        /** Parses one line of inline Markdown; adjacent spans with the same style are merged. */
        fun parse(line: String): List<InlineSpan> =
            InlineParser(line).run {
                parseRange(0, source.length, InlineStyle())
                spans.toList()
            }
    }
}
