# Chroma Examples

```sh
swift run --package-path Examples PlayDemo
swift run --package-path Examples ChatDemo
swift run --package-path Examples ImageDemo
```

## Testing 

```sh
swift test --package-path Examples
```

## Interaction profiling

```sh
ROWS=1000 swift run --package-path Examples -c release InteractionDemo
ROWS=1000 LAZY=1 swift run --package-path Examples -c release InteractionDemo
```

Move the mouse over the list, scroll, and click rows. The default is an eager list; `LAZY=1` limits row work to the viewport. `ROWS` must be positive. There are no animations or streaming updates. Profile the main thread to compare registration refresh (`WindowRuntime.processInput` → `FrameProducer.refreshRegistrations` → `BlockEngine.draw`) with normal rendering. The headless `InteractionBenchmark` measures the same workload without GPU work.
