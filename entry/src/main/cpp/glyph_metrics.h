#pragma once

#include <cstdint>
#include <string>
#include <string_view>

namespace readmigo::typesetting {

// Per-font-size metrics. All values in CSS pixels.
struct LineMetrics {
    double ascent;
    double descent;
    double line_height;     // ascent + descent + leading
};

// Width estimator + line-metrics provider.
//
// The W3 milestone uses a hard-coded heuristic table:
//   - ASCII glyphs:   fontSize * 0.55  (proportional fallback)
//   - CJK glyphs:     fontSize * 1.0   (full-width)
//   - Combining marks etc. treated as zero-width
//
// W5 will replace this with a freetype/harfbuzz-backed implementation.
class GlyphMetrics {
public:
    // Estimate advance width for a single code point at the given font size.
    static double advance_width(char32_t cp, double font_size) noexcept;

    // Estimate line metrics (ascent / descent / line_height) for a font size.
    // line_height = font_size * 1.35 unless `line_height_multiplier` overrides.
    static LineMetrics line_metrics(double font_size, double line_height_multiplier = 1.35) noexcept;

    // Convenience: total width of a UTF-8 string at the given font size.
    // letter_spacing is added between every pair of code points.
    static double measure_string(std::string_view utf8, double font_size, double letter_spacing = 0.0);
};

}  // namespace readmigo::typesetting
