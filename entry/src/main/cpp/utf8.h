#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace readmigo::utf8 {

// Decode a single UTF-8 code point starting at bytes[pos]. On success, returns
// the code point and advances pos past it. On malformed input, returns U+FFFD
// and advances pos by 1 byte (the lenient policy used for typesetting fallback).
char32_t decode_one(std::string_view bytes, std::size_t& pos) noexcept;

// Encode a code point into the back of `out`. No-op for invalid code points
// (> 0x10FFFF or surrogate halves).
void encode_one(char32_t cp, std::string& out);

// Decode an entire UTF-8 byte sequence into a vector of code points.
std::vector<char32_t> decode(std::string_view bytes);

// Encode a vector of code points back to UTF-8.
std::string encode(const std::vector<char32_t>& code_points);

// Byte length (1..4) of the UTF-8 sequence whose lead byte is `lead`.
// Returns 0 for an invalid continuation byte.
int sequence_length(unsigned char lead) noexcept;

// True if cp is in the CJK Unified Ideographs range (plus common Kana / Hangul
// ranges) — used by the line breaker to decide character-vs-word breaking.
bool is_cjk(char32_t cp) noexcept;

// True for ASCII letters / digits (the "word character" set for word breaking).
bool is_word_char(char32_t cp) noexcept;

// True for space / tab / newline (used by word breaker).
bool is_whitespace(char32_t cp) noexcept;

// True for punctuation that must NOT appear at the start of a line.
// Example: 。 ， ） 」 ！ ？ . , ) ] etc.
bool is_no_break_before(char32_t cp) noexcept;

// True for punctuation that must NOT appear at the end of a line.
// Example: （ 「 ( [ etc.
bool is_no_break_after(char32_t cp) noexcept;

}  // namespace readmigo::utf8
