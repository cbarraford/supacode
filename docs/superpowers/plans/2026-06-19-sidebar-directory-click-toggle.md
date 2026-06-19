# Sidebar Directory Click Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a single click anywhere on a nested sidebar directory header row toggle expand/collapse.

**Architecture:** Keep the behavior in the existing `SidebarPathGroupHeaderRow` SwiftUI view. The view continues sending `RepositoriesFeature.Action.branchNestExpansionChanged`, so reducer state, persistence, and branch nesting data logic remain unchanged. The row already uses one full-width plain `Button`; the implementation exposes that row internally so the interaction can be tested directly without hosting the entire sidebar tree.

**Tech Stack:** Swift 6, SwiftUI, TCA, Swift Testing, macOS `NSHostingView` interaction test harness.

---

## File Structure

- Modify: `supacodeTests/SidebarPathGroupHeaderInteractionTests.swift`
  - Owns the targeted hosted-view interaction test for clicking a nested branch group header away from the chevron.
- Modify: `supacode/Features/Repositories/Views/SidebarItemsView.swift`
  - Owns `SidebarPathGroupHeaderRow`, the directory-like group header rendered by nested branch grouping.

---

### Task 1: Lock In Whole-Row Single-Click Toggle

**Files:**
- Modify: `supacodeTests/SidebarPathGroupHeaderInteractionTests.swift`
- Modify: `supacode/Features/Repositories/Views/SidebarItemsView.swift`

- [x] **Step 1: Write the failing interaction test**

In `supacodeTests/SidebarPathGroupHeaderInteractionTests.swift`, host `SidebarPathGroupHeaderRow` directly and make the tested click clearly target the directory name / row body rather than the chevron:

```swift
clickHosted(view, at: CGPoint(x: 72, y: 34), size: CGSize(width: 240, height: 40))
```

The point is inside the header row label area for the `feature` group and away from the chevron.

- [x] **Step 2: Run the targeted test to verify it fails when only the chevron is clickable**

Run:

```bash
xcodebuild test -workspace supacode.xcworkspace -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/SidebarPathGroupHeaderInteractionTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```

Result: the first full-sidebar hosted harness crashed on unsafe `Store.state` access before the click. The test was narrowed to the actual header row so it verifies the single-click interaction without unrelated sidebar observation.

- [x] **Step 3: Implement the minimal row hit-target change**

In `supacode/Features/Repositories/Views/SidebarItemsView.swift`, keep the whole group header as one plain `Button` and ensure the full row frame is the interactive shape:

```swift
.frame(maxWidth: .infinity, alignment: .leading)
.contentShape(.interaction, .rect)
```

These modifiers belong on the `HStack` inside the `Button` label so the label area, directory text, trailing whitespace, and chevron all participate in the button hit test.

Result: these modifiers were already present. `SidebarPathGroupHeaderRow` was changed from `private` to internal so the regression test can host the row directly.

- [x] **Step 4: Run the targeted test to verify it passes**

Run:

```bash
xcodebuild test -workspace supacode.xcworkspace -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/SidebarPathGroupHeaderInteractionTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```

Result: `SidebarPathGroupHeaderInteractionTests` passed with one click on the label area. After a clean Tuist
generation, the default Swift 6 dependency build failed before reaching app/test code in
`swift-composable-architecture`; the same focused interaction test passed with the diagnostic
`SWIFT_VERSION=5.0` override once that dependency graph compiled.

- [x] **Step 5: Build the app**

Run:

```bash
make build-app
```

Result: `make build-app` currently fails before compiling Supacode app code, inside the generated
`swift-composable-architecture` package project:

```text
Binding+Observation.swift:86:5: type 'WritableKeyPath<Root, Value>' does not conform to the 'Sendable' protocol
```

The same failure occurs with `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES` and with
`SWIFT_STRICT_CONCURRENCY=minimal`, so this is tracked as an environment/dependency build blocker
for the required default build rather than a failure introduced by the sidebar row change.

- [x] **Step 6: Commit only the implementation changes**

Run:

```bash
git status --short
git add supacodeTests/SidebarPathGroupHeaderInteractionTests.swift supacode/Features/Repositories/Views/SidebarItemsView.swift docs/superpowers/plans/2026-06-19-sidebar-directory-click-toggle.md
git commit -m "Make sidebar directory headers easier to toggle"
```

Expected: one commit containing the focused test/update, the minimal SwiftUI hit-target change if needed, and this plan document.
