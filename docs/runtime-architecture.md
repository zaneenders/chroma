# Runtime architecture

**Proposal only.** Types and calls below are illustrative, not implemented APIs.

## Implementation policy

| Decision | Requirement |
| --- | --- |
| Breaking changes | Allowed, including public APIs, when they simplify the design |
| Backward compatibility | Not required; no compatibility shims, deprecated wrappers, or legacy fallback paths |
| Migration | Update repository callers, tests, benchmarks, and documentation to the new APIs |
| Removal | Delete superseded APIs, duplicate implementations, and code made unnecessary by the redesign |
| Behavior | Preserve required behavior and regression coverage; API cleanup is not permission to silently drop features |

## Replace overlapping responsibilities

| Current | Target |
| --- | --- |
| [`Interaction`](../Sources/Chroma/Interaction/Interaction.swift): state + builders + routing + geometry | Window-owned `UIState`; separate preparation and dispatch |
| [`BlockContext`](../Sources/Chroma/Blocks/BlockContext.swift): shared access across phases | Phase-specific capabilities |
| `PaintableBlock` / `LayoutPreparingBlock`: different focus contracts | One primitive contract; explicit focus behavior |
| Document / editor / custom-provider / drag-selection fallback chain | One explicit text-selection owner |

## Ownership

```text
Application                         Platform host
  model (@Observable) + documents     native events / clipboard / presentation
       |                                      |
       +------------------+-------------------+
                          v
                   WindowRuntime                 MAIN ACTOR
                   ├── UIState                   kept between events / frames
                   ├── FrameProducer              operation-local work + Observation tracking
                   └── FrameScheduler             presentation demand + cap
                          |
           +--------------+----------------+
           v                               v
   fresh input preparation         fresh frame preparation
           |                               |
      dispatch once                   paint -> DrawList -> backend
           |
     model / UIState
```

```swift
struct UIState {
  var focus: FocusState
  var scroll: [ScrollID: ScrollState]
  var editing: EditorSession?       // Editing lifecycle / IME, not another selection.
  var selection: TextSelection?
}
```

| Lifetime | Data |
| --- | --- |
| Across operations | Model, documents, `UIState`, collection identity index |
| Until replaced | Installed geometry for hover / platform queries; never fresh enough for actions |
| One operation | Temporary node graph, action handlers, proposal-dependent measurement cache |

## Temporary graph, serial read-only passes

**All UI passes run synchronously, in order, on the main actor. No concurrent walkers.**

```text
@Observable model + Block composition
      |
      v
resolve blocks -> operation-local GraphBuilder + actions
      |
      v
measure / place <------------> expand required virtual rows
  parent proposals -> child measurement
  child sizes      -> parent placement
      |
      v
freeze NodeGraph + Geometry
      |
      ├── 1. input walker ------> InputMap
      ├── 2. text walker -------> [TextGeometry]
      ├── runtime reconciliation -> VisualState
      └── 3. paint walker ------> DrawList         presentation only

SERIAL: 1 -> 2 -> reconcile -> 3
```

```swift
@MainActor
protocol PrimitiveBlock: Block where Body == Never {
  func prepare(in context: PreparationContext, into graph: inout GraphBuilder) -> NodeID
}

struct Node {
  let id: NodeID
  let layout: LayoutSpec
  let children: [NodeID]
  let input: InputSpec              // Focus, bindings, hit regions, action IDs.
  let paint: PaintSpec
}

struct NodeGraph {
  let root: NodeID
  let nodes: [NodeID: Node]
}

@MainActor
struct PreparedOperation {
  let graph: NodeGraph
  let geometry: Geometry
  let actions: [ActionID: @MainActor (InputEvent) -> Void]
}
```

Payload types omitted. Resolve each required node once per preparation; reuse it across
measurements and walkers. Lazy row factories stay in the builder, not the frozen graph.

```swift
@MainActor
func buildInputMap(_ graph: NodeGraph, geometry: Geometry) -> InputMap

@MainActor
func buildTextGeometry(_ graph: NodeGraph, geometry: Geometry) -> [TextGeometry]

@MainActor
func paint(
  _ graph: NodeGraph, geometry: Geometry,
  text: [TextGeometry], state: VisualState
) -> DrawList
```

| Phase | Reads | Owns / produces | Must not do |
| --- | --- | --- | --- |
| Resolve / expand | Blocks, environment, current model / state | Graph builder + action table | Dispatch actions / mutate model or UI state |
| Measure / place | Nodes + parent proposals | `Geometry`; local `(NodeID, proposal)` measurement cache | Mutate model / UI state; replace layout with a preorder walk |
| Input walker | Frozen graph + geometry | `InputMap` | Mutate nodes / state; execute callbacks |
| Text walker | Frozen graph + geometry | Visible `TextGeometry` | Infer complete document text from visible nodes |
| Paint walker | Frozen graph, geometry, text mapping, visual-state snapshot | `DrawList` | Register controls, mutate state, reevaluate blocks |
| Runtime reconcile / dispatch | Current documents + operation outputs | Updated model / `UIState` | Replay input during presentation |

**Read-only graph, separate outputs.** Walkers never attach results to nodes or expand children.
Reconciliation and dispatch are runtime steps, not read-only walkers.

### Virtualized lists

```text
collection descriptor + viewport + layout proposal
                         |
               determine required row range
                         |
               resolve visible rows + required overscan
                         |
               finish expansion / layout
                         |
               freeze graph -> serial walkers

NOT: collection -> resolve every row -> filter visible nodes
```

**Keep:** declarative blocks, dependency-aware layout, drawing backends.
**Avoid:** second engine, generic walker framework, parallel passes, cross-operation graph reuse.

## Input call stack

```text
Host event / queued input
└── WindowRuntime.handle(event)                  ordered main-actor execution
    ├── FrameProducer.prepare(current model, state, environment)
    │   ├── resolve -> graph builder + current actions
    │   ├── measure / place + expand required virtual rows
    │   └── freeze -> PreparedOperation(graph, geometry, actions)
    ├── buildInputMap(graph, geometry)
    ├── buildTextGeometry(graph, geometry)
    ├── reconcile UIState(documents, geometry, inputMap, text)
    ├── dispatch(event, inputMap, actions)       EXACTLY ONCE
    │   └── mutate model / UIState
    ├── FrameScheduler.requestPresentation()
    └── discard operation                       NO PAINT
```

**Every actionable event, including keyboard commands, gets fresh preparation.**
No suspension or intervening event between preparation and dispatch.
If reconciliation changes preparation / layout inputs, rebuild the operation and its
walker outputs **before** dispatch or paint.

## Presentation call stack

```text
FrameScheduler                                 30 Hz cap in this proposal
└── WindowRuntime.present()                    only when requested; no catch-up burst
    ├── withObservationTracking(.didSet)        rearm each evaluation
    │   ├── FrameProducer.prepare(LATEST model, state, environment)
    │   │   └── PreparedOperation(graph, geometry, actions)
    │   ├── buildInputMap(graph, geometry)
    │   ├── buildTextGeometry(graph, geometry)
    │   ├── reconcile UIState(documents, geometry, inputMap, text)
    │   ├── snapshot VisualState
    │   └── paint(graph, geometry, text, visualState) -> DrawList
    ├── host.present(drawList)
    └── discard operation                      NO INPUT REPLAY
```

```text
Input actions -----------------------+
Background results -> apply on actor +--> latest model / UIState
Animation updates -------------------+              |
                                                    v
Observation (.didSet) -> enqueue on actor --> presentation requested
First frame / resize ---------------------->        |
                                             coalesce requests
                                                    |
                                             one capped wakeup
                                                    |
                                                draw latest

state:   S0 -> key -> S1 -> network -> S2 -> animation -> S3
frames:  draw S0                                        draw S3

idle = no scheduled work       coalesce draws, NEVER actions / model updates
```

## Text belongs to a document, not a visible node

```swift
enum TextOwner { case document(DocumentID), editor(EditorID) }
struct TextPosition { let run: RunID; let offset: Int } // Character boundary.
struct TextSelection {
  let owner: TextOwner
  let revision: Revision
  let anchor: TextPosition
  var active: TextPosition
}
struct TextRun { let id: RunID; let text: String }
struct TextDocument {
  let owner: TextOwner
  let revision: Revision
  let runs: [TextRun]               // Complete ordered text + explicit copy separators.
}
```

```text
Application supplies complete TextDocument     independent of virtualization
                     |
                     +---- TextSelection ------> copy full range
                     |       anchor + active
                     |              |
Visible TextGeometry +--------------+----------> highlight intersection

Document:  A (anchor) ---- B ---- C ---- D (active)
Viewport:               [ B ---- C ]
Copy:      A ================================= D
Highlight:               B ==== C

focus != selection owner        reverse / shrink moves active, NEVER anchor
```

| Change | Selection |
| --- | --- |
| Offscreen / virtual node absent / resize / rewrap | Preserve |
| Endpoint deleted / document or editor session replaced | Clear |
| Text revision changed | Map using known edits, or clear affected selection; IDs alone are insufficient |

## Collection index cache, not a node-graph cache

```text
KEEP     collection ID + membership/order revision -> RowID-to-position index
REBUILD  required row nodes + layout + action callbacks on each operation
```

```swift
struct CollectionIdentityKey: Hashable {
  let collection: CollectionID
  let membershipRevision: UInt64
}
```

```text
CURRENT, measured at e0da048
HeadlessHost.sendInput
└── WindowRuntime.processInput
    └── FrameProducer.refreshRegistrations
        └── BlockEngine.register / resolve
            └── DeferredBlock.body -> StressScene.content
                └── ScrollView.init -> ScrollViewController.rowIdentity
                    └── TypedUniformRowIdentity.matches -> scan ALL IDs

TARGET
collection identity + membershipRevision
    ├── changed -> rebuild identity index
    └── same ----> reuse identity index
                         |
                    fresh visible-row preparation on EVERY operation
```

Revision contract: insertion, deletion, reorder, and ID replacement all invalidate.
Count or object identity alone is insufficient. A new tree shape alone does not fix this scan.

## Migration gates

```text
Temporary graph + dependency-aware layout + serial walkers
                  |
Button + selectable text + virtualized list, through headless host
                  |
Migrate built-ins / custom blocks -> delete replaced paths
```

| Gate | Required check |
| --- | --- |
| Input / presentation split | Consecutive keyboard + pointer actions: fresh, ordered, once; post-action paint |
| Unified primitive contract | Built-in and custom controls obey the same focus / phase rules |
| Text ownership | Offscreen copy, reverse / shrink, Unicode, edits, deletion, session replacement |
| Scheduling | Observation rearms; async model updates / animation request frames; idle does no work |
| Read-only passes | Input / text / paint walkers leave the graph unchanged; no block reevaluation or action dispatch |
| Layout / virtualization | Proposal-dependent measurement and placement remain correct; expand only required rows |
| Lifetimes | Graph shared within one preparation; no nodes or action tables reused between operations |
| Identity index | Unchanged IDs avoid scans; structural changes update lookup correctly |
| Migration complete | Repository callers use the new APIs; replaced paths and compatibility scaffolding are deleted |

Keep [scroll ownership issue #85](https://github.com/zaneenders/chroma/issues/85) separately tracked.

<details>
<summary>Measured baseline + reproduction (not a performance guarantee)</summary>

`e0da048`, release, M5 MacBook Air, macOS 27.0.1, Swift 6.4. Headless CPU only:
no native event loop, GPU, or Markdown parsing.

```text
StressBenchmark: 3 panes, depth 8, 1440 x 900
cycle: 2 activations + 12 scroll events -> 1 presentation -> 1,000 idle polls
5 warmups + 30 timed cycles; counters from a separate instrumented replay
```

| Rows / pane | Input burst p50 / p95 (ms) | Presentation p50 / p95 (ms) | First frame (one sample, ms) |
| ---: | ---: | ---: | ---: |
| 1,000 | 181.559 / 182.484 | 13.207 / 13.401 | 57.388 |
| 100,000 | 207.669 / 209.846 | 15.038 / 15.178 | 99.961 |
| 1,000,000 | 404.795 / 415.037 | 29.148 / 30.012 | 756.254 |

| Counter (same at all three sizes) | Input burst | Presentation |
| --- | ---: | ---: |
| Body evaluations | 370 | 26 |
| Measurements, including cache hits | 128,308 | 9,011 |
| Registrations | 19,762 | 1,388 |
| Paints | 0 | 1,388 |

Idle: ~0.015 ms / 1,000 polls; zero body evaluations, measurements, registrations, paints.

Million-row Time Profiler capture: 100 timed cycles + 5 warmups + instrumented replay;
includes startup / teardown. **Inclusive stack presence, not additive phase costs:**

| Sampled CPU weight | Value |
| --- | ---: |
| Total | 49.752 s |
| Identity matching / total | 52.34% |
| Identity matching within input | 24.266 / 42.137 s = 57.59% |
| `BlockEngine.resolve`, including identity matching | 72.23% |

Identity scans are a major cost here, not the only cost. Measure visible preparation,
layout, registration, allocation, and dispatch separately before choosing further optimizations.

```sh
swift build --package-path Benchmarks -c release --product StressBenchmark
profile_dir="$(mktemp -d /tmp/chroma-profile.XXXXXX)"
for rows in 1000 100000 1000000; do
  Benchmarks/.build/release/StressBenchmark --rows "$rows" --samples 30 --warmup 5 \
    > "$profile_dir/stress-$rows.json"
done
xcrun xctrace record --template 'Time Profiler' \
  --output "$profile_dir/stress.trace" --launch -- \
  "$PWD/Benchmarks/.build/release/StressBenchmark" \
  --rows 1000000 --samples 100 --warmup 5
```

Original local artifacts: `/tmp/chroma-profile/` (temporary, not committed).

</details>
