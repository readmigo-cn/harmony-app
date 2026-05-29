#include "text_layout.h"

#include <algorithm>
#include <cctype>
#include <cmath>

#include "glyph_metrics.h"
#include "utf8.h"

namespace readmigo::typesetting {

namespace {

void append_decoded_entity(std::string_view name, std::string& out) {
    if (name == "amp") { out.push_back('&'); return; }
    if (name == "lt")  { out.push_back('<'); return; }
    if (name == "gt")  { out.push_back('>'); return; }
    if (name == "quot"){ out.push_back('"'); return; }
    if (name == "apos"){ out.push_back('\''); return; }
    if (name == "nbsp"){ out.push_back(' '); return; }
    // Unknown entity: leave the source as-is to avoid silent data loss.
    out.push_back('&');
    out.append(name.data(), name.size());
    out.push_back(';');
}

std::string strip_entities(std::string_view text) {
    std::string out;
    out.reserve(text.size());
    for (std::size_t i = 0; i < text.size(); ) {
        if (text[i] == '&') {
            const std::size_t semi = text.find(';', i + 1);
            if (semi != std::string_view::npos && semi - i <= 8) {
                append_decoded_entity(text.substr(i + 1, semi - i - 1), out);
                i = semi + 1;
                continue;
            }
        }
        out.push_back(text[i]);
        ++i;
    }
    return out;
}

bool tag_is_block(std::string_view tag_lower) {
    static const char* kBlock[] = {
        "p", "div", "h1", "h2", "h3", "h4", "h5", "h6",
        "li", "blockquote", "pre", "hr", "br", "section",
        "article", "header", "footer", "tr",
    };
    for (auto* t : kBlock) {
        if (tag_lower == t) return true;
    }
    return false;
}

bool tag_is_heading(std::string_view tag_lower) {
    return tag_lower.size() == 2 && tag_lower[0] == 'h' &&
           tag_lower[1] >= '1' && tag_lower[1] <= '6';
}

std::string to_lower(std::string_view s) {
    std::string out(s);
    for (auto& c : out) {
        c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    }
    return out;
}

}  // namespace

TypesettingEngine::TypesettingEngine(LayoutOptions defaults) : defaults_(defaults) {}

std::vector<TypesettingEngine::Paragraph> TypesettingEngine::extract_paragraphs(std::string_view html) {
    std::vector<Paragraph> out;
    std::string current;
    bool current_is_heading = false;

    auto flush = [&]() {
        if (!current.empty()) {
            // Trim trailing whitespace.
            while (!current.empty() &&
                   (current.back() == ' ' || current.back() == '\n' || current.back() == '\t')) {
                current.pop_back();
            }
            if (!current.empty()) {
                Paragraph p;
                p.text = strip_entities(current);
                p.is_heading = current_is_heading;
                out.push_back(std::move(p));
            }
        }
        current.clear();
        current_is_heading = false;
    };

    std::size_t i = 0;
    while (i < html.size()) {
        if (html[i] == '<') {
            const std::size_t close = html.find('>', i + 1);
            if (close == std::string_view::npos) break;
            std::string_view tag_body = html.substr(i + 1, close - i - 1);
            // Skip <!-- comments --> and processing instructions.
            if (!tag_body.empty() && (tag_body[0] == '!' || tag_body[0] == '?')) {
                i = close + 1;
                continue;
            }
            // Extract bare tag name (drop attributes).
            std::size_t name_end = 0;
            const std::size_t name_start = (tag_body.size() > 0 && tag_body[0] == '/') ? 1 : 0;
            while (name_end + name_start < tag_body.size() &&
                   tag_body[name_start + name_end] != ' ' &&
                   tag_body[name_start + name_end] != '\t' &&
                   tag_body[name_start + name_end] != '/') {
                ++name_end;
            }
            const std::string tag_lower = to_lower(tag_body.substr(name_start, name_end));
            if (tag_is_block(tag_lower)) {
                flush();
                if (tag_is_heading(tag_lower) && name_start == 0) {
                    current_is_heading = true;
                }
            }
            i = close + 1;
            continue;
        }
        // Collapse runs of whitespace into single spaces inside a paragraph.
        if (html[i] == '\n' || html[i] == '\t' || html[i] == '\r' || html[i] == ' ') {
            if (!current.empty() && current.back() != ' ') current.push_back(' ');
            ++i;
            continue;
        }
        current.push_back(html[i]);
        ++i;
    }
    flush();
    return out;
}

LayoutSummary TypesettingEngine::layout_html(std::string_view html,
                                             std::string_view chapter_id,
                                             double page_width,
                                             double page_height,
                                             double font_size_override) {
    LayoutOptions opts = defaults_;
    if (font_size_override > 0.0) opts.font_size = font_size_override;

    const double margin = opts.margin;
    const double content_w = std::max(0.0, page_width - margin * 2.0);
    const double content_h = std::max(0.0, page_height - margin * 2.0);

    const auto paragraphs = extract_paragraphs(html);

    LayoutResult result;
    result.summary.warning_count = 0;
    result.summary.total_blocks = static_cast<int>(paragraphs.size());

    TypesetPage page{};
    auto reset_page = [&](int page_index, int first_block) {
        page = TypesetPage{};
        page.page_index = page_index;
        page.width = page_width;
        page.height = page_height;
        page.content_x = margin;
        page.content_y = margin;
        page.content_width = content_w;
        page.content_height = content_h;
        page.first_block_index = first_block;
        page.last_block_index = first_block;
    };

    int page_index = 0;
    int first_block_on_page = 0;
    reset_page(page_index, first_block_on_page);
    double cursor_y = margin;

    for (std::size_t block_idx = 0; block_idx < paragraphs.size(); ++block_idx) {
        const Paragraph& para = paragraphs[block_idx];
        const double para_fs = para.is_heading ? opts.font_size * 1.25 : opts.font_size;
        const LineMetrics lm = GlyphMetrics::line_metrics(para_fs, opts.line_height_multiplier);

        const auto slices = LineBreaker::break_paragraph(
            para.text, para_fs, content_w, opts.strategy, opts.letter_spacing);

        for (const auto& slice : slices) {
            if (cursor_y + lm.line_height > margin + content_h && !page.lines.empty()) {
                page.last_block_index = static_cast<int>(block_idx);
                result.pages.push_back(std::move(page));
                ++page_index;
                first_block_on_page = static_cast<int>(block_idx);
                reset_page(page_index, first_block_on_page);
                cursor_y = margin;
            }

            const double baseline_y = cursor_y + lm.ascent;

            TextLine line{};
            line.x = margin;
            line.y = baseline_y;
            line.w = slice.width;
            line.h = lm.line_height;
            line.ascent = lm.ascent;
            line.descent = lm.descent;

            TextRun run{};
            run.x = margin;
            run.y = baseline_y;
            run.w = slice.width;
            run.font_size = para_fs;
            run.block_index = static_cast<int>(block_idx);
            run.inline_index = 0;
            run.char_offset = static_cast<int>(slice.char_start);
            run.char_length = static_cast<int>(slice.char_length);
            run.is_link = false;
            run.text = slice.text;
            line.runs.push_back(std::move(run));

            page.lines.push_back(std::move(line));
            cursor_y += lm.line_height;
        }
        page.last_block_index = static_cast<int>(block_idx);
    }

    if (!page.lines.empty()) {
        result.pages.push_back(std::move(page));
    }

    result.summary.page_count = static_cast<int>(result.pages.size());

    {
        std::lock_guard<std::mutex> g(mutex_);
        std::string key(chapter_id);
        auto it = chapters_.find(key);
        if (it != chapters_.end()) {
            it->second = std::move(result);
            auto pos = std::find(lru_order_.begin(), lru_order_.end(), key);
            if (pos != lru_order_.end()) lru_order_.erase(pos);
            lru_order_.push_back(key);
        } else {
            chapters_.emplace(key, std::move(result));
            lru_order_.push_back(key);
            evict_if_needed_unsafe();
        }
        return chapters_.at(key).summary;
    }
}

void TypesettingEngine::evict_if_needed_unsafe() {
    while (lru_order_.size() > kMaxChapters) {
        const std::string victim = lru_order_.front();
        lru_order_.erase(lru_order_.begin());
        chapters_.erase(victim);
    }
}

const TypesetPage* TypesettingEngine::get_page(std::string_view chapter_id, int page_index) const {
    std::lock_guard<std::mutex> g(mutex_);
    auto it = chapters_.find(std::string(chapter_id));
    if (it == chapters_.end()) return nullptr;
    if (page_index < 0 || static_cast<std::size_t>(page_index) >= it->second.pages.size()) return nullptr;
    return &it->second.pages[static_cast<std::size_t>(page_index)];
}

std::vector<ChapterAnchor> TypesettingEngine::get_anchors(std::string_view chapter_id) const {
    std::lock_guard<std::mutex> g(mutex_);
    std::vector<ChapterAnchor> out;
    auto it = chapters_.find(std::string(chapter_id));
    if (it == chapters_.end()) return out;
    out.reserve(it->second.pages.size());
    for (const auto& p : it->second.pages) {
        out.push_back({p.page_index, p.first_block_index, p.last_block_index});
    }
    return out;
}

HitResult TypesettingEngine::find_word_bounds(const TextRun& run, int char_index_in_run) {
    HitResult r{};
    r.block_index = run.block_index;
    r.inline_index = run.inline_index;
    if (run.text.empty()) {
        r.char_offset = run.char_offset;
        r.char_length = 0;
        return r;
    }

    const auto code_points = utf8::decode(run.text);
    if (code_points.empty()) {
        r.char_offset = run.char_offset;
        r.char_length = 0;
        return r;
    }
    int idx = std::clamp(char_index_in_run, 0, static_cast<int>(code_points.size()) - 1);

    // CJK: select the single character.
    if (utf8::is_cjk(code_points[static_cast<std::size_t>(idx)])) {
        std::string out;
        utf8::encode_one(code_points[static_cast<std::size_t>(idx)], out);
        r.char_offset = run.char_offset + idx;
        r.char_length = 1;
        r.text = std::move(out);
        return r;
    }

    // ASCII word expansion: walk backwards/forwards across word chars.
    int start = idx;
    while (start > 0 && utf8::is_word_char(code_points[static_cast<std::size_t>(start - 1)])) --start;
    int end = idx;
    while (end + 1 < static_cast<int>(code_points.size()) &&
           utf8::is_word_char(code_points[static_cast<std::size_t>(end + 1)])) ++end;

    // If the index landed on non-word-char and no adjacent word char exists,
    // return a single-character selection.
    if (!utf8::is_word_char(code_points[static_cast<std::size_t>(idx)]) && start == end) {
        std::string out;
        utf8::encode_one(code_points[static_cast<std::size_t>(idx)], out);
        r.char_offset = run.char_offset + idx;
        r.char_length = 1;
        r.text = std::move(out);
        return r;
    }

    std::string out;
    for (int k = start; k <= end; ++k) utf8::encode_one(code_points[static_cast<std::size_t>(k)], out);
    r.char_offset = run.char_offset + start;
    r.char_length = end - start + 1;
    r.text = std::move(out);
    return r;
}

bool TypesettingEngine::hit_test(std::string_view chapter_id,
                                 int page_index,
                                 double x,
                                 double y,
                                 HitResult& out) const {
    const TypesetPage* page = get_page(chapter_id, page_index);
    if (page == nullptr) return false;
    for (const auto& line : page->lines) {
        if (y < line.y - line.ascent || y > line.y + line.descent) continue;
        for (const auto& run : line.runs) {
            if (x < run.x || x > run.x + run.w || run.w <= 0.0) continue;
            const double ratio = (x - run.x) / run.w;
            int char_idx = static_cast<int>(std::floor(ratio * static_cast<double>(run.char_length)));
            if (char_idx < 0) char_idx = 0;
            if (char_idx >= run.char_length) char_idx = std::max(0, run.char_length - 1);
            out = find_word_bounds(run, char_idx);
            return true;
        }
    }
    return false;
}

double TypesettingEngine::measure_text(std::string_view utf8_bytes,
                                       double font_size,
                                       double letter_spacing) {
    return GlyphMetrics::measure_string(utf8_bytes, font_size, letter_spacing);
}

}  // namespace readmigo::typesetting
