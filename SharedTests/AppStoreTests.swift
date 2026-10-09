import Foundation
import Testing

/// What the App Store asks of every bundle Bite ships, the app and each app or extension inside
/// it: a privacy manifest, and the app's own version and build.
@MainActor
struct AppStoreTests {
    /// The app and what's inside it, without the tests put in it for this run.
    private var bundles: [Bundle] {
        let inside = FileManager.default.enumerator(at: Bundle.main.bundleURL, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { ["app", "appex"].contains($0.pathExtension) }
            .compactMap(Bundle.init(url:)) ?? []
        return [Bundle.main] + inside
    }

    /// Each tracks no one and collects nothing, and gives Apple's reason for every kind of API it
    /// says it uses. Which kinds each uses is in its own `PrivacyInfo.xcprivacy`.
    @Test func everyBundleHasAPrivacyManifest() throws {
        #expect(bundles.count > 1)
        for bundle in bundles {
            let name = bundle.bundleURL.lastPathComponent
            guard let url = bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy") else {
                Issue.record("\(name) has no privacy manifest")
                continue
            }
            let data = try Data(contentsOf: url)
            let manifest = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any], "\(name)")
            #expect(manifest["NSPrivacyTracking"] as? Bool == false, "\(name)")
            #expect((manifest["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty == true, "\(name)")
            #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true, "\(name)")
            let apis = manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
            #expect(apis != nil, "\(name)")
            for api in apis ?? [] {
                let kind = api["NSPrivacyAccessedAPIType"] as? String ?? "?"
                #expect((api["NSPrivacyAccessedAPITypeReasons"] as? [String])?.isEmpty == false, "\(name): \(kind)")
            }
        }
    }

    @Test func everyBundleHasTheAppsVersion() {
        for key in ["CFBundleShortVersionString", "CFBundleVersion"] {
            let apps = Bundle.main.infoDictionary?[key] as? String
            for bundle in bundles.dropFirst() {
                #expect(bundle.infoDictionary?[key] as? String == apps, "\(bundle.bundleURL.lastPathComponent) \(key)")
            }
        }
    }
}
