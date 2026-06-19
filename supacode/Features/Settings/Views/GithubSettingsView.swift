import ComposableArchitecture
import SupacodeSettingsFeature
import SupacodeSettingsShared
import SwiftUI

@MainActor @Observable
final class GithubSettingsViewModel {
  enum GithubState: Equatable {
    case loading
    case unavailable
    case outdated
    case notAuthenticated
    case authenticated(username: String, host: String)
    case error(String)
  }

  var githubState: GithubState = .loading
  var isGitLabCLIAvailable = false

  @ObservationIgnored
  @Dependency(GithubCLIClient.self) private var githubCLI

  @ObservationIgnored
  @Dependency(CLIForgeProviderClient.self) private var cliForgeProvider

  func load() async {
    githubState = .loading
    isGitLabCLIAvailable = await cliForgeProvider.isAvailable(.gitLab)

    do {
      guard await githubCLI.isAvailable() else {
        githubState = .unavailable
        return
      }
      if let status = try await githubCLI.authStatus() {
        githubState = .authenticated(username: status.username, host: status.host)
      } else {
        githubState = .notAuthenticated
      }
    } catch let error as GithubCLIError {
      switch error {
      case .outdated:
        githubState = .outdated
      case .unavailable:
        githubState = .unavailable
      case .gatewayTimeout:
        githubState = .error(error.localizedDescription ?? "GitHub returned a gateway timeout.")
      case .commandFailed(let message):
        githubState = .error(message)
      }
    } catch {
      githubState = .error(error.localizedDescription)
    }
  }
}

struct GithubSettingsView: View {
  @Bindable var store: StoreOf<SettingsFeature>
  @State private var viewModel = GithubSettingsViewModel()

  var body: some View {
    Form {
      Section {
        Toggle(isOn: $store.githubIntegrationEnabled) {
          Text("Enable Forge Providers")
          Text("Pull request and merge request status in the sidebar and command palette.")
        }
      }
      Section("Bundled Providers") {
        providerRow(
          name: "GitHub",
          executable: "gh",
          status: githubStatusText,
          capabilities: "PR status, merge actions, Actions logs, re-run failed jobs",
        )
        providerRow(
          name: "GitLab",
          executable: "glab",
          status: viewModel.isGitLabCLIAvailable ? "CLI found" : "CLI not found",
          capabilities: "MR status and pipeline status",
        )
      }
      Section("GitHub CLI") {
        switch viewModel.githubState {
        case .loading:
          LabeledContent("Checking GitHub CLI…") {
            ProgressView().controlSize(.small)
          }

        case .unavailable:
          Label {
            VStack(alignment: .leading, spacing: 2) {
              Text("GitHub CLI not found")
              Text("Install `gh` to enable pull request checks.")
                .foregroundStyle(.secondary)
                .font(.callout)
            }
          } icon: {
            Image(systemName: "xmark.circle")
              .foregroundStyle(.red)
              .accessibilityHidden(true)
          }

        case .notAuthenticated:
          Label {
            VStack(alignment: .leading, spacing: 2) {
              Text("Not authenticated")
              Text("Run `gh auth login` in a terminal to authenticate.")
                .foregroundStyle(.secondary)
                .font(.callout)
            }
          } icon: {
            Image(systemName: "exclamationmark.triangle")
              .foregroundStyle(.orange)
              .accessibilityHidden(true)
          }

        case .outdated:
          Label {
            VStack(alignment: .leading, spacing: 2) {
              Text("GitHub CLI outdated")
              Text("Update to the latest version for full support.")
                .foregroundStyle(.secondary)
                .font(.callout)
            }
          } icon: {
            Image(systemName: "exclamationmark.triangle")
              .foregroundStyle(.orange)
              .accessibilityHidden(true)
          }

        case .authenticated(let username, let host):
          LabeledContent("Signed in as") {
            Text(username)
          }
          LabeledContent("Host") {
            Text(host)
          }

        case .error(let message):
          Label {
            VStack(alignment: .leading, spacing: 2) {
              Text("Error checking status")
              Text(message)
                .foregroundStyle(.secondary)
                .font(.callout)
            }
          } icon: {
            Image(systemName: "exclamationmark.triangle")
              .foregroundStyle(.red)
              .accessibilityHidden(true)
          }
        }

        switch viewModel.githubState {
        case .unavailable:
          Button("Get GitHub CLI") {
            NSWorkspace.shared.open(URL(string: "https://cli.github.com")!)
          }
        case .outdated:
          Button("Update GitHub CLI") {
            NSWorkspace.shared.open(URL(string: "https://cli.github.com")!)
          }
        default:
          EmptyView()
        }
      }
      Section("Pull Requests") {
        Picker(selection: $store.pullRequestMergeStrategy) {
          ForEach(PullRequestMergeStrategy.allCases) { strategy in
            Text(strategy.title)
              .tag(strategy)
          }
        } label: {
          Text("Merge strategy")
          Text("Default strategy when merging PRs from the command palette.")
        }
        Picker(selection: $store.mergedWorktreeAction) {
          Text("Do nothing").tag(MergedWorktreeAction?.none)
          ForEach(MergedWorktreeAction.allCases) { action in
            Text(action.title).tag(MergedWorktreeAction?.some(action))
          }
        } label: {
          Text("When a pull request is merged")
          switch store.mergedWorktreeAction {
          case .archive:
            Text("Archives the worktree when its pull request is merged.")
          case .delete:
            Text("Follows the \"Delete local branch with worktree\" option in Worktrees settings.")
          case nil:
            EmptyView()
          }
        }
      }
    }
    .formStyle(.grouped)
    .padding(.top, -20)
    .padding(.leading, -8)
    .padding(.trailing, -6)
    .navigationTitle("Providers")
    .task {
      await viewModel.load()
    }
    .onChange(of: store.githubIntegrationEnabled) { _, _ in
      Task {
        await viewModel.load()
      }
    }
  }

  private var githubStatusText: String {
    switch viewModel.githubState {
    case .loading:
      return "Checking..."
    case .unavailable:
      return "CLI not found"
    case .outdated:
      return "CLI outdated"
    case .notAuthenticated:
      return "Not authenticated"
    case .authenticated:
      return "Authenticated"
    case .error:
      return "Error"
    }
  }

  private func providerRow(
    name: String,
    executable: String,
    status: String,
    capabilities: String,
  ) -> some View {
    LabeledContent {
      VStack(alignment: .trailing, spacing: 2) {
        Text(status)
        Text(capabilities)
          .foregroundStyle(.secondary)
          .font(.callout)
          .multilineTextAlignment(.trailing)
      }
    } label: {
      Text(name)
      Text("Uses `\(executable)`")
    }
  }
}
