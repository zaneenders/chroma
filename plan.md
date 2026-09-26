# Keyboard navigation contract

- One navigation tree, rooted at the window; no initial selected child.
- `Group` defines a semantic boundary. Stacks and visual wrappers do not.
- ScrollView and standalone LazyVStack define scrolling boundaries.
- `d/f/j/k` move among peers and stop at the current group's edges.
- `Shift+d/f/j/k` search outward from the current group and select a neighboring
  section without entering it. Shift+letters remain text in EDIT/SELECT mode.
- `l` enters a group, restores its remembered child, or activates a leaf.
- `s` selects the containing group; Escape leaves EDIT/SELECT for MOVE.
- Hover does not change keyboard selection. Pointer clicks select their target.
- `.navigationIgnored()` excludes decoration; hover styling changes appearance only.
- Selectable text supports read-only caret movement, range selection and copying.
- Scroll controllers retain position while absent, reset on identity changes, and
  reveal keyboard-selected content only as needed. Following new messages is opt-in.

Contract coverage: NavigationContractTests, HierarchicalNavigationTests,
ScrollNavigationTests, and the Example's WorkspaceTests.
