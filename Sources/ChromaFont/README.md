# Bundled font

Chroma uses **one** text font: a rasterized subset of Noto Sans Mono Regular
2.007, with a 12-point monospace advance. There is no font-face selector.
Generated terminal and interface symbols supplement the font, not a second
ASCII alphabet.
There is no runtime font lookup or font rasterizer dependency.

## License and provenance

The font and derived bitmap coverage are distributed under **SIL OFL 1.1**.
The exact TTF embeds `Copyright 2015-2021 Google LLC. All Rights Reserved.`
and explicitly states SIL OFL 1.1. The upstream repository also includes the
Noto Project Authors copyright notice. Both are preserved with the full license
in [Resources/OFL.txt](Resources/OFL.txt), copied into ChromaFont's SwiftPM
resource bundle. Applications must ship that bundle (or an accessible copy of
the notice and license) with distributed binaries. This does not license the
application itself under OFL. No Reserved Font Names are specified in the
source copyright notices.

Pinned upstream revision: `ffebf8c1ee449e544955a7e813c54f9b73848eac`.

- [Original TTF](https://raw.githubusercontent.com/notofonts/noto-fonts/ffebf8c1ee449e544955a7e813c54f9b73848eac/hinted/ttf/NotoSansMono/NotoSansMono-Regular.ttf)
- [Upstream license](https://raw.githubusercontent.com/notofonts/noto-fonts/ffebf8c1ee449e544955a7e813c54f9b73848eac/LICENSE)
- TTF SHA-256: `d9e2b23d19f8230be7146f409a52b1d23117e635e28f2e2892cf91b7382f325b`

## Static shared atlas

`Resources/FontAtlas.atlas` is the finished font asset, checked into source control.
Metal and OpenGL ES load the same character mapping, grayscale pixels, and mipmaps.
Normal builds only copy the asset into the ChromaFont resource bundle. Runtime
loads and validates it once and uploads the textures. There is no font build
plugin, rasterization tool, FreeType, HarfBuzz, Python, or font lookup dependency.
Backend shader compilation remains separate from the font asset: Metal uses MSL
and OpenGL ES uses GLSL, both sampling this same grayscale coverage.

The asset contains 762 glyphs and a full mip chain, approximately 6.1 MB. Its Noto
coverage was rendered once from the pinned TTF above at 60 px, baseline 65, on
60×84 canvases with 36 px advance. All 190 accented letters are native Noto glyphs,
not synthetic accents. Negative left bearings were accommodated by translating
whole glyphs right to preserve their ink. Terminal/interface symbols are baked
into the same texture. The prior construction tools have been removed.

This is intentionally a fixed font asset, not a font-generation pipeline. Changing
the font or repertoire requires supplying a replacement asset in the format below.
Tests pin the existing mapping/pixels and check lookup, accents, fallback, mip
shape, symbol continuity, and malformed-resource handling. Preserve the OFL notice
and update provenance and regression expectations when replacing the asset.

## Binary formats

`FontAtlas.atlas` is a small Chroma-specific format, not a property list.
All integers are unsigned 32-bit little-endian:

1. Four magic bytes `CATL`.
2. Version (`1`), base texture width, base texture height, glyph count.
3. One Unicode scalar per glyph, in cell-index order.
4. Raw row-major 8-bit coverage for the base level and every mip level, down to
   1×1. Each successive dimension is `max(1, previous / 2)` with integer division.

Version 1 uses 32 columns, 60×84 glyphs, and three pixels of padding per side.
No per-level dimensions, compression, or trailing bytes are stored. The loader
checks version, dimensions, lengths, scalar validity and uniqueness, and the
presence of the replacement glyph. Character keys preserve canonical equality.

The loader borrows the input `Data` through `RawSpan` and uses Swift 6.4's
endian-aware integer loads, avoiding a whole-asset `[UInt8]` copy. Length checks
precede each load so malformed assets throw `AssetError` rather than triggering
a bounds trap. Each mip still owns its pixel array after parsing; no borrowed
storage escapes the input's lifetime. `ChromaFont`, `Chroma`, and `RemoteProtocol`
enable Swift's strict memory-safety diagnostics.

## Latin accents

All 190 supported accented letters now use Noto's actual complete glyph designs.
There are no authored accent patterns, dot-removal rules, or synthetic base-letter
compression. The repertoire retains the existing ASCII-letter + single supported
mark combinations within U+00C0–U+024F; stacked accents remain unsupported.

Swift `Character` equality maps precomposed and canonically equivalent decomposed
spellings to the same cell without rewriting application text, including `café`,
`Ångström`, `naïve`, `façade`, and `Český`. Advances remain unchanged at 12 logical
points. Terminal and interface symbols still use the separate generated designs.

## Explicit limitations

This is not general Unicode shaping. Unsupported base/mark combinations,
stacked accents, isolated marks, emoji sequences, and unsupported scripts still
use a visible replacement glyph. Marks are never silently discarded. Greek,
Cyrillic, CJK/wide-cell layout, bidi, and contextual shaping are not added by
this change. Additional bitmap coverage and a positioned-glyph interface can be
introduced incrementally when those features are implemented.
