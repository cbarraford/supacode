import AppKit
import ComposableArchitecture
import Foundation
import OrderedCollections
import SwiftUI
import Testing

@testable import supacode

@MainActor
struct SidebarPathGroupHeaderInteractionTests {
  @Test func clickingDirectoryHeaderRowAwayFromChevronTogglesExpansion() {
    let repoRoot = "/tmp/repo"
    let featureA = makeWorktree(id: "/tmp/repo/feature-a", name: "feature/a", repoRoot: repoRoot)
    let featureB = makeWorktree(id: "/tmp/repo/feature-b", name: "feature/b", repoRoot: repoRoot)
    let repository = makeRepository(id: repoRoot, worktrees: [featureA, featureB])
    var state = RepositoriesFeature.State(reconciledRepositories: [repository])
    state.$sidebarNestWorktreesByBranch.withLock { $0 = true }
    state.reconcileSidebarForTesting()

    let store = Store(initialState: state) {
      RepositoriesFeature()
    }
    let groups = repositoryGroups(in: store.state, repositoryID: repository.id)
    let view = VStack(spacing: 0) {
      SidebarItemsView(
        repository: repository,
        groups: groups,
        shortcutHintByID: [:],
        selectedWorktreeIDs: [],
        store: store,
        terminalManager: WorktreeTerminalManager(runtime: GhosttyRuntime()),
      )
    }
    .frame(width: 240, height: 96, alignment: .topLeading)

    clickHosted(view, at: CGPoint(x: 210, y: 82), size: CGSize(width: 240, height: 96))

    #expect(
      store.state.sidebar.sections[repository.id]?.buckets[.unpinned]?.collapsedBranchPrefixes
        == ["feature"]
    )
  }

  private func repositoryGroups(
    in state: RepositoriesFeature.State,
    repositoryID: Repository.ID,
  ) -> [SidebarItemGroup] {
    for section in state.sidebarStructure.sections {
      if case .repository(let id, let groups) = section, id == repositoryID {
        return groups
      }
    }
    return []
  }

  private func clickHosted<V: View>(
    _ view: V,
    at location: CGPoint,
    size: CGSize,
  ) {
    let hostingView = NSHostingView(rootView: view)
    let window = NSWindow(
      contentRect: CGRect(origin: .zero, size: size),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false,
    )
    window.contentView = hostingView
    hostingView.frame = CGRect(origin: .zero, size: size)
    window.layoutIfNeeded()
    hostingView.layoutSubtreeIfNeeded()

    sendMouseEvent(.leftMouseDown, to: window, at: location, eventNumber: 1)
    sendMouseEvent(.leftMouseUp, to: window, at: location, eventNumber: 2)
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
  }

  private func sendMouseEvent(
    _ type: NSEvent.EventType,
    to window: NSWindow,
    at location: CGPoint,
    eventNumber: Int,
  ) {
    let event = NSEvent.mouseEvent(
      with: type,
      location: location,
      modifierFlags: [],
      timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: eventNumber,
      clickCount: 1,
      pressure: type == .leftMouseDown ? 1 : 0,
    )
    if let event {
      window.sendEvent(event)
    }
  }

  private func makeWorktree(
    id: String,
    name: String,
    repoRoot: String,
  ) -> Worktree {
    Worktree(
      id: WorktreeID(id),
      name: name,
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: id),
      repositoryRootURL: URL(fileURLWithPath: repoRoot),
    )
  }

  private func makeRepository(
    id: String,
    worktrees: [Worktree],
  ) -> Repository {
    Repository(
      id: RepositoryID(id),
      rootURL: URL(fileURLWithPath: id),
      name: "repo",
      worktrees: IdentifiedArray(uniqueElements: worktrees),
    )
  }
}
