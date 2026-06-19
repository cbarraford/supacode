import ComposableArchitecture
import Foundation
import SupacodeSettingsShared

struct CLIForgeProviderClient: Sendable {
  var batchPullRequests: @Sendable (ForgeRemoteInfo, [String], URL?) async throws -> [String: ForgePullRequest]
  var customStatusChecks: @Sendable (ForgeCustomCICommand, ForgeCustomCIContext) async throws -> [ForgeStatusCheck]
  var isAvailable: @Sendable (ForgeProviderDescriptor) async -> Bool

  static func live(shell: ShellClient = .liveValue) -> CLIForgeProviderClient {
    let resolver = CLIForgeExecutableResolver()
    return CLIForgeProviderClient(
      batchPullRequests: { remote, branches, repoRoot in
        guard remote.providerID == .gitLab else {
          return [:]
        }
        return try await GitLabCLIAdapter.batchPullRequests(
          remote: remote,
          branches: branches,
          repoRoot: repoRoot,
          shell: shell,
          resolver: resolver,
        )
      },
      customStatusChecks: { command, context in
        try await CustomCICommandRunner.statusChecks(
          command: command,
          context: context,
          shell: shell,
        )
      },
      isAvailable: { descriptor in
        await resolver.isAvailable(executableName: descriptor.executableName, shell: shell)
      },
    )
  }

  static let testValue = CLIForgeProviderClient(
    batchPullRequests: { _, _, _ in [:] },
    customStatusChecks: { _, _ in [] },
    isAvailable: { _ in true },
  )
}

nonisolated struct ForgeCustomCIContext: Equatable, Sendable {
  let repoRoot: URL
  let branch: String
  let remote: ForgeRemoteInfo
  let pullRequest: ForgePullRequest
}

extension CLIForgeProviderClient: DependencyKey {
  static let liveValue = live()
}

extension DependencyValues {
  var cliForgeProvider: CLIForgeProviderClient {
    get { self[CLIForgeProviderClient.self] }
    set { self[CLIForgeProviderClient.self] = newValue }
  }
}

private actor CLIForgeExecutableResolver {
  private var cachedExecutableURLs: [String: URL] = [:]
  private var inFlightResolutions: [String: Task<URL, Error>] = [:]

  func executableURL(executableName: String, shell: ShellClient) async throws -> URL {
    if let cached = cachedExecutableURLs[executableName] {
      return cached
    }
    if let inFlight = inFlightResolutions[executableName] {
      return try await inFlight.value
    }
    let task = Task {
      try await resolveExecutableURL(executableName: executableName, shell: shell)
    }
    inFlightResolutions[executableName] = task
    do {
      let url = try await task.value
      cachedExecutableURLs[executableName] = url
      inFlightResolutions[executableName] = nil
      return url
    } catch {
      inFlightResolutions[executableName] = nil
      throw error
    }
  }

  func isAvailable(executableName: String, shell: ShellClient) async -> Bool {
    do {
      _ = try await executableURL(executableName: executableName, shell: shell)
      return true
    } catch {
      return false
    }
  }

  private func resolveExecutableURL(executableName: String, shell: ShellClient) async throws -> URL {
    let whichURL = URL(fileURLWithPath: "/usr/bin/which")
    let output = try await shell.run(whichURL, [executableName], nil).stdout
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw GithubCLIError.unavailable
    }
    return URL(fileURLWithPath: trimmed)
  }
}

private enum GitLabCLIAdapter {
  static func batchPullRequests(
    remote: ForgeRemoteInfo,
    branches: [String],
    repoRoot: URL?,
    shell: ShellClient,
    resolver: CLIForgeExecutableResolver,
  ) async throws -> [String: ForgePullRequest] {
    let dedupedBranches = deduplicatedBranches(branches)
    guard !dedupedBranches.isEmpty else {
      return [:]
    }
    let executableURL = try await resolver.executableURL(
      executableName: ForgeProviderDescriptor.gitLab.executableName,
      shell: shell,
    )
    var results: [String: ForgePullRequest] = [:]
    for branch in dedupedBranches {
      let output = try await shell.runLogin(
        executableURL,
        [
          "mr",
          "list",
          "--repo",
          repoURL(for: remote),
          "--source-branch",
          branch,
          "--output",
          "json",
          "--per-page",
          "5",
        ],
        repoRoot,
        log: false,
      ).stdout
      guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        continue
      }
      let mergeRequests = try JSONDecoder().decode([GitLabMergeRequestResponse].self, from: Data(output.utf8))
      if let pullRequest =
        mergeRequests
        .map({ $0.pullRequest(providerCapabilities: ForgeProviderDescriptor.gitLab.capabilities) })
        .max(by: { lhs, rhs in
          let leftRank = gitLabStateRank(lhs.state)
          let rightRank = gitLabStateRank(rhs.state)
          if leftRank != rightRank {
            return leftRank < rightRank
          }
          return lhs.number < rhs.number
        })
      {
        results[branch] = pullRequest
      }
    }
    return results
  }

  private static func repoURL(for remote: ForgeRemoteInfo) -> String {
    "https://\(remote.host)/\(remote.projectPath)"
  }

  private static func deduplicatedBranches(_ branches: [String]) -> [String] {
    var seen = Set<String>()
    return branches.filter { !$0.isEmpty && seen.insert($0).inserted }
  }

  private static func gitLabStateRank(_ state: String) -> Int {
    switch state.uppercased() {
    case "OPEN":
      return 2
    case "MERGED":
      return 1
    default:
      return 0
    }
  }
}

private struct GitLabMergeRequestResponse: Decodable {
  let iid: Int
  let title: String
  let state: String
  let draft: Bool?
  let workInProgress: Bool?
  let webURL: String
  let sourceBranch: String?
  let targetBranch: String?
  let author: Author?
  let pipeline: Pipeline?

  private enum CodingKeys: String, CodingKey {
    case iid
    case title
    case state
    case draft
    case workInProgress = "work_in_progress"
    case webURL = "web_url"
    case sourceBranch = "source_branch"
    case targetBranch = "target_branch"
    case author
    case pipeline
  }

  struct Author: Decodable {
    let username: String?
    let login: String?
  }

  struct Pipeline: Decodable {
    let status: String?
    let webURL: String?

    private enum CodingKeys: String, CodingKey {
      case status
      case webURL = "web_url"
    }
  }

  func pullRequest(providerCapabilities: Set<ForgeCapability>) -> ForgePullRequest {
    ForgePullRequest(
      providerID: .gitLab,
      providerCapabilities: providerCapabilities,
      number: iid,
      title: title,
      state: normalizedState,
      additions: 0,
      deletions: 0,
      isDraft: draft ?? workInProgress ?? title.lowercased().hasPrefix("draft:"),
      reviewDecision: nil,
      mergeable: nil,
      mergeStateStatus: nil,
      updatedAt: nil,
      url: webURL,
      headRefName: sourceBranch,
      baseRefName: targetBranch,
      commitsCount: nil,
      authorLogin: author?.username ?? author?.login,
      statusCheckRollup: pipeline.map { pipeline in
        ForgeStatusCheckRollup(checks: [
          ForgeStatusCheck(
            name: "Pipeline",
            detailsUrl: pipeline.webURL,
            status: "COMPLETED",
            conclusion: nil,
            state: pipeline.status,
          )
        ])
      },
      mergeQueueEntry: nil,
    )
  }

  private var normalizedState: String {
    switch state.lowercased() {
    case "opened", "open":
      return "OPEN"
    case "merged":
      return "MERGED"
    case "closed", "closed_at":
      return "CLOSED"
    default:
      return state.uppercased()
    }
  }
}

private enum CustomCICommandRunner {
  static func statusChecks(
    command: ForgeCustomCICommand,
    context: ForgeCustomCIContext,
    shell: ShellClient,
  ) async throws -> [ForgeStatusCheck] {
    let rendered = render(command.command, context: context)
    let output = try await shell.runLogin(
      URL(fileURLWithPath: "/bin/zsh"),
      ["-lc", rendered],
      context.repoRoot,
      log: false,
    ).stdout
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return []
    }
    let response = try JSONDecoder().decode(CustomCIStatusResponse.self, from: Data(trimmed.utf8))
    return response.checks.map(\.statusCheck)
  }

  private static func render(_ template: String, context: ForgeCustomCIContext) -> String {
    let replacements: [String: String] = [
      "REPO_ROOT": context.repoRoot.path(percentEncoded: false),
      "BRANCH": context.branch,
      "REMOTE_HOST": context.remote.host,
      "PROJECT_PATH": context.remote.projectPath,
      "PULL_REQUEST_NUMBER": "\(context.pullRequest.number)",
      "PULL_REQUEST_URL": context.pullRequest.url,
    ]
    return replacements.reduce(template) { partial, entry in
      partial.replacing("{{\(entry.key)}}", with: entry.value)
    }
  }
}

private struct CustomCIStatusResponse: Decodable {
  let checks: [Check]

  struct Check: Decodable {
    let name: String?
    let status: String?
    let conclusion: String?
    let detailsUrl: String?

    var statusCheck: ForgeStatusCheck {
      ForgeStatusCheck(
        name: name,
        detailsUrl: detailsUrl,
        status: nil,
        conclusion: conclusion,
        state: status,
      )
    }
  }
}
