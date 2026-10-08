# Install

From the app's Swift package (with Chroma as a dependency):

**Linux**
```sh
swift package chroma-install
```

**macOS**
```sh
swift package --disable-sandbox \
  --allow-writing-to-directory "$HOME/Applications" chroma-install
```

Always builds **release** for the current platform. Symbols are included by default;
pass `--without-profiling` after `chroma-install` to omit debug info.

- Uses the package's single executable product. No JSON configuration.
- Linux: installs under `~/.local`, including a launcher in `~/.local/bin`.
- macOS: installs to `~/Applications`, using an available Apple Development signing identity.
- Copies dependency resources. Uses existing `Packaging/Info.plist`, `Packaging/AppIcon.png`
  (Linux) / `AppIcon.icns` (macOS), and `LICENSE` when present.

The macOS command disables SwiftPM's plugin sandbox so signing can access the Keychain;
the directory write grant alone is insufficient. Only run it with packages you trust.

Quit the app before reinstalling. Recognized legacy Scribe/ShapeTree installs migrate with backups;
unrelated files are not overwritten. No elevated privileges are used.
