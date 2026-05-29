#include "glyph_metrics.h"

#include "utf8.h"

namespace readmigo::typesetting {

namespace {

// Width ratio (multiplier on font_size) for a single code point.
double width_ratio(char32_t cp) noexcept {
    if (cp == 0) return 0.0;
    if (cp < 0x20u) return 0.0;        // control characters
    if (utf8::is_cjk(cp)) return 1.0;  // CJK full-width
    // Common Latin Extended / Greek / Cyrillic — treat as 0.55 like ASCII.
    if (cp < 0x0500u) {
        // Narrow punctuation that's visibly thinner.
        switch (cp) {
            case U'i': case U'I': case U'l': case U'.': case U',':
            case U';': case U':': case U'\'': case U'!': case U'|':
                return 0.30;
            case U' ':
                return 0.28;
            case U'm': case U'M': case U'w': case U'W':
                return 0.85;
            default:
                return 0.55;
        }
    }
    // Anything else (symbols, emoji) — assume square.
    return 1.0;
}

}  // namespace

double GlyphMetrics::advance_width(char32_t cp, double font_size) noexcept {
    return width_ratio(cp) * font_size;
}

LineMetrics GlyphMetrics::line_metrics(double font_size, double line_height_multiplier) noexcept {
    LineMetrics m{};
    m.ascent = font_size * 0.80;
    m.descent = font_size * 0.20;
    m.line_height = font_size * line_height_multiplier;
    return m;
}

double GlyphMetrics::measure_string(std::string_view utf8_bytes, double font_size, double letter_spacing) {
    double total = 0.0;
    std::size_t pos = 0;
    std::size_t count = 0;
    while (pos < utf8_bytes.size()) {
        const char32_t cp = utf8::decode_one(utf8_bytes, pos);
        if (cp == 0xFFFD && pos == 0) break;  // total decode failure
        total += advance_width(cp, font_size);
        ++count;
    }
    if (count > 1) total += letter_spacing * static_cast<double>(count - 1);
    return total;
}

}  // namespace readmigo::typesetting
