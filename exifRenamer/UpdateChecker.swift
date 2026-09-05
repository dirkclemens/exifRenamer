//
//  UpdateChecker.swift
//  exifRenamer
//

import Foundation

/// Fire-and-forget "is a newer version available" check against
/// https://api.adcore.de/apps/check.php. Purely informational for now —
/// the result is only logged, nothing else happens with it yet.
enum UpdateChecker {
    private static let appIdentifier = "exifRenamer"
    private static let endpoint = URL(string: "https://api.adcore.de/apps/check.php")!

    static func checkForUpdate() {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "app", value: appIdentifier),
            URLQueryItem(name: "version", value: version),
            URLQueryItem(name: "os", value: ProcessInfo.processInfo.operatingSystemVersionString),
            URLQueryItem(name: "arch", value: currentArchitecture),
        ]
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.setValue("\(appIdentifier)/\(version)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data, error == nil,
                  let result = try? JSONDecoder().decode(UpdateCheckResponse.self, from: data)
            else { return }
            #if DEBUG
            print("UpdateChecker: current=\(result.currentVersion ?? "?") latest=\(result.latestVersion ?? "?") updateAvailable=\(result.updateAvailable ?? false)")
            #endif
        }.resume()
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}

private struct UpdateCheckResponse: Decodable {
    let app: String?
    let currentVersion: String?
    let latestVersion: String?
    let updateAvailable: Bool?
    let downloadURL: String?

    enum CodingKeys: String, CodingKey {
        case app
        case currentVersion = "current_version"
        case latestVersion = "latest_version"
        case updateAvailable = "update_available"
        case downloadURL = "download_url"
    }
}
