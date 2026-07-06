import Foundation
import ZettyCore

/// A newer release available for download.
struct AvailableUpdate: Equatable {
    let version: String   // e.g. "0.1.7"
    let url: URL          // release page
}

/// Checks the public GitHub releases API for a newer version. Notify-only.
final class UpdateChecker {
    private static let endpoint = URL(string:
        "https://api.github.com/repos/webteractive/zetty/releases/latest")!
    private static let releasesPage = URL(string:
        "https://github.com/webteractive/zetty/releases/latest")!

    private let currentVersion: String

    init(currentVersion: String) { self.currentVersion = currentVersion }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: String
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    enum CheckError: Error { case badResponse }

    /// Fetches the latest release; completion runs on the main queue with an
    /// `AvailableUpdate` when newer, `nil` when up to date, or an error.
    func check(completion: @escaping (Result<AvailableUpdate?, Error>) -> Void) {
        // A dev/unparseable current version can never be "behind" — skip.
        guard SemVer(currentVersion) != nil else {
            DispatchQueue.main.async { completion(.success(nil)) }
            return
        }
        var request = URLRequest(url: Self.endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { data, _, error in
            let result: Result<AvailableUpdate?, Error>
            if let error {
                result = .failure(error)
            } else if let data, let release = try? JSONDecoder().decode(Release.self, from: data) {
                if SemVer.isNewer(latest: release.tagName, than: self.currentVersion) {
                    let version = release.tagName.hasPrefix("v")
                        ? String(release.tagName.dropFirst()) : release.tagName
                    let url = URL(string: release.htmlURL) ?? Self.releasesPage
                    result = .success(AvailableUpdate(version: version, url: url))
                } else {
                    result = .success(nil)
                }
            } else {
                result = .failure(CheckError.badResponse)
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}
