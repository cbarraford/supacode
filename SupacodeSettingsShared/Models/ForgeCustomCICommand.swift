import Foundation

public nonisolated struct ForgeCustomCICommand: Codable, Equatable, Sendable {
  public var providerID: String
  public var command: String

  public init(providerID: String, command: String) {
    self.providerID = providerID
    self.command = command
  }
}
