# Sidebar Directory Click Toggle Design

## Goal

Make nested sidebar directory headers easier to expand and collapse by allowing a single click on the
directory header row, including the name and row whitespace, to toggle the group. The chevron remains as
the visual affordance.

## Current Context

The sidebar can nest git worktrees by branch path. Shared branch prefixes render as directory-like group
headers through `SidebarPathGroupHeaderRow` in
`supacode/Features/Repositories/Views/SidebarItemsView.swift`. Expanding and collapsing persists through
the existing `RepositoriesFeature.Action.branchNestExpansionChanged` action and
`SidebarState.Section.Bucket.collapsedBranchPrefixes`.

There is already a focused interaction test in
`supacodeTests/SidebarPathGroupHeaderInteractionTests.swift` for clicking away from the chevron. The
implementation should keep that behavior explicit and reliable.

## Design

Use single-click as the interaction. A click anywhere in a nested branch group header row toggles the
header between expanded and collapsed.

The row should continue to:

- Show the chevron with the current rotation animation.
- Use the existing reducer action for state changes.
- Preserve existing collapsed-state persistence.
- Keep drag movement disabled for group headers.
- Keep accessibility labels and help text aligned with the current state.

No double-click behavior is needed. Directory headers do not represent selectable worktrees, so single
click does not need to preserve a competing selection action.

## Testing

Update or add a focused test that hosts `SidebarItemsView`, clicks a point away from the chevron on the
directory/header row, and verifies that the corresponding prefix is added to
`collapsedBranchPrefixes`. This test should fail if only the chevron is clickable.

Run the targeted sidebar path group interaction test before and after the implementation, then run the
app build with `make build-app`.
