import Foundation

nonisolated struct ForgeProviderID: RawRepresentable, Codable, Equatable, Hashable, Sendable {
  let rawValue: String

  init(rawValue: String) {
    self.rawValue = rawValue
  }

  init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.rawValue = try container.decode(String.self)
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  static let github = ForgeProviderID("github")
  static let gitLab = ForgeProviderID("gitlab")
}

nonisolated enum ForgeCapability: String, Codable, CaseIterable, Hashable, Sendable {
  case pullRequestStatus
  case openPullRequest
  case markReady
  case merge
  case close
  case ciStatus
  case ciLogs
  case rerunFailedJobs
}

nonisolated struct ForgeProviderDescriptor: Equatable, Sendable {
  let id: ForgeProviderID
  let displayName: String
  let pullRequestAbbreviation: String
  let pullRequestName: String
  let executableName: String
  let capabilities: Set<ForgeCapability>
  let hostKeywords: [String]

  func matches(host: String) -> Bool {
    let normalizedHost = host.lowercased()
    let hostLabels = Set(normalizedHost.split(separator: ".").map(String.init))
    return hostKeywords.contains { keyword in
      let normalizedKeyword = keyword.lowercased()
      return normalizedHost == normalizedKeyword
        || normalizedHost.hasSuffix(".\(normalizedKeyword)")
        || hostLabels.contains(normalizedKeyword)
    }
  }

  static let github = ForgeProviderDescriptor(
    id: .github,
    displayName: "GitHub",
    pullRequestAbbreviation: "PR",
    pullRequestName: "pull request",
    executableName: "gh",
    capabilities: Set(ForgeCapability.allCases),
    hostKeywords: ["github"],
  )

  static let gitLab = ForgeProviderDescriptor(
    id: .gitLab,
    displayName: "GitLab",
    pullRequestAbbreviation: "MR",
    pullRequestName: "merge request",
    executableName: "glab",
    capabilities: [
      .pullRequestStatus,
      .openPullRequest,
      .ciStatus,
    ],
    hostKeywords: ["gitlab"],
  )
}

nonisolated struct ForgeProviderRegistry: Equatable, Sendable {
  let descriptors: [ForgeProviderDescriptor]

  static let bundled = ForgeProviderRegistry(descriptors: [
    .github,
    .gitLab,
  ])

  func descriptor(for id: ForgeProviderID) -> ForgeProviderDescriptor? {
    descriptors.first { $0.id == id }
  }

  func descriptor(matchingHost host: String) -> ForgeProviderDescriptor? {
    descriptors.first { $0.matches(host: host) }
  }
}

nonisolated struct ForgeRemoteInfo: Equatable, Sendable {
  let providerID: ForgeProviderID
  let host: String
  let projectPath: String
  let owner: String
  let repo: String

  init(providerID: ForgeProviderID, host: String, projectPath: String) {
    let normalizedPath = Self.normalizedProjectPath(projectPath)
    let components = normalizedPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    self.providerID = providerID
    self.host = host
    self.projectPath = normalizedPath
    self.owner = components.dropLast().joined(separator: "/")
    self.repo = components.last ?? ""
  }

  init(host: String, owner: String, repo: String) {
    self.providerID = .github
    self.host = host
    self.owner = owner
    self.repo = repo
    self.projectPath = "\(owner)/\(repo)"
  }

  var descriptor: ForgeProviderDescriptor? {
    ForgeProviderRegistry.bundled.descriptor(for: providerID)
  }

  private static func normalizedProjectPath(_ path: String) -> String {
    let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/ \n\r\t"))
    guard trimmed.hasSuffix(".git") else {
      return trimmed
    }
    return String(trimmed.dropLast(4))
  }
}

typealias GithubRemoteInfo = ForgeRemoteInfo
