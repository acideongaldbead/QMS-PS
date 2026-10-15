package com.nexperia.qms.common.richtext;

import org.jsoup.Jsoup;
import org.jsoup.nodes.Document;
import org.jsoup.safety.Safelist;
import org.springframework.stereotype.Component;

/**
 * Whitelist filter for rich-text bodies (announcements today).
 *
 * The body is stored as HTML and rendered with v-html, so it must be cleaned on
 * the way IN -- this is the only place a body becomes trusted. Reads return the
 * stored string untouched: re-cleaning on read would normalise the markup and
 * break the byte-for-byte round trip the acceptance script asserts.
 */
@Component
public class HtmlSanitizer {

    /**
     * Text formatting only: no images, no tables, no inline styles, no scripts.
     * Must cover exactly what the editor emits (TipTap wraps every paragraph in
     * {@code <p>}); dropping a tag here silently deletes that formatting on save.
     */
    private static final Safelist FORMATTING = Safelist.none()
            .addTags("p", "br", "strong", "b", "em", "i", "u",
                    "h1", "h2", "h3", "h4", "ul", "ol", "li", "blockquote", "a")
            .addAttributes("a", "href", "target", "rel")
            .addProtocols("a", "href", "http", "https", "mailto");

    /**
     * prettyPrint(false) is load-bearing: the default re-indents the markup, so
     * the stored bytes would change on every save and never round-trip.
     */
    private static final Document.OutputSettings OUTPUT =
            new Document.OutputSettings().prettyPrint(false);

    public String sanitize(String html) {
        if (html == null) {
            return null;
        }
        return Jsoup.clean(html, "", FORMATTING, OUTPUT);
    }
}
