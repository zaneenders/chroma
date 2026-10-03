# Headless mode tests

Run from the repository root:

```sh
swift build -c release --product ChromaHeadlessDemo
swift build --package-path HeadlessModeTests -c release --product HeadlessProcessFixture
CHROMA_HEADLESS_DEMO="$(swift build -c release --show-bin-path)/ChromaHeadlessDemo" \
CHROMA_HEADLESS_FIXTURE="$(swift build --package-path HeadlessModeTests -c release --show-bin-path)/HeadlessProcessFixture" \
swift test --package-path HeadlessModeTests -c release
```

The tests drive the demo and fixture as real child processes using Swift Subprocess.
