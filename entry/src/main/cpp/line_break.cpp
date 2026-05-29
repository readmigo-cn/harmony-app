#include "line_break.h"

#include <algorithm>
#include <cmath>
#include <limits>

#include "glyph_metrics.h"
#include "utf8.h"

namespace readmigo::typesetting {

namespace {

// One atom = the smallest unit the breaker considers when placing characters
// on a line. For ASCII text an atom is a whole word (run of word-chars); for
// CJK an atom is one code point. Whitespace between ASCII atoms is collapsed
// to a single soft space.
struct Atom {
    std::size_t byte_start;
    std::size_t byte_end;
    std::size_t char_start;
    std::size_t char_count;
    double width;
    bool is_space;        // true for the synthetic gap between ASCII words
    bool starts_with_no_break_before;  // first cp is closing punctuation
    bool ends_with_no_break_after;     // last cp is opening punctuation
};

std::vector<Atom> tokenize(std::string_view utf8, double font_size, double letter_spacing) {
    std::vector<Atom> atoms;
    atoms.reserve(utf8.size() / 2 + 4);

    std::size_t byte_pos = 0;
    std::size_t char_pos = 0;
    const double space_w = GlyphMetrics::advance_width(U' ', font_size);

    while (byte_pos < utf8.size()) {
        const std::size_t lead_byte = byte_pos;
        char32_t cp = utf8::decode_one(utf8, byte_pos);

        if (utf8::is_whitespace(cp)) {
            // Collapse run of whitespace into one synthetic space atom.
            while (byte_pos < utf8.size()) {
                std::size_t peek = byte_pos;
                const char32_t next_cp = utf8::decode_one(utf8, peek);
                if (!utf8::is_whitespace(next_cp)) break;
                byte_pos = peek;
            }
            // Drop leading whitespace at start of paragraph; otherwise emit gap.
            if (!atoms.empty() && !atoms.back().is_space) {
                Atom gap{};
                gap.byte_start = lead_byte;
                gap.byte_end = byte_pos;
                gap.char_start = char_pos;
                gap.char_count = 1;
                gap.width = space_w;
                gap.is_space = true;
                atoms.push_back(gap);
                char_pos += 1;
            }
            continue;
        }

        if (utf8::is_cjk(cp)) {
            // CJK code points are individual atoms (per-char breaking).
            Atom a{};
            a.byte_start = lead_byte;
            a.byte_end = byte_pos;
            a.char_start = char_pos;
            a.char_count = 1;
            a.width = GlyphMetrics::advance_width(cp, font_size);
            a.is_space = false;
            a.starts_with_no_break_before = utf8::is_no_break_before(cp);
            a.ends_with_no_break_after = utf8::is_no_break_after(cp);
            atoms.push_back(a);
            char_pos += 1;
            continue;
        }

        // ASCII (or other non-CJK, non-space): accumulate a word atom up to
        // the next whitespace OR the next CJK character.
        Atom word{};
        word.byte_start = lead_byte;
        word.is_space = false;
        word.starts_with_no_break_before = utf8::is_no_break_before(cp);
        std::size_t accumulated = 1;
        double w = GlyphMetrics::advance_width(cp, font_size);
        char32_t last_cp = cp;

        while (byte_pos < utf8.size()) {
            std::size_t peek = byte_pos;
            const char32_t next_cp = utf8::decode_one(utf8, peek);
            if (utf8::is_whitespace(next_cp) || utf8::is_cjk(next_cp)) break;
            byte_pos = peek;
            const double nw = GlyphMetrics::advance_width(next_cp, font_size);
            w += nw;
            last_cp = next_cp;
            accumulated += 1;
        }

        if (accumulated > 1) {
            w += letter_spacing * static_cast<double>(accumulated - 1);
        }
        word.byte_end = byte_pos;
        word.char_start = char_pos;
        word.char_count = accumulated;
        word.width = w;
        word.ends_with_no_break_after = utf8::is_no_break_after(last_cp);
        atoms.push_back(word);
        char_pos += accumulated;
    }

    return atoms;
}

// Pack a line starting at atoms[i]; returns the index of the first atom on
// the NEXT line and stores the consumed range + measured width.
std::size_t pack_greedy(const std::vector<Atom>& atoms,
                        std::size_t start,
                        double max_width,
                        std::size_t& out_end_exclusive,
                        double& out_width) {
    double width = 0.0;
    std::size_t i = start;

    // Skip leading whitespace atoms.
    while (i < atoms.size() && atoms[i].is_space) ++i;
    const std::size_t line_start = i;

    while (i < atoms.size()) {
        const Atom& a = atoms[i];

        // Forbid breaking BEFORE a `no_break_before` atom: glue it onto the
        // previous one if we already placed something on this line.
        const double trial = width + a.width;
        if (trial > max_width && i > line_start) {
            // Try to honour no-break rules: if previous atom ends with a
            // no-break-after, we must keep going (overflow the line).
            const Atom& prev = atoms[i - 1];
            if (!prev.ends_with_no_break_after && !a.starts_with_no_break_before) {
                break;
            }
        }
        width = trial;
        ++i;
    }

    // If we did not advance at all (single atom wider than the line), force
    // one atom on this line to avoid an infinite loop.
    if (i == line_start && i < atoms.size()) {
        width = atoms[i].width;
        ++i;
    }

    // Trim trailing whitespace from the line; it should not count towards width.
    std::size_t end_excl = i;
    while (end_excl > line_start && atoms[end_excl - 1].is_space) {
        width -= atoms[end_excl - 1].width;
        --end_excl;
    }

    out_end_exclusive = end_excl;
    out_width = width;

    // Advance past trailing whitespace so the next line starts cleanly.
    while (i < atoms.size() && atoms[i].is_space) ++i;
    return i;
}

LineSlice make_slice(std::string_view utf8,
                     const std::vector<Atom>& atoms,
                     std::size_t first,
                     std::size_t end_excl,
                     double width) {
    LineSlice s{};
    if (first >= atoms.size() || end_excl == first) {
        s.byte_start = first < atoms.size() ? atoms[first].byte_start : utf8.size();
        s.byte_end = s.byte_start;
        s.char_start = first < atoms.size() ? atoms[first].char_start : 0;
        s.char_length = 0;
        s.width = 0.0;
        return s;
    }
    s.byte_start = atoms[first].byte_start;
    s.byte_end = atoms[end_excl - 1].byte_end;
    s.char_start = atoms[first].char_start;
    std::size_t chars = 0;
    for (std::size_t k = first; k < end_excl; ++k) chars += atoms[k].char_count;
    s.char_length = chars;
    s.width = width;
    s.text.assign(utf8.data() + s.byte_start, s.byte_end - s.byte_start);
    return s;
}

}  // namespace

std::vector<LineSlice> LineBreaker::break_paragraph(
    std::string_view utf8,
    double font_size,
    double max_width,
    LineBreakStrategy strategy,
    double letter_spacing) {
    std::vector<LineSlice> out;
    if (utf8.empty() || max_width <= 0.0 || font_size <= 0.0) return out;

    const auto atoms = tokenize(utf8, font_size, letter_spacing);
    if (atoms.empty()) return out;

    if (strategy == LineBreakStrategy::kGreedy) {
        std::size_t i = 0;
        while (i < atoms.size()) {
            while (i < atoms.size() && atoms[i].is_space) ++i;
            if (i >= atoms.size()) break;
            const std::size_t line_first = i;

            std::size_t end_excl = line_first;
            double width = 0.0;
            i = pack_greedy(atoms, line_first, max_width, end_excl, width);
            if (end_excl <= line_first) {
                end_excl = line_first + 1;
                width = atoms[line_first].width;
                i = end_excl;
            }
            out.push_back(make_slice(utf8, atoms, line_first, end_excl, width));
        }
        return out;
    }

    // Best-fit dynamic programming: for each atom index j, compute the minimum
    // "badness" (sum of squared trailing-space) to lay out atoms[0..j-1].
    //
    // dp[j] = min over i<j of dp[i] + cost(i, j) where cost(i, j) is the
    // squared trailing space if the line packs atoms[i..j-1] (and INF if it
    // does not fit).
    const std::size_t n = atoms.size();
    std::vector<double> dp(n + 1, std::numeric_limits<double>::infinity());
    std::vector<std::size_t> prev(n + 1, 0);
    std::vector<double> line_w(n + 1, 0.0);
    dp[0] = 0.0;

    for (std::size_t i = 0; i < n; ++i) {
        if (dp[i] == std::numeric_limits<double>::infinity()) continue;
        double width = 0.0;
        for (std::size_t j = i; j < n; ++j) {
            // Skip leading whitespace on the line.
            if (j == i && atoms[j].is_space) continue;
            width += atoms[j].width;
            // Compute trimmed line width (no trailing whitespace).
            double trimmed = width;
            if (atoms[j].is_space) trimmed -= atoms[j].width;
            if (trimmed > max_width) {
                // If the FIRST atom on the line already overflows, we must
                // place it alone and continue.
                if (j == i) {
                    const double slack = 0.0;  // unavoidable overflow
                    if (dp[i] + slack < dp[j + 1]) {
                        dp[j + 1] = dp[i] + slack;
                        prev[j + 1] = i;
                        line_w[j + 1] = atoms[j].width;
                    }
                }
                break;
            }
            const double slack = max_width - trimmed;
            const bool is_last_line = (j + 1 == n);
            const double cost = is_last_line ? 0.0 : slack * slack;
            if (dp[i] + cost < dp[j + 1]) {
                dp[j + 1] = dp[i] + cost;
                prev[j + 1] = i;
                line_w[j + 1] = trimmed;
            }
        }
    }

    // Reconstruct line boundaries.
    std::vector<std::size_t> breaks;
    breaks.push_back(n);
    for (std::size_t j = n; j > 0; j = prev[j]) breaks.push_back(prev[j]);
    std::reverse(breaks.begin(), breaks.end());

    out.reserve(breaks.size() > 1 ? breaks.size() - 1 : 0);
    for (std::size_t k = 0; k + 1 < breaks.size(); ++k) {
        std::size_t first = breaks[k];
        const std::size_t end_excl = breaks[k + 1];
        // Skip leading whitespace.
        while (first < end_excl && atoms[first].is_space) ++first;
        if (first >= end_excl) continue;
        out.push_back(make_slice(utf8, atoms, first, end_excl, line_w[end_excl]));
    }
    return out;
}

}  // namespace readmigo::typesetting
