import Foundation
import Testing

@testable import SupacodeSettingsShared
@testable import supacode

actor CLIForgeShellRecorder {
  struct Snapshot {
    let whichCalls: [[String]]
    let loginCalls: [[String]]
  }

  private var whichCalls: [[String]] = []
  private var loginCalls: [[String]] = []

  func recordWhich(arguments: [String]) {
    whichCalls.append(arguments)
  }

  func recordLogin(arguments: [String]) {
    loginCalls.append(arguments)
  }

  func snapshot() -> Snapshot {
    Snapshot(whichCalls: whichCalls, loginCalls: loginCalls)
  }
}

struct CLIForgeProviderClientTests {
  @Test func gitLabBatchPullRequestsDecodesMergeRequestAndPipelineStatus() async throws {
    let recorder = CLIForgeShellRecorder()
    let shell = ShellClient(
      run: { executableURL, arguments, _ in
        if executableURL.lastPathComponent == "which" {
          await recorder.recordWhich(arguments: arguments)
          return ShellOutput(stdout: "/usr/local/bin/glab", stderr: "", exitCode: 0)
        }
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
      },
      runLoginImpl: { executableURL, arguments, _, _ in
        await recorder.recordLogin(arguments: [executableURL.lastPathComponent] + arguments)
        return ShellOutput(
          stdout: """
            [
              {
                "iid": 42,
                "title": "Ship provider abstraction",
                "state": "opened",
                "draft": true,
                "web_url": "https://gitlab.com/platform/mobile/ios/app-shell/-/merge_requests/42",
                "source_branch": "feature/provider",
                "target_branch": "main",
                "author": { "username": "khoi" },
                "pipeline": {
                  "status": "failed",
                  "web_url": "https://gitlab.com/platform/mobile/ios/app-shell/-/pipelines/99"
                }
              }
            ]
            """,
          stderr: "",
          exitCode: 0,
        )
      },
    )
    let client = CLIForgeProviderClient.live(shell: shell)
    let remote = ForgeRemoteInfo(
      providerID: .gitLab,
      host: "gitlab.com",
      projectPath: "platform/mobile/ios/app-shell",
    )

    let result = try await client.batchPullRequests(remote, ["feature/provider"], URL(fileURLWithPath: "/repo"))

    let pullRequest = try #require(result["feature/provider"])
    #expect(pullRequest.providerID == .gitLab)
    #expect(pullRequest.providerCapabilities == ForgeProviderDescriptor.gitLab.capabilities)
    #expect(pullRequest.number == 42)
    #expect(pullRequest.state == "OPEN")
    #expect(pullRequest.isDraft)
    #expect(pullRequest.headRefName == "feature/provider")
    #expect(pullRequest.baseRefName == "main")
    #expect(pullRequest.authorLogin == "khoi")
    #expect(pullRequest.statusCheckRollup?.checks.first?.checkState == .failure)
    #expect(
      pullRequest.statusCheckRollup?.checks.first?.detailsUrl
        == "https://gitlab.com/platform/mobile/ios/app-shell/-/pipelines/99"
    )

    let snapshot = await recorder.snapshot()
    #expect(snapshot.whichCalls == [["glab"]])
    #expect(
      snapshot.loginCalls.first == [
        "glab",
        "mr",
        "list",
        "--repo",
        "https://gitlab.com/platform/mobile/ios/app-shell",
        "--source-branch",
        "feature/provider",
        "--output",
        "json",
        "--per-page",
        "5",
      ])
  }

  @Test func gitLabBatchPullRequestsPrefersHeadPipelineStatus() async throws {
    let shell = ShellClient(
      run: { executableURL, _, _ in
        if executableURL.lastPathComponent == "which" {
          return ShellOutput(stdout: "/usr/local/bin/glab", stderr: "", exitCode: 0)
        }
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, _, _, _ in
        ShellOutput(
          stdout: """
            [
              {
                "iid": 42,
                "title": "Ship provider abstraction",
                "state": "opened",
                "web_url": "https://gitlab.com/platform/mobile/ios/app-shell/-/merge_requests/42",
                "source_branch": "feature/provider",
                "target_branch": "main",
                "pipeline": {
                  "status": "failed",
                  "web_url": "https://gitlab.com/platform/mobile/ios/app-shell/-/pipelines/old"
                },
                "head_pipeline": {
                  "status": "success",
                  "web_url": "https://gitlab.com/platform/mobile/ios/app-shell/-/pipelines/current"
                }
              }
            ]
            """,
          stderr: "",
          exitCode: 0,
        )
      },
    )
    let client = CLIForgeProviderClient.live(shell: shell)
    let remote = ForgeRemoteInfo(
      providerID: .gitLab,
      host: "gitlab.com",
      projectPath: "platform/mobile/ios/app-shell",
    )

    let result = try await client.batchPullRequests(remote, ["feature/provider"], URL(fileURLWithPath: "/repo"))

    let pullRequest = try #require(result["feature/provider"])
    #expect(pullRequest.statusCheckRollup?.checks.first?.checkState == .success)
    #expect(
      pullRequest.statusCheckRollup?.checks.first?.detailsUrl
        == "https://gitlab.com/platform/mobile/ios/app-shell/-/pipelines/current"
    )
  }

  @Test func executableAvailabilityFallsBackToLoginShellPath() async throws {
    let recorder = CLIForgeShellRecorder()
    let shell = ShellClient(
      run: { executableURL, arguments, _ in
        if executableURL.lastPathComponent == "which" {
          await recorder.recordWhich(arguments: arguments)
          throw ShellClientError(command: "which glab", stdout: "", stderr: "", exitCode: 1)
        }
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
      },
      runLoginImpl: { executableURL, arguments, _, _ in
        if executableURL.lastPathComponent == "which" {
          await recorder.recordLogin(arguments: arguments)
          return ShellOutput(stdout: "/Users/me/.local/bin/glab", stderr: "", exitCode: 0)
        }
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
      },
    )
    let client = CLIForgeProviderClient.live(shell: shell)

    let isAvailable = await client.isAvailable(.gitLab)

    #expect(isAvailable)
    let snapshot = await recorder.snapshot()
    #expect(snapshot.whichCalls == [["glab"]])
    #expect(snapshot.loginCalls == [["glab"]])
  }

  @Test func gitLabBatchPullRequestsReturnsEmptyForUnsupportedProvider() async throws {
    let client = CLIForgeProviderClient.live(shell: .testValue)
    let remote = ForgeRemoteInfo(host: "github.com", owner: "supabitapp", repo: "supacode")

    let result = try await client.batchPullRequests(remote, ["feature"], nil)

    #expect(result == [:])
  }

  @Test func customStatusChecksRenderTemplateAndDecodeDocumentedJSONShape() async throws {
    let recorder = CLIForgeShellRecorder()
    let shell = ShellClient(
      run: { _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) },
      runLoginImpl: { executableURL, arguments, currentDirectoryURL, _ in
        await recorder.recordLogin(arguments: [executableURL.path(percentEncoded: false)] + arguments)
        #expect(currentDirectoryURL == URL(fileURLWithPath: "/repo"))
        return ShellOutput(
          stdout: """
            {
              "checks": [
                {
                  "name": "Buildkite",
                  "status": "failed",
                  "detailsUrl": "https://ci.example/builds/1"
                }
              ]
            }
            """,
          stderr: "",
          exitCode: 0,
        )
      },
    )
    let client = CLIForgeProviderClient.live(shell: shell)
    let remote = ForgeRemoteInfo(
      providerID: .gitLab,
      host: "gitlab.com",
      projectPath: "platform/mobile/ios/app-shell",
    )
    let pullRequest = ForgePullRequest(
      providerID: .gitLab,
      providerCapabilities: ForgeProviderDescriptor.gitLab.capabilities,
      number: 42,
      title: "MR",
      state: "OPEN",
      additions: 0,
      deletions: 0,
      isDraft: false,
      reviewDecision: nil,
      mergeable: nil,
      mergeStateStatus: nil,
      updatedAt: nil,
      url: "https://gitlab.com/platform/mobile/ios/app-shell/-/merge_requests/42",
      headRefName: "feature/provider",
      baseRefName: "main",
      commitsCount: nil,
      authorLogin: nil,
      statusCheckRollup: nil,
      mergeQueueEntry: nil,
    )

    let checks = try await client.customStatusChecks(
      ForgeCustomCICommand(
        providerID: "gitlab",
        command: "ci-status --repo {{REPO_ROOT}} --branch {{BRANCH}} --host {{REMOTE_HOST}} "
          + "--project {{PROJECT_PATH}} --mr {{PULL_REQUEST_NUMBER}} --url {{PULL_REQUEST_URL}}",
      ),
      ForgeCustomCIContext(
        repoRoot: URL(fileURLWithPath: "/repo"),
        branch: "feature/provider",
        remote: remote,
        pullRequest: pullRequest,
      ),
    )

    #expect(
      checks == [
        ForgeStatusCheck(
          name: "Buildkite",
          detailsUrl: "https://ci.example/builds/1",
          state: "failed",
        )
      ])

    let snapshot = await recorder.snapshot()
    #expect(
      snapshot.loginCalls.first == [
        "/bin/zsh",
        "-lc",
        "ci-status --repo '/repo' --branch 'feature/provider' --host 'gitlab.com' "
          + "--project 'platform/mobile/ios/app-shell' --mr '42' "
          + "--url 'https://gitlab.com/platform/mobile/ios/app-shell/-/merge_requests/42'",
      ])
  }

  @Test func customStatusChecksShellQuotesTemplateValues() async throws {
    let recorder = CLIForgeShellRecorder()
    let shell = ShellClient(
      run: { _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) },
      runLoginImpl: { executableURL, arguments, _, _ in
        await recorder.recordLogin(arguments: [executableURL.path(percentEncoded: false)] + arguments)
        return ShellOutput(stdout: #"{"checks":[]}"#, stderr: "", exitCode: 0)
      },
    )
    let client = CLIForgeProviderClient.live(shell: shell)
    let remote = ForgeRemoteInfo(
      providerID: .gitLab,
      host: "gitlab.com",
      projectPath: "platform/mobile/ios/app shell",
    )
    let pullRequest = ForgePullRequest(
      providerID: .gitLab,
      providerCapabilities: ForgeProviderDescriptor.gitLab.capabilities,
      number: 42,
      title: "MR",
      state: "OPEN",
      additions: 0,
      deletions: 0,
      isDraft: false,
      reviewDecision: nil,
      mergeable: nil,
      mergeStateStatus: nil,
      updatedAt: nil,
      url: "https://gitlab.com/platform/mobile/ios/app-shell/-/merge_requests/42?x='y'",
      headRefName: "feature/provider'; rm -rf / #",
      baseRefName: "main",
      commitsCount: nil,
      authorLogin: nil,
      statusCheckRollup: nil,
      mergeQueueEntry: nil,
    )

    _ = try await client.customStatusChecks(
      ForgeCustomCICommand(
        providerID: "gitlab",
        command: "ci-status --branch {{BRANCH}} --project {{PROJECT_PATH}} --url {{PULL_REQUEST_URL}}",
      ),
      ForgeCustomCIContext(
        repoRoot: URL(fileURLWithPath: "/repo"),
        branch: "feature/provider'; rm -rf / #",
        remote: remote,
        pullRequest: pullRequest,
      ),
    )

    let snapshot = await recorder.snapshot()
    #expect(
      snapshot.loginCalls.first == [
        "/bin/zsh",
        "-lc",
        "ci-status --branch 'feature/provider'\\''; rm -rf / #' "
          + "--project 'platform/mobile/ios/app shell' "
          + "--url 'https://gitlab.com/platform/mobile/ios/app-shell/-/merge_requests/42?x='\\''y'\\'''",
      ])
  }
}
