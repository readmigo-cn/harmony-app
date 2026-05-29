#pragma once

#include <cstddef>
#include <string>
#include <string_view>
#include <vector>

namespace readmigo::typesetting {

// One typeset line (a slice of the original UTF-8 source).
struct LineSlice {
    std::size_t byte_start;   // inclusive byte offset into the source
    std::size_t byte_end;     // exclusive byte offset
    std::size_t char_start;   // inclusive code-point index
    std::size_t char_length;  // number of code points
    double width;             // measured width in CSS pixels
    std::string text;         // the actual UTF-8 bytes (convenience)
};

enum class LineBreakStrategy {
    kGreedy,   // first-fit; minimises CPU at the cost of ragged right edge
    kBestFit,  // minimise sum-of-squares of trailing space
};

class LineBreaker {
public:
    // Break a UTF-8 paragraph into lines that fit within `max_width` at the
    // given font size. The breaker is locale-agnostic: ASCII words break at
    // whitespace; CJK breaks at character boundaries; mixed content does both.
    //
    // The output respects no-break-before / no-break-after punctuation rules.
    static std::vector<LineSlice> break_paragraph(
        std::string_view utf8,
        double font_size,
        double max_width,
        LineBreakStrategy strategy = LineBreakStrategy::kGreedy,
        double letter_spacing = 0.0);
};

}  // namespace readmigo::typesetting
