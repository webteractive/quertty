import Foundation

/// One downloadable asset attached to a GitHub release.
public struct ReleaseAsset: Equatable {
    public let name: String
    public let downloadURL: URL

    public init(name: String, downloadURL: URL) {
        self.name = name
        self.downloadURL = downloadURL
    }
}
