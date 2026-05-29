#pragma once

#include <cstddef>
#include <memory>
#include <mutex>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

#include "line_break.h"

namespace readmigo::typesetting {

// A page-level "run" — one slice of source text on one line.
struct TextRun {
    double x;
    double y;             // baseline y
    double w;
    double font_size;
    int block_index;
    int inline_index;
    int char_offset;
    int char_length;
    bool is_link;
    std::string text;
};

struct TextLine {
    double x;
    double y;              // baseline y
    double w;
    double h;              // total line height
    double ascent;
    double descent;
    std::vector<TextRun> runs;
};

struct PageDecoration {
    std::string type;      // "hr" | "img" | "table"
    double x;
    double y;
    double w;
    double h;
    std::string src;
    std::string alt;
};

struct TypesetPage {
    int page_index;
    double width;
    double height;
    double content_x;
    double content_y;
    double content_width;
    double content_height;
    int first_block_index;
    int last_block_index;
    std::vector<TextLine> lines;
    std::vector<PageDecoration> decorations;
};

struct ChapterAnchor {
    int page_index;
    int first_block_index;
    int last_block_index;
};

struct LayoutSummary {
    int page_count;
    int total_blocks;
    int warning_count;
};

struct HitResult {
    int block_index;
    int inline_index;
    int char_offset;
    int char_length;
    std::string text;
};

struct LayoutOptions {
    double font_size = 17.0;
    double line_height_multiplier = 1.6;
    double margin = 24.0;
    double letter_spacing = 0.0;
    LineBreakStrategy strategy = LineBreakStrategy::kGreedy;
    std::string locale = "zh-CN";
};

// One in-memory layout result for a chapter; keyed by chapterId in the engine.
struct LayoutResult {
    std::vector<TypesetPage> pages;
    LayoutSummary summary;
};

// The engine. Holds layout results for up to kMaxChapters chapters (LRU eviction).
// All public methods are thread-safe for concurrent reads after the chapter has
// been laid out; concurrent writes (layoutHtml) are serialised internally.
class TypesettingEngine {
public:
    static constexpr std::size_t kMaxChapters = 5;

    explicit TypesettingEngine(LayoutOptions defaults = {});

    // Strip HTML tags to plain paragraphs, run line-breaking + pagination,
    // and cache the result under `chapter_id`. Returns the summary.
    LayoutSummary layout_html(std::string_view html,
                              std::string_view chapter_id,
                              double page_width,
                              double page_height,
                              double font_size_override = 0.0);

    // Read-only accessors — return nullptr if chapter or page is missing.
    const TypesetPage* get_page(std::string_view chapter_id, int page_index) const;
    std::vector<ChapterAnchor> get_anchors(std::string_view chapter_id) const;

    // Hit-test: find the (block, char) under (x, y). Returns nullopt on miss.
    bool hit_test(std::string_view chapter_id,
                  int page_index,
                  double x,
                  double y,
                  HitResult& out) const;

    // Width-only convenience for ArkUI sizing.
    static double measure_text(std::string_view utf8,
                               double font_size,
                               double letter_spacing = 0.0);

private:
    // Paragraphs extracted from input HTML.
    struct Paragraph {
        std::string text;
        bool is_heading;
    };

    static std::vector<Paragraph> extract_paragraphs(std::string_view html);
    static HitResult find_word_bounds(const TextRun& run, int char_index_in_run);

    void evict_if_needed_unsafe();

    LayoutOptions defaults_;
    mutable std::mutex mutex_;
    std::unordered_map<std::string, LayoutResult> chapters_;
    std::vector<std::string> lru_order_;  // back = most recently used
};

}  // namespace readmigo::typesetting
