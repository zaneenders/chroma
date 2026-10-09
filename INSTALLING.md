# Install

From the app's Swift package (with Chroma as a dependency):

**Linux**
```sh
swift package chroma-install
```

**macOS** (update the system Applications copy)
```sh
swift package --disable-sandbox \
  --allow-writing-to-directory /Applications chroma-install --install-directory /Applications
```

Omit `--install-directory` and use `--allow-writing-to-directory "$HOME/Applications"`
for a user-only installation instead. The write grant is a sandbox permission,
not the installation destination; use `--install-directory` to select the destination.

Always builds **release** for the current platform. Symbols are included by default;
pass `--without-profiling` after `chroma-install` to omit debug info.

- Uses the package's single executable product. No JSON configuration.
- Linux: defaults to `~/.local`, including a launcher in `~/.local/bin`; `--install-directory` overrides that prefix.
- macOS: defaults to `~/Applications`; `--install-directory /Applications` updates the system copy using an available Apple Development signing identity.
- Copies dependency resources. Uses existing `Packaging/Info.plist`, `Packaging/AppIcon.png`
  (Linux) / `AppIcon.icns` (macOS), and `LICENSE` when present.

The macOS command disables SwiftPM's plugin sandbox so signing can access the Keychain;
the directory write grant alone is insufficient. Only run it with packages you trust.

Quit the app before reinstalling; macOS checks for a running executable before building and replacing the app.
Recognized legacy Scribe/ShapeTree installs migrate with backups; unrelated files are not overwritten.
The selected installation directory must be writable by your user. No elevated privileges are used.
