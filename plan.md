# Keyboard navigation contract

- One navigation tree, rooted at the window; no initial selected child.
- `Group` defines a semantic boundary. Stacks and visual wrappers do not.
- ScrollView and standalone LazyVStack define scrolling boundaries.
- `d/f/j/k` move among peers and stop at the current group's edges.
- `Shift+d/f/j/k` search outward from the current group and select a neighboring
  section without entering it. Inside text these keys extend selection; in INPUT they type uppercase letters.
- `l` enters a group or text, restores a group's remembered child, or activates a button.
- `s` leaves the text level or selects the containing group. Enter starts INPUT;
  Escape returns to MOVE inside text, preserving caret and selection.
- Hover does not change keyboard selection. Pointer clicks select their target.
- `.navigationIgnored()` excludes decoration; hover styling changes appearance only.
- Text handles MOVE as caret movement and selection. Only editable text permits
  INPUT. Arrow keys are unbound by default.
- Scroll controllers retain position while absent, reset on identity changes, and
  reveal keyboard-selected content only as needed. Following new messages is opt-in.

Contract coverage: NavigationContractTests, HierarchicalNavigationTests,
ScrollNavigationTests, and the Example's WorkspaceTests.
