package local.writingassistant.app.ui

import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MarkdownTest {
    private fun spans(line: String) = InlineParser.parse(line)

    private fun span(
        text: String,
        style: InlineStyle = InlineStyle(),
    ) = InlineSpan(text, style)

    private val bold = InlineStyle(bold = true)
    private val italic = InlineStyle(italic = true)

    @Test
    fun `plain text is one unstyled span`() {
        assertEquals(listOf(span("hello world")), spans("hello world"))
    }

    @Test
    fun `empty input parses to one empty line`() {
        assertEquals(listOf(MarkdownLine(LineKind.Plain, emptyList())), Markdown.parse(""))
        assertEquals("", Markdown.toAnnotatedString("").text)
    }

    @Test
    fun `bold italic strike and code are styled`() {
        assertEquals(
            listOf(
                span("bold", bold),
                span(" "),
                span("it", italic),
                span(" "),
                span("gone", InlineStyle(strike = true)),
                span(" "),
                span("x*y", InlineStyle(code = true)),
            ),
            spans("**bold** *it* ~~gone~~ `x*y`"),
        )
    }

    @Test
    fun `underscores emphasise words but not snake_case`() {
        assertEquals(
            listOf(span("bold", bold), span(" and snake_case_name")),
            spans("__bold__ and snake_case_name"),
        )
        assertEquals(listOf(span("it", italic)), spans("_it_"))
    }

    @Test
    fun `nested emphasis keeps both styles`() {
        assertEquals(
            listOf(
                span("a ", bold),
                span("b", InlineStyle(bold = true, italic = true)),
                span(" c", bold),
            ),
            spans("**a *b* c**"),
        )
        assertEquals(
            listOf(
                span("a ", italic),
                span("b", InlineStyle(bold = true, italic = true)),
                span(" c", italic),
            ),
            spans("*a **b** c*"),
        )
        assertEquals(
            listOf(span("all", InlineStyle(bold = true, italic = true))),
            spans("***all***"),
        )
    }

    @Test
    fun `unclosed markers stay literal`() {
        assertEquals(listOf(span("**bold")), spans("**bold"))
        assertEquals(listOf(span("a * b")), spans("a * b"))
        assertEquals(listOf(span("`code")), spans("`code"))
        assertEquals(listOf(span("[label](no close")), spans("[label](no close"))
        assertEquals(listOf(span("2 * 3 * 4")), spans("2 * 3 * 4"))
    }

    @Test
    fun `half matched run keeps the extra marker`() {
        assertEquals(listOf(span("*"), span("a", italic)), spans("**a*"))
    }

    @Test
    fun `escaped markers are literal`() {
        assertEquals(listOf(span("*not italic*")), spans("\\*not italic\\*"))
        assertEquals(listOf(span("a\\b")), spans("a\\b"))
    }

    @Test
    fun `markers inside code are literal`() {
        assertEquals(listOf(span("**x**", InlineStyle(code = true))), spans("`**x**`"))
    }

    @Test
    fun `links keep their label styling and target`() {
        assertEquals(
            listOf(
                span("see "),
                span("the ", InlineStyle(link = "https://a.com/x")),
                span("docs", InlineStyle(bold = true, link = "https://a.com/x")),
            ),
            spans("see [the **docs**](https://a.com/x)"),
        )
        assertEquals(
            listOf(span("https://a.com", InlineStyle(link = "https://a.com"))),
            spans("<https://a.com>"),
        )
        assertEquals(
            listOf(span("me@a.com", InlineStyle(link = "mailto:me@a.com"))),
            spans("<me@a.com>"),
        )
    }

    @Test
    fun `link destinations keep balanced parentheses`() {
        val url = "https://en.wikipedia.org/wiki/Foo_(bar)"
        assertEquals(listOf(span("x", InlineStyle(link = url))), spans("[x]($url)"))
        assertEquals(
            listOf(span("x", InlineStyle(link = "https://a.com/(b)")), span(" after")),
            spans("[x](https://a.com/(b)) after"),
        )
    }

    @Test
    fun `link destinations with unbalanced parentheses stay literal`() {
        assertEquals(listOf(span("[x](https://a.com/(b)")), spans("[x](https://a.com/(b)"))
    }

    @Test
    fun `images stay literal with plain alt text`() {
        val image = "![alt](https://a.com/i.png)"
        assertEquals(listOf(span(image)), spans(image))
        assertEquals(
            listOf(span("see ![a b](u) now")),
            spans("see ![a **b**](u) now"),
        )
        assertEquals(
            listOf(span("!"), span("alt", InlineStyle(link = "https://a.com"))),
            spans("\\![alt](https://a.com)"),
        )
    }

    @Test
    fun `bare urls and malformed links stay plain`() {
        assertEquals(listOf(span("go to https://a.com now")), spans("go to https://a.com now"))
        assertEquals(listOf(span("[a] (b)")), spans("[a] (b)"))
        assertEquals(listOf(span("[a](b c)")), spans("[a](b c)"))
    }

    @Test
    fun `line kinds are detected`() {
        val lines = Markdown.parse("# Title\n- one\n* two\n3. three\nplain\n#no")
        assertEquals(
            listOf(
                LineKind.Heading(1),
                LineKind.Bullet,
                LineKind.Bullet,
                LineKind.Numbered(3, "3. "),
                LineKind.Plain,
                LineKind.Plain,
            ),
            lines.map { it.kind },
        )
    }

    @Test
    fun `annotated string renders bullets styles and safe links`() {
        val text =
            Markdown.toAnnotatedString(
                "- **hi** [x](https://a.com) [y](javascript:x)\n2. `c`",
            )
        assertEquals("• hi x y\n2. c", text.text)
        val styles = text.spanStyles.map { text.text.substring(it.start, it.end) to it.item }
        assertTrue(styles.any { (s, style) -> s == "hi" && style.fontWeight == FontWeight.Bold })
        assertTrue(
            styles.any { (s, style) ->
                s == "c" && style.fontFamily == FontFamily.Monospace
            },
        )
        val links = text.getLinkAnnotations(0, text.length)
        assertEquals(listOf("x"), links.map { text.text.substring(it.start, it.end) })
        assertEquals("https://a.com", (links.single().item as LinkAnnotation.Url).url)
    }

    @Test
    fun `annotated string styles italic and headings`() {
        val text = Markdown.toAnnotatedString("## Head\n*it*")
        assertEquals("Head\nit", text.text)
        assertTrue(
            text.spanStyles.any {
                it.start == 0 && it.end == 4 &&
                    it.item.fontWeight == FontWeight.Bold
            },
        )
        assertTrue(text.spanStyles.any { it.start == 5 && it.item.fontStyle == FontStyle.Italic })
    }

    @Test
    fun `html groups lists and escapes text`() {
        val html = Markdown.toHtml("Hi <b> & \"q\"\nnext\n- a\n- **b**\n# T\n3. x\n4. y")
        assertEquals(
            "<meta charset=\"utf-8\">Hi &lt;b&gt; &amp; &quot;q&quot;<br>next" +
                "<ul><li>a</li><li><b>b</b></li></ul><p><b>T</b></p>" +
                "<ol start=\"3\"><li>x</li><li>y</li></ol>",
            html,
        )
    }

    @Test
    fun `html nests inline tags and drops unsafe links`() {
        assertEquals(
            "<meta charset=\"utf-8\"><a href=\"https://a.com?a=1&amp;b=2\"><b><i>x</i></b></a> " +
                "<code>c</code> <s>s</s> y",
            Markdown.toHtml("[***x***](https://a.com?a=1&b=2) `c` ~~s~~ [y](file:///etc)"),
        )
        assertEquals("<meta charset=\"utf-8\"><ol><li>one</li></ol>", Markdown.toHtml("1. one"))
    }

    @Test
    fun `empty markdown gives just the charset`() {
        assertEquals("<meta charset=\"utf-8\">", Markdown.toHtml(""))
    }

    @Test
    fun `clipboard text keeps list markers and link targets`() {
        assertEquals(
            "• see docs (https://a.com)\n2. https://b.com\nmail me@a.com\nbad",
            Markdown.toClipboardText(
                "- see [docs](https://a.com)\n2. <https://b.com>\nmail <me@a.com>\n[bad](ftp://x)",
            ),
        )
    }

    @Test
    fun `crlf line endings are normalised`() {
        assertEquals("a\nb", Markdown.toClipboardText("a\r\nb"))
    }
}
