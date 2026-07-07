import Foundation

/// Picks the installable artifacts from a release's assets by name convention:
/// `*.dmg` is the app image and `*.dmg.sha256` its checksum sidecar.
public enum UpdateAssets {
    public static func select(from assets: [ReleaseAsset]) -> (dmg: URL?, checksum: URL?) {
        let dmg = assets.first { $0.name.hasSuffix(".dmg") }?.downloadURL
        let checksum = assets.first { $0.name.hasSuffix(".dmg.sha256") }?.downloadURL
        return (dmg, checksum)
    }
}
