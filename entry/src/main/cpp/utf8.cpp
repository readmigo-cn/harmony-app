#include "utf8.h"

namespace readmigo::utf8 {

int sequence_length(unsigned char lead) noexcept {
    if ((lead & 0x80u) == 0x00u) return 1;
    if ((lead & 0xE0u) == 0xC0u) return 2;
    if ((lead & 0xF0u) == 0xE0u) return 3;
    if ((lead & 0xF8u) == 0xF0u) return 4;
    return 0;
}

char32_t decode_one(std::string_view bytes, std::size_t& pos) noexcept {
    if (pos >= bytes.size()) return 0xFFFD;
    const auto lead = static_cast<unsigned char>(bytes[pos]);
    const int len = sequence_length(lead);
    if (len == 0 || pos + static_cast<std::size_t>(len) > bytes.size()) {
        pos += 1;
        return 0xFFFD;
    }

    char32_t cp = 0;
    switch (len) {
        case 1:
            cp = lead;
            break;
        case 2:
            cp = static_cast<char32_t>(lead & 0x1Fu) << 6;
            cp |= static_cast<char32_t>(static_cast<unsigned char>(bytes[pos + 1]) & 0x3Fu);
            break;
        case 3:
            cp = static_cast<char32_t>(lead & 0x0Fu) << 12;
            cp |= static_cast<char32_t>(static_cast<unsigned char>(bytes[pos + 1]) & 0x3Fu) << 6;
            cp |= static_cast<char32_t>(static_cast<unsigned char>(bytes[pos + 2]) & 0x3Fu);
            break;
        case 4:
            cp = static_cast<char32_t>(lead & 0x07u) << 18;
            cp |= static_cast<char32_t>(static_cast<unsigned char>(bytes[pos + 1]) & 0x3Fu) << 12;
            cp |= static_cast<char32_t>(static_cast<unsigned char>(bytes[pos + 2]) & 0x3Fu) << 6;
            cp |= static_cast<char32_t>(static_cast<unsigned char>(bytes[pos + 3]) & 0x3Fu);
            break;
        default:
            break;
    }

    // Validate continuation bytes (top two bits must be 10).
    for (int i = 1; i < len; i++) {
        if ((static_cast<unsigned char>(bytes[pos + static_cast<std::size_t>(i)]) & 0xC0u) != 0x80u) {
            pos += 1;
            return 0xFFFD;
        }
    }

    pos += static_cast<std::size_t>(len);
    return cp;
}

void encode_one(char32_t cp, std::string& out) {
    if (cp > 0x10FFFFu) return;
    if (cp >= 0xD800u && cp <= 0xDFFFu) return;  // surrogate halves are invalid

    if (cp < 0x80u) {
        out.push_back(static_cast<char>(cp));
    } else if (cp < 0x800u) {
        out.push_back(static_cast<char>(0xC0u | (cp >> 6)));
        out.push_back(static_cast<char>(0x80u | (cp & 0x3Fu)));
    } else if (cp < 0x10000u) {
        out.push_back(static_cast<char>(0xE0u | (cp >> 12)));
        out.push_back(static_cast<char>(0x80u | ((cp >> 6) & 0x3Fu)));
        out.push_back(static_cast<char>(0x80u | (cp & 0x3Fu)));
    } else {
        out.push_back(static_cast<char>(0xF0u | (cp >> 18)));
        out.push_back(static_cast<char>(0x80u | ((cp >> 12) & 0x3Fu)));
        out.push_back(static_cast<char>(0x80u | ((cp >> 6) & 0x3Fu)));
        out.push_back(static_cast<char>(0x80u | (cp & 0x3Fu)));
    }
}

std::vector<char32_t> decode(std::string_view bytes) {
    std::vector<char32_t> out;
    out.reserve(bytes.size());  // upper bound: 1 cp per byte
    std::size_t pos = 0;
    while (pos < bytes.size()) {
        out.push_back(decode_one(bytes, pos));
    }
    return out;
}

std::string encode(const std::vector<char32_t>& code_points) {
    std::string out;
    out.reserve(code_points.size() * 2);
    for (auto cp : code_points) encode_one(cp, out);
    return out;
}

bool is_cjk(char32_t cp) noexcept {
    // CJK Unified Ideographs.
    if (cp >= 0x4E00u && cp <= 0x9FFFu) return true;
    // CJK Unified Ideographs Extension A.
    if (cp >= 0x3400u && cp <= 0x4DBFu) return true;
    // Hiragana / Katakana.
    if (cp >= 0x3040u && cp <= 0x30FFu) return true;
    // Hangul Syllables.
    if (cp >= 0xAC00u && cp <= 0xD7A3u) return true;
    // Halfwidth + Fullwidth forms (treated as CJK-wide for layout).
    if (cp >= 0xFF00u && cp <= 0xFFEFu) return true;
    // CJK punctuation block.
    if (cp >= 0x3000u && cp <= 0x303Fu) return true;
    return false;
}

bool is_word_char(char32_t cp) noexcept {
    if (cp >= U'A' && cp <= U'Z') return true;
    if (cp >= U'a' && cp <= U'z') return true;
    if (cp >= U'0' && cp <= U'9') return true;
    if (cp == U'\'' || cp == U'-') return true;
    return false;
}

bool is_whitespace(char32_t cp) noexcept {
    return cp == U' ' || cp == U'\t' || cp == U'\n' || cp == U'\r' || cp == 0x3000u /* IDEOGRAPHIC SPACE */;
}

bool is_no_break_before(char32_t cp) noexcept {
    // ASCII closing / sentence-final punctuation.
    switch (cp) {
        case U',': case U'.': case U';': case U':': case U'!': case U'?':
        case U')': case U']': case U'}': case U'>': case U'\'': case U'"':
            return true;
        default:
            break;
    }
    // CJK closing punctuation / quotes.
    switch (cp) {
        case 0x3001:  // 、
        case 0x3002:  // 。
        case 0xFF0C:  // ，
        case 0xFF0E:  // ．
        case 0xFF1B:  // ；
        case 0xFF1A:  // ：
        case 0xFF01:  // ！
        case 0xFF1F:  // ？
        case 0xFF09:  // ）
        case 0xFF3D:  // ］
        case 0xFF5D:  // ｝
        case 0x300B:  // 》
        case 0x300D:  // 」
        case 0x300F:  // 』
        case 0x3011:  // 】
            return true;
        default:
            return false;
    }
}

bool is_no_break_after(char32_t cp) noexcept {
    switch (cp) {
        case U'(': case U'[': case U'{': case U'<':
            return true;
        default:
            break;
    }
    switch (cp) {
        case 0xFF08:  // （
        case 0xFF3B:  // ［
        case 0xFF5B:  // ｛
        case 0x300A:  // 《
        case 0x300C:  // 「
        case 0x300E:  // 『
        case 0x3010:  // 【
            return true;
        default:
            return false;
    }
}

}  // namespace readmigo::utf8
