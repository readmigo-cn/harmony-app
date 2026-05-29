#include "napi_bindings.h"

#include <cstring>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

#include "text_layout.h"

namespace readmigo::napi {

using readmigo::typesetting::ChapterAnchor;
using readmigo::typesetting::HitResult;
using readmigo::typesetting::LayoutSummary;
using readmigo::typesetting::TextLine;
using readmigo::typesetting::TextRun;
using readmigo::typesetting::TypesetPage;
using readmigo::typesetting::TypesettingEngine;

namespace {

// ---------- Helpers ----------

void throw_error(napi_env env, const char* code, const char* msg) {
    napi_throw_error(env, code, msg);
}

bool get_string_utf8(napi_env env, napi_value v, std::string& out) {
    size_t len = 0;
    if (napi_get_value_string_utf8(env, v, nullptr, 0, &len) != napi_ok) return false;
    out.resize(len);
    size_t written = 0;
    if (napi_get_value_string_utf8(env, v, out.data(), len + 1, &written) != napi_ok) return false;
    out.resize(written);
    return true;
}

bool get_double(napi_env env, napi_value v, double& out) {
    return napi_get_value_double(env, v, &out) == napi_ok;
}

bool get_int32(napi_env env, napi_value v, int32_t& out) {
    return napi_get_value_int32(env, v, &out) == napi_ok;
}

napi_value make_string(napi_env env, const std::string& s) {
    napi_value v = nullptr;
    napi_create_string_utf8(env, s.c_str(), s.size(), &v);
    return v;
}

napi_value make_int(napi_env env, int32_t i) {
    napi_value v = nullptr;
    napi_create_int32(env, i, &v);
    return v;
}

napi_value make_double(napi_env env, double d) {
    napi_value v = nullptr;
    napi_create_double(env, d, &v);
    return v;
}

void set_prop(napi_env env, napi_value obj, const char* key, napi_value value) {
    napi_set_named_property(env, obj, key, value);
}

// ---------- JSON serialisation (avoid pulling in a heavy lib) ----------

void json_escape(const std::string& in, std::string& out) {
    out.push_back('"');
    for (char c : in) {
        switch (c) {
            case '"':  out.append("\\\""); break;
            case '\\': out.append("\\\\"); break;
            case '\b': out.append("\\b"); break;
            case '\f': out.append("\\f"); break;
            case '\n': out.append("\\n"); break;
            case '\r': out.append("\\r"); break;
            case '\t': out.append("\\t"); break;
            default:
                if (static_cast<unsigned char>(c) < 0x20) {
                    char buf[8];
                    std::snprintf(buf, sizeof(buf), "\\u%04x", static_cast<unsigned>(c));
                    out.append(buf);
                } else {
                    out.push_back(c);
                }
                break;
        }
    }
    out.push_back('"');
}

void serialize_run(const TextRun& run, std::string& out) {
    out.push_back('{');
    out.append("\"x\":");           out.append(std::to_string(run.x));
    out.append(",\"y\":");          out.append(std::to_string(run.y));
    out.append(",\"w\":");          out.append(std::to_string(run.w));
    out.append(",\"fontSize\":");   out.append(std::to_string(run.font_size));
    out.append(",\"blockIndex\":"); out.append(std::to_string(run.block_index));
    out.append(",\"inlineIndex\":");out.append(std::to_string(run.inline_index));
    out.append(",\"charOffset\":"); out.append(std::to_string(run.char_offset));
    out.append(",\"charLength\":"); out.append(std::to_string(run.char_length));
    out.append(",\"isLink\":");     out.append(run.is_link ? "true" : "false");
    out.append(",\"text\":");       json_escape(run.text, out);
    out.push_back('}');
}

void serialize_line(const TextLine& line, std::string& out) {
    out.push_back('{');
    out.append("\"x\":");        out.append(std::to_string(line.x));
    out.append(",\"y\":");       out.append(std::to_string(line.y));
    out.append(",\"w\":");       out.append(std::to_string(line.w));
    out.append(",\"h\":");       out.append(std::to_string(line.h));
    out.append(",\"ascent\":");  out.append(std::to_string(line.ascent));
    out.append(",\"descent\":"); out.append(std::to_string(line.descent));
    out.append(",\"runs\":[");
    for (std::size_t i = 0; i < line.runs.size(); ++i) {
        if (i > 0) out.push_back(',');
        serialize_run(line.runs[i], out);
    }
    out.append("]}");
}

std::string serialize_page(const TypesetPage& page) {
    std::string out;
    out.reserve(256 + page.lines.size() * 96);
    out.push_back('{');
    out.append("\"pageIndex\":");      out.append(std::to_string(page.page_index));
    out.append(",\"width\":");         out.append(std::to_string(page.width));
    out.append(",\"height\":");        out.append(std::to_string(page.height));
    out.append(",\"contentX\":");      out.append(std::to_string(page.content_x));
    out.append(",\"contentY\":");      out.append(std::to_string(page.content_y));
    out.append(",\"contentWidth\":");  out.append(std::to_string(page.content_width));
    out.append(",\"contentHeight\":"); out.append(std::to_string(page.content_height));
    out.append(",\"firstBlockIndex\":");out.append(std::to_string(page.first_block_index));
    out.append(",\"lastBlockIndex\":");out.append(std::to_string(page.last_block_index));
    out.append(",\"lines\":[");
    for (std::size_t i = 0; i < page.lines.size(); ++i) {
        if (i > 0) out.push_back(',');
        serialize_line(page.lines[i], out);
    }
    out.append("],\"decorations\":[]}");
    return out;
}

std::string serialize_anchors(const std::vector<ChapterAnchor>& anchors) {
    std::string out;
    out.push_back('[');
    for (std::size_t i = 0; i < anchors.size(); ++i) {
        if (i > 0) out.push_back(',');
        out.push_back('{');
        out.append("\"pageIndex\":");       out.append(std::to_string(anchors[i].page_index));
        out.append(",\"firstBlockIndex\":");out.append(std::to_string(anchors[i].first_block_index));
        out.append(",\"lastBlockIndex\":"); out.append(std::to_string(anchors[i].last_block_index));
        out.push_back('}');
    }
    out.push_back(']');
    return out;
}

std::string serialize_hit(const HitResult& hit) {
    std::string out;
    out.push_back('{');
    out.append("\"blockIndex\":");  out.append(std::to_string(hit.block_index));
    out.append(",\"inlineIndex\":");out.append(std::to_string(hit.inline_index));
    out.append(",\"charOffset\":"); out.append(std::to_string(hit.char_offset));
    out.append(",\"charLength\":"); out.append(std::to_string(hit.char_length));
    out.append(",\"text\":");       json_escape(hit.text, out);
    out.push_back('}');
    return out;
}

// ---------- Engine handle management ----------
//
// We wrap each TypesettingEngine in a napi_external so the JS side gets an
// opaque handle. The finalizer deletes the engine when JS drops the handle.

void engine_finalizer(napi_env /*env*/, void* data, void* /*hint*/) {
    delete static_cast<TypesettingEngine*>(data);
}

TypesettingEngine* unwrap_engine(napi_env env, napi_value v) {
    void* raw = nullptr;
    if (napi_get_value_external(env, v, &raw) != napi_ok) return nullptr;
    return static_cast<TypesettingEngine*>(raw);
}

// ---------- Function implementations ----------

napi_value CreateEngine(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    readmigo::typesetting::LayoutOptions opts;
    if (argc >= 1) {
        napi_valuetype t;
        napi_typeof(env, argv[0], &t);
        if (t == napi_object) {
            napi_value fs_v = nullptr;
            if (napi_get_named_property(env, argv[0], "fontScale", &fs_v) == napi_ok) {
                napi_valuetype tt;
                napi_typeof(env, fs_v, &tt);
                if (tt == napi_number) {
                    double scale = 1.0;
                    if (get_double(env, fs_v, scale) && scale > 0.0) {
                        opts.font_size *= scale;
                    }
                }
            }
            napi_value lh_v = nullptr;
            if (napi_get_named_property(env, argv[0], "lineHeightMultiplier", &lh_v) == napi_ok) {
                napi_valuetype tt;
                napi_typeof(env, lh_v, &tt);
                if (tt == napi_number) get_double(env, lh_v, opts.line_height_multiplier);
            }
        }
    }

    auto* engine = new TypesettingEngine(opts);
    napi_value handle = nullptr;
    if (napi_create_external(env, engine, engine_finalizer, nullptr, &handle) != napi_ok) {
        delete engine;
        throw_error(env, "ENGINE_INIT_FAILED", "napi_create_external failed");
        return nullptr;
    }
    return handle;
}

napi_value DestroyEngine(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    // Destruction is handled by the finalizer when JS drops its reference; the
    // explicit call is a no-op kept for API symmetry with the ArkTS bridge.
    napi_value undef = nullptr;
    napi_get_undefined(env, &undef);
    return undef;
}

napi_value LayoutHtml(napi_env env, napi_callback_info info) {
    size_t argc = 6;
    napi_value argv[6] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 5) {
        throw_error(env, "INVALID_ARGS", "layoutHtml requires (handle, html, chapterId, width, height, [fontSize])");
        return nullptr;
    }
    TypesettingEngine* engine = unwrap_engine(env, argv[0]);
    if (engine == nullptr) {
        throw_error(env, "INVALID_HANDLE", "engine handle is not an external");
        return nullptr;
    }
    std::string html;
    std::string chapter;
    if (!get_string_utf8(env, argv[1], html) || !get_string_utf8(env, argv[2], chapter)) {
        throw_error(env, "INVALID_ARGS", "html / chapterId must be strings");
        return nullptr;
    }
    double w = 0.0;
    double h = 0.0;
    if (!get_double(env, argv[3], w) || !get_double(env, argv[4], h)) {
        throw_error(env, "INVALID_ARGS", "width / height must be numbers");
        return nullptr;
    }
    double fs = 0.0;
    if (argc >= 6) {
        napi_valuetype t;
        napi_typeof(env, argv[5], &t);
        if (t == napi_number) get_double(env, argv[5], fs);
    }
    LayoutSummary summary = engine->layout_html(html, chapter, w, h, fs);

    napi_value out = nullptr;
    napi_create_object(env, &out);
    set_prop(env, out, "pageCount",    make_int(env, summary.page_count));
    set_prop(env, out, "totalBlocks",  make_int(env, summary.total_blocks));
    set_prop(env, out, "warningCount", make_int(env, summary.warning_count));
    return out;
}

napi_value GetPageJson(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value argv[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 3) {
        throw_error(env, "INVALID_ARGS", "getPageJson requires (handle, chapterId, pageIndex)");
        return nullptr;
    }
    TypesettingEngine* engine = unwrap_engine(env, argv[0]);
    if (engine == nullptr) return nullptr;
    std::string chapter;
    if (!get_string_utf8(env, argv[1], chapter)) return nullptr;
    int32_t page_idx = 0;
    if (!get_int32(env, argv[2], page_idx)) return nullptr;

    const TypesetPage* p = engine->get_page(chapter, page_idx);
    if (p == nullptr) {
        napi_value n = nullptr;
        napi_get_null(env, &n);
        return n;
    }
    return make_string(env, serialize_page(*p));
}

napi_value GetChapterAnchorsJson(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 2) {
        throw_error(env, "INVALID_ARGS", "getChapterAnchorsJson requires (handle, chapterId)");
        return nullptr;
    }
    TypesettingEngine* engine = unwrap_engine(env, argv[0]);
    if (engine == nullptr) return nullptr;
    std::string chapter;
    if (!get_string_utf8(env, argv[1], chapter)) return nullptr;
    const auto anchors = engine->get_anchors(chapter);
    if (anchors.empty()) {
        napi_value n = nullptr;
        napi_get_null(env, &n);
        return n;
    }
    return make_string(env, serialize_anchors(anchors));
}

napi_value HitTestJson(napi_env env, napi_callback_info info) {
    size_t argc = 5;
    napi_value argv[5] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 5) {
        throw_error(env, "INVALID_ARGS", "hitTestJson requires (handle, chapterId, pageIndex, x, y)");
        return nullptr;
    }
    TypesettingEngine* engine = unwrap_engine(env, argv[0]);
    if (engine == nullptr) return nullptr;
    std::string chapter;
    if (!get_string_utf8(env, argv[1], chapter)) return nullptr;
    int32_t page_idx = 0;
    if (!get_int32(env, argv[2], page_idx)) return nullptr;
    double x = 0.0;
    double y = 0.0;
    if (!get_double(env, argv[3], x) || !get_double(env, argv[4], y)) return nullptr;

    HitResult hit{};
    if (!engine->hit_test(chapter, page_idx, x, y, hit)) {
        napi_value n = nullptr;
        napi_get_null(env, &n);
        return n;
    }
    return make_string(env, serialize_hit(hit));
}

}  // namespace

napi_value RegisterTypesettingModule(napi_env env, napi_value exports) {
    napi_value sub = nullptr;
    napi_create_object(env, &sub);

    napi_property_descriptor descs[] = {
        {"createTypesettingEngine",  nullptr, CreateEngine,           nullptr, nullptr, nullptr, napi_default, nullptr},
        {"destroyTypesettingEngine", nullptr, DestroyEngine,          nullptr, nullptr, nullptr, napi_default, nullptr},
        {"layoutHtml",               nullptr, LayoutHtml,             nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getPageJson",              nullptr, GetPageJson,            nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getChapterAnchorsJson",    nullptr, GetChapterAnchorsJson,  nullptr, nullptr, nullptr, napi_default, nullptr},
        {"hitTestJson",              nullptr, HitTestJson,            nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, sub, sizeof(descs) / sizeof(descs[0]), descs);

    napi_set_named_property(env, exports, "typesetting", sub);
    return exports;
}

}  // namespace readmigo::napi

// ---------- Module init ----------
//
// Use the NAPI_MODULE macro shared by both the HarmonyOS NDK and the local
// stub header — that way we don't need to track struct-field layout changes.

extern "C" napi_value ReadmigoNativeInit(napi_env env, napi_value exports) {
    return readmigo::napi::RegisterTypesettingModule(env, exports);
}

NAPI_MODULE(libreadmigo_native, ReadmigoNativeInit)
