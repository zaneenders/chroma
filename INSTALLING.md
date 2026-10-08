# Install

From the app's Swift package (with Chroma as a dependency):

```sh
swift package chroma-install
swift package chroma-install --without-profiling
```

Always builds **release** for the current platform. Symbols are included by default;
`--without-profiling` omits debug info.

- Uses the package's single executable product. No JSON configuration.
- Linux: installs under `~/.local`, including a launcher in `~/.local/bin`.
- macOS: installs to `~/Applications`, using an available Apple Development signing identity.
- Copies dependency resources. Uses existing `Packaging/Info.plist`, `Packaging/AppIcon.png`
  (Linux) / `AppIcon.icns` (macOS), and `LICENSE` when present.

Quit the app before reinstalling. Recognized legacy Scribe/ShapeTree installs migrate with backups;
unrelated files are not overwritten.
On macOS, SwiftPM may require `--allow-writing-to-directory "$HOME/Applications"`
before `chroma-install`. No elevated privileges are used.
