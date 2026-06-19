import Testing

@testable import supacode

struct ForgeProviderTests {
  @Test func parseForgeRemoteInfoRecognizesGithubRemote() {
    let info = GitClient.parseForgeRemoteInfo("git@github.com:supabitapp/supacode.git")

    #expect(info?.providerID == .github)
    #expect(info?.host == "github.com")
    #expect(info?.projectPath == "supabitapp/supacode")
    #expect(info?.owner == "supabitapp")
    #expect(info?.repo == "supacode")
  }

  @Test func parseForgeRemoteInfoRecognizesGitLabNestedProjectRemote() {
    let info = GitClient.parseForgeRemoteInfo("git@gitlab.com:platform/mobile/ios/app-shell.git")

    #expect(info?.providerID == .gitLab)
    #expect(info?.host == "gitlab.com")
    #expect(info?.projectPath == "platform/mobile/ios/app-shell")
    #expect(info?.owner == "platform/mobile/ios")
    #expect(info?.repo == "app-shell")
  }

  @Test func parseForgeRemoteInfoRecognizesSelfHostedGitLabRemote() {
    let info = GitClient.parseForgeRemoteInfo("git@gitlab.example.com:platform/mobile/ios/app-shell.git")

    #expect(info?.providerID == .gitLab)
    #expect(info?.host == "gitlab.example.com")
    #expect(info?.projectPath == "platform/mobile/ios/app-shell")
  }

  @Test func parseForgeRemoteInfoReturnsNilForUnknownHost() {
    let info = GitClient.parseForgeRemoteInfo("git@example.com:platform/mobile/ios/app-shell.git")

    #expect(info == nil)
  }

  @Test func parseForgeRemoteInfoDoesNotMatchProviderNameInsideHostLabel() {
    let info = GitClient.parseForgeRemoteInfo("git@notgithub.example.com:supabitapp/supacode.git")

    #expect(info == nil)
  }

  @Test func bundledRegistryKeepsGitLabReadOnly() {
    let registry = ForgeProviderRegistry.bundled
    let gitLab = registry.descriptor(for: .gitLab)

    #expect(gitLab?.capabilities.contains(.pullRequestStatus) == true)
    #expect(gitLab?.capabilities.contains(.openPullRequest) == true)
    #expect(gitLab?.capabilities.contains(.ciStatus) == true)
    #expect(gitLab?.capabilities.contains(.merge) == false)
    #expect(gitLab?.capabilities.contains(.close) == false)
    #expect(gitLab?.capabilities.contains(.markReady) == false)
    #expect(gitLab?.capabilities.contains(.ciLogs) == false)
    #expect(gitLab?.capabilities.contains(.rerunFailedJobs) == false)
  }
}
