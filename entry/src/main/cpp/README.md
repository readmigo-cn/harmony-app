# libreadmigo_native — typesetting native module (W3 baseline)

The shared library `libreadmigo_native.so` is the C++ typesetting engine that
ArkTS loads via `requireNapi('libreadmigo_native.so').typesetting`. The
TypeScript wrapper lives at
`entry/src/main/ets/core/native/typesetting.ets` and degrades to an in-process
mock when the `.so` is absent.

## Source layout

```
cpp/
├── CMakeLists.txt        — NDK entry; produces libreadmigo_native.so for arm64-v8a
├── napi_bindings.{h,cpp} — NAPI module registration + JS<->C++ glue
├── text_layout.{h,cpp}   — TypesettingEngine: paragraph extraction, pagination, hit-test, LRU chapter cache
├── line_break.{h,cpp}    — Greedy + best-fit line breaker (CJK char-break + ASCII word-break)
├── glyph_metrics.{h,cpp} — Per-glyph width heuristic table (CJK = font_size, ASCII = font_size * 0.55, narrow/wide overrides)
├── utf8.{h,cpp}          — UTF-8 decode/encode + CJK / word-char / no-break-before/after predicates
└── README.md             — this file
```

## Exported NAPI surface

All exports live under the `typesetting` sub-object on the module:

| Function | Signature | Returns |
| --- | --- | --- |
| `createTypesettingEngine` | `(config?: { fontScale?: number; lineHeightMultiplier?: number }) → external` | opaque engine handle (GC-finalised) |
| `destroyTypesettingEngine` | `(handle: external) → void` | no-op; finalizer handles cleanup |
| `layoutHtml` | `(handle, html: string, chapterId: string, w: number, h: number, fontSize?: number) → { pageCount, totalBlocks, warningCount }` | layout summary |
| `getPageJson` | `(handle, chapterId: string, pageIndex: number) → string \| null` | JSON-serialised `TypesetPage` (see ArkTS bridge for shape) |
| `getChapterAnchorsJson` | `(handle, chapterId: string) → string \| null` | JSON-serialised `ChapterAnchor[]` |
| `hitTestJson` | `(handle, chapterId: string, pageIndex: number, x: number, y: number) → string \| null` | JSON-serialised `HitResult` |

The JSON shapes match the ArkTS interface declarations in
`typesetting.ets`. JSON is used (instead of structured `napi_value` objects)
to keep the bridge simple and the cache layer in ArkTS uniform; the encoder
is hand-rolled — no external JSON dependency.

## Algorithms

### Line breaking (`line_break.cpp`)

1. **Tokenise** the paragraph into atoms.
   * ASCII / Latin: each run of word-chars (letters / digits / `'-`) is one atom.
   * CJK: every code point is its own atom (per-char breaking).
   * Whitespace: collapsed into single synthetic gap atoms; trimmed at line edges.
2. **Greedy fit** (`kGreedy`): pack atoms left-to-right until the next atom would overflow.
3. **Best fit** (`kBestFit`): O(n²) DP minimising `sum_i (max_width − line_width_i)²` for all but the last line. Falls back to greedy for atoms larger than the line.
4. **No-break-before / no-break-after** rules: closing punctuation (`。 ， ） 」 . , )` etc.) cannot start a line; opening punctuation (`（ 「 (`) cannot end one. The breaker glues the offending atom to its neighbour even if that causes a controlled overflow.

### Pagination (`text_layout.cpp`)

* `extract_paragraphs` strips HTML tags into a list of `(text, is_heading)` paragraphs. Block-level tags trigger a paragraph boundary; inline tags are dropped. HTML entities (`&amp; &lt; &gt; &quot; &apos; &nbsp;`) are decoded.
* For each paragraph, the line breaker emits `LineSlice`s of width ≤ `pageWidth − 2·margin`.
* Lines flow down the page. When the next line would exceed `pageHeight − 2·margin`, the current page is emitted and a fresh one begins.
* Headings (`h1..h6`) use 1.25× the body font size.
* Up to `kMaxChapters` (5) layout results are retained per engine in an LRU cache.

### Hit-test

`hit_test` walks lines / runs to find one whose bounding box contains `(x, y)`, then runs `find_word_bounds` on the run:

* CJK code point → select the single character.
* ASCII word char → expand left/right while neighbours are word chars.
* Non-word char without adjacent word → select the single character.

Returned coordinates are paragraph-relative: `charOffset` is the code-point
offset within the source block, **not** within the run.

## NAPI header and library resolution

CMakeLists.txt uses `OHOS_SDK_NATIVE_ROOT` (set automatically by DevEco/hvigorw) to
switch between the two compile environments:

| Environment | `OHOS_SDK_NATIVE_ROOT` | NAPI headers | `libace_napi.z.so` |
|---|---|---|---|
| DevEco / hvigorw | set | `<sdk>/native/sysroot/usr/include` | linked; resolved by HarmonyOS dynamic linker at runtime |
| Local desktop (CLion / CLI) | not set | `napi-bridge/stubs/` | **not linked** — link fails on purpose; `.o` compilation succeeds |

The stub headers at `napi-bridge/stubs/napi/` declare the NAPI ABI so sources
compile locally without the full SDK. The dynamic link step fails because no
stub `.so` exists — this is expected and caught by `cmake --build . -- -k`
(continue-on-error). On-device, `libace_napi.z.so` is a system library; it does
**not** need to be bundled inside the HAP.

## Building

### Production (DevEco Studio)

DevEco's hvigorw drives CMake automatically:

```bash
hvigorw --mode module -p module=entry@default -p product=default assembleHap
```

This passes `-DCMAKE_TOOLCHAIN_FILE=<sdk>/native/build/cmake/ohos.toolchain.cmake`
and `-DOHOS_ARCH=arm64-v8a`. The resulting `libreadmigo_native.so` lands in
`entry/libs/arm64-v8a/` and is packaged into the HAP.

To force a clean native rebuild from the CLI:

```bash
hvigorw clean :entry:default@CompileBuildNativeWithCmake
hvigorw :entry:default@CompileBuildNativeWithCmake
```

### Local desktop (sanity checks only)

There is no off-device runtime for `libace_napi.z.so`, but the sources compile
against the in-repo stub headers at `napi-bridge/stubs/napi/`. This catches
syntax errors and warning regressions before pushing to CI:

```bash
mkdir -p build && cd build
cmake ../entry/src/main/cpp -DCMAKE_BUILD_TYPE=Debug
cmake --build . -- -k 2>&1 | grep -E 'warning|error'
```

Compilation produces five clean `.o` files (zero warnings under
`-Wall -Wextra -Wpedantic`). The final `.so` link fails locally because the
stub provides no `napi_*` implementations — that is expected. On-device, the
HarmonyOS dynamic linker resolves these symbols against `libace_napi.z.so`.

## Known limitations (W3)

* **Width estimation is heuristic.** No freetype / harfbuzz; widths come from a hard-coded table. Tracking + kerning are ignored. Expect 5–10% drift vs the real glyph cache. W5 will integrate the HarmonyOS Drawing API.
* **No bidi support.** Right-to-left scripts (Arabic, Hebrew) will lay out visually left-to-right.
* **No inline styles.** Bold / italic / link / colour runs are not yet propagated through to `TextRun`. Every run is emitted with `isLink = false`. The W4 milestone wires inline runs from a richer DOM walker.
* **No image / table / hr layout.** `PageDecoration` is reserved in the schema but the W3 engine emits an empty `decorations` array.
* **Single-column only.** No multi-column or footnote layout.

## Thread safety

The engine serialises `layout_html` with an internal mutex. Read methods
(`get_page`, `get_anchors`, `hit_test`, `measure_text`) take the same lock;
concurrent readers therefore queue, but the workload (small page lookups) is
fast enough that the simpler model wins over a reader-writer lock at this
scale. Revisit if profiling shows contention.

Static lookup tables (`utf8::is_cjk`, `GlyphMetrics::advance_width`) are pure
functions and require no synchronisation.
