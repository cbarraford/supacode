import Foundation

nonisolated struct ForgePullRequest: Decodable, Equatable, Hashable {
  let providerID: ForgeProviderID
  let providerCapabilities: Set<ForgeCapability>
  let number: Int
  let title: String
  let state: String
  let additions: Int
  let deletions: Int
  let isDraft: Bool
  let reviewDecision: String?
  let mergeable: String?
  let mergeStateStatus: String?
  let updatedAt: Date?
  let url: String
  let headRefName: String?
  let baseRefName: String?
  let commitsCount: Int?
  let authorLogin: String?
  let statusCheckRollup: ForgeStatusCheckRollup?
  let mergeQueueEntry: GithubMergeQueueEntry?

  init(
    providerID: ForgeProviderID = .github,
    providerCapabilities: Set<ForgeCapability> = ForgeProviderDescriptor.github.capabilities,
    number: Int,
    title: String,
    state: String,
    additions: Int,
    deletions: Int,
    isDraft: Bool,
    reviewDecision: String?,
    mergeable: String?,
    mergeStateStatus: String?,
    updatedAt: Date?,
    url: String,
    headRefName: String?,
    baseRefName: String?,
    commitsCount: Int?,
    authorLogin: String?,
    statusCheckRollup: ForgeStatusCheckRollup?,
    mergeQueueEntry: GithubMergeQueueEntry?,
  ) {
    self.providerID = providerID
    self.providerCapabilities = providerCapabilities
    self.number = number
    self.title = title
    self.state = state
    self.additions = additions
    self.deletions = deletions
    self.isDraft = isDraft
    self.reviewDecision = reviewDecision
    self.mergeable = mergeable
    self.mergeStateStatus = mergeStateStatus
    self.updatedAt = updatedAt
    self.url = url
    self.headRefName = headRefName
    self.baseRefName = baseRefName
    self.commitsCount = commitsCount
    self.authorLogin = authorLogin
    self.statusCheckRollup = statusCheckRollup
    self.mergeQueueEntry = mergeQueueEntry
  }

  private enum CodingKeys: String, CodingKey {
    case providerID
    case providerCapabilities
    case number
    case title
    case state
    case additions
    case deletions
    case isDraft
    case reviewDecision
    case mergeable
    case mergeStateStatus
    case updatedAt
    case url
    case headRefName
    case baseRefName
    case commitsCount
    case authorLogin
    case statusCheckRollup
    case mergeQueueEntry
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let providerID = try container.decodeIfPresent(ForgeProviderID.self, forKey: .providerID) ?? .github
    let descriptor = ForgeProviderRegistry.bundled.descriptor(for: providerID)
    self.providerID = providerID
    self.providerCapabilities =
      try container.decodeIfPresent(Set<ForgeCapability>.self, forKey: .providerCapabilities)
      ?? descriptor?.capabilities
      ?? []
    self.number = try container.decode(Int.self, forKey: .number)
    self.title = try container.decode(String.self, forKey: .title)
    self.state = try container.decode(String.self, forKey: .state)
    self.additions = try container.decodeIfPresent(Int.self, forKey: .additions) ?? 0
    self.deletions = try container.decodeIfPresent(Int.self, forKey: .deletions) ?? 0
    self.isDraft = try container.decodeIfPresent(Bool.self, forKey: .isDraft) ?? false
    self.reviewDecision = try container.decodeIfPresent(String.self, forKey: .reviewDecision)
    self.mergeable = try container.decodeIfPresent(String.self, forKey: .mergeable)
    self.mergeStateStatus = try container.decodeIfPresent(String.self, forKey: .mergeStateStatus)
    self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    self.url = try container.decode(String.self, forKey: .url)
    self.headRefName = try container.decodeIfPresent(String.self, forKey: .headRefName)
    self.baseRefName = try container.decodeIfPresent(String.self, forKey: .baseRefName)
    self.commitsCount = try container.decodeIfPresent(Int.self, forKey: .commitsCount)
    self.authorLogin = try container.decodeIfPresent(String.self, forKey: .authorLogin)
    self.statusCheckRollup = try container.decodeIfPresent(ForgeStatusCheckRollup.self, forKey: .statusCheckRollup)
    self.mergeQueueEntry = try container.decodeIfPresent(GithubMergeQueueEntry.self, forKey: .mergeQueueEntry)
  }

  var providerDescriptor: ForgeProviderDescriptor? {
    ForgeProviderRegistry.bundled.descriptor(for: providerID)
  }

  func supports(_ capability: ForgeCapability) -> Bool {
    providerCapabilities.contains(capability)
  }

  func addingStatusChecks(_ checks: [ForgeStatusCheck]) -> ForgePullRequest {
    guard !checks.isEmpty else {
      return self
    }
    let existingChecks = statusCheckRollup?.checks ?? []
    return ForgePullRequest(
      providerID: providerID,
      providerCapabilities: providerCapabilities,
      number: number,
      title: title,
      state: state,
      additions: additions,
      deletions: deletions,
      isDraft: isDraft,
      reviewDecision: reviewDecision,
      mergeable: mergeable,
      mergeStateStatus: mergeStateStatus,
      updatedAt: updatedAt,
      url: url,
      headRefName: headRefName,
      baseRefName: baseRefName,
      commitsCount: commitsCount,
      authorLogin: authorLogin,
      statusCheckRollup: ForgeStatusCheckRollup(checks: existingChecks + checks),
      mergeQueueEntry: mergeQueueEntry,
    )
  }

  var pullRequestAbbreviation: String {
    providerDescriptor?.pullRequestAbbreviation ?? "PR"
  }

  var pullRequestName: String {
    providerDescriptor?.pullRequestName ?? "pull request"
  }

  var pullRequestNameCapitalized: String {
    pullRequestName.prefix(1).uppercased() + pullRequestName.dropFirst()
  }

  var providerDisplayName: String {
    providerDescriptor?.displayName ?? "Forge"
  }

  var openHelpText: String {
    "Open \(pullRequestName) on \(providerDisplayName)"
  }
}

typealias GithubPullRequest = ForgePullRequest
