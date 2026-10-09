# ChromaFont

Noto Sans Mono Regular 2.007 rasterized subset with generated symbols.
SIL OFL 1.1: distribute [Resources/OFL.txt](Resources/OFL.txt) with the atlas.

Regenerate ≈, ✘, and the monochrome 👍 with `swift Tools/add-missing-glyphs.swift` from the repository root.

## Missing-glyph diagnostics

Fallback rendering always uses the same replacement glyph. By default, a process reports each
missing scalar-prefix signature once, with a lifetime limit of 64 distinct signatures plus one
suppression notice. Each signature includes at most 16 Unicode scalars; longer grapheme clusters
are marked `truncated=true` and deduplicated by that prefix. This bounds both diagnostic memory
and log volume, including pathological grapheme clusters and many-distinct input. Only code
points are reported, never surrounding text.

The built-in sink writes asynchronously to stderr. A stalled reader does not hold the drawing
thread or diagnostic state lock. At most 65 output records can be queued per bounded instance;
diagnostics are best effort and may not finish before process exit. Concurrent diagnostic order
is unspecified. No periodic reset occurs: a later new glyph can be suppressed after the lifetime
budget is exhausted.

Set `CHROMA_MISSING_GLYPH_WARNINGS=off` or `CHROMA_MISSING_GLYPH_WARNINGS=verbose` before creating the first
atlas or accessing `MissingGlyphWarnings.shared` to disable diagnostics or retain the original full, per-occurrence codepoint detail.
Unset or unknown values choose the bounded default. Verbose mode is explicitly unbounded; use it
only for short debugging sessions with a consuming stderr reader.

Callers constructing their own atlas can inject a scoped policy and a thread-safe sink:

```swift
let diagnostics = MissingGlyphWarnings(policy: .bounded) { line in
  // Called serially on a private background queue; do not touch UI state here.
  sendToDiagnosticLog(line)
}
let atlas = HighResolutionFontAtlas(missingGlyphWarnings: diagnostics)
```

Reuse the diagnostics instance across related atlases to share its budget. Creating a new instance
starts a new budget; the default shared instance lasts for the process. Custom sinks receive the
same bounded codepoint-only records, and must be Sendable. Disabled mode performs no output work.
