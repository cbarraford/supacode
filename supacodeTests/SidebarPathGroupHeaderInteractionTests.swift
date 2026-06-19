import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI
import Testing

@testable import supacode

@MainActor
struct SidebarPathGroupHeaderInteractionTests {
  @Test func clickingDirectoryHeaderRowAwayFromChevronTogglesExpansion() {
    let repositoryID: Repository.ID = "/tmp/repo"
    let observedExpansion = LockIsolated<ObservedExpansion?>(nil)
    let store = Store(initialState: RepositoriesFeature.State()) {
      Reduce<RepositoriesFeature.State, RepositoriesFeature.Action> { _, action in
        if case .branchNestExpansionChanged(
          let repositoryID,
          let bucketID,
          let prefix,
          let isExpanded,
        ) = action {
          observedExpansion.withValue {
            $0 = ObservedExpansion(
              repositoryID: repositoryID,
              bucketID: bucketID,
              prefix: prefix,
              isExpanded: isExpanded,
            )
          }
        }
        return .none
      }
    }
    let view = SidebarPathGroupHeaderRow(
      repositoryID: repositoryID,
      bucketID: .unpinned,
      prefix: "feature",
      components: ["feature"],
      depth: 0,
      isCollapsed: false,
      leafDescendantIDs: [],
      store: store,
    )
    .frame(width: 240, height: 40, alignment: .topLeading)

    clickHosted(view, at: CGPoint(x: 72, y: 34), size: CGSize(width: 240, height: 40))

    #expect(
      observedExpansion.value
        == ObservedExpansion(
          repositoryID: repositoryID,
          bucketID: .unpinned,
          prefix: "feature",
          isExpanded: false,
        )
    )
  }

  private struct ObservedExpansion: Equatable {
    var repositoryID: Repository.ID
    var bucketID: SidebarBucket
    var prefix: String
    var isExpanded: Bool
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
    window.makeKeyAndOrderFront(nil)
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
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
}
