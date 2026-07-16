import AppAccount
import Foundation
import Models

@main
@MainActor
struct IceCubesSeedAccount {
    static func main() throws {
        let env = ProcessInfo.processInfo.environment
        let server = nonEmpty(env["QUILLUI_ICECUBES_SEED_SERVER"], default: "mastodon.social")
        let accountName = nonEmpty(env["QUILLUI_ICECUBES_SEED_ACCOUNT_NAME"], default: "quill@mastodon.social")
        let accessToken = nonEmpty(env["QUILLUI_ICECUBES_SEED_ACCESS_TOKEN"], default: "quillui-fixture-token")
        let tokenType = nonEmpty(env["QUILLUI_ICECUBES_SEED_TOKEN_TYPE"], default: "Bearer")
        let scope = nonEmpty(env["QUILLUI_ICECUBES_SEED_SCOPE"], default: "read write follow push")
        let createdAt = Double(nonEmpty(env["QUILLUI_ICECUBES_SEED_CREATED_AT"], default: "1700000000")) ?? 1_700_000_000
        let defaultsDomain = nonEmpty(
            env["QUILLUI_ICECUBES_SEED_DEFAULTS_DOMAIN"],
            default: "icecubes-linux-app"
        )
        let statusActionSecondary = env["QUILLUI_ICECUBES_SEED_STATUS_ACTION_SECONDARY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let token = OauthToken(
            accessToken: accessToken,
            tokenType: tokenType,
            scope: scope,
            createdAt: createdAt
        )
        let account = AppAccount(
            server: server,
            accountName: accountName,
            oauthToken: token
        )

        try account.save()
        AppAccountsManager.latestCurrentAccountKey = account.id
        if let statusActionSecondary, !statusActionSecondary.isEmpty {
            let appDefaults = UserDefaults(suiteName: defaultsDomain) ?? .standard
            appDefaults.set(statusActionSecondary, forKey: "statusActionSecondary")
            appDefaults.synchronize()
        }
        resetDisplayDefaults(defaultsDomain: defaultsDomain)
        print("Seeded IceCubes account \(account.id)")
    }

    private static func resetDisplayDefaults(defaultsDomain: String) {
        let stores = [
            UserDefaults.standard,
            UserDefaults(suiteName: defaultsDomain),
            UserDefaults(suiteName: "group.com.thomasricouard.IceCubesApp"),
        ].compactMap { $0 }

        for store in stores {
            store.removeObject(forKey: "chosen_font")
            store.set(1.0, forKey: "font_size_scale")
            store.set(true, forKey: "is_previously_set")
            store.set("light", forKey: "selectedScheme")
            store.set("Ice Cube - Light", forKey: "selectedSet")
            store.set(false, forKey: "followSystemColorSchme")
            store.set(0xBB3BE2, forKey: "tint")
            store.set(0xFFFFFF, forKey: "primaryBackground")
            store.set(0xF0F1F2, forKey: "secondaryBackground")
            store.set(0x000000, forKey: "label")
            store.synchronize()
        }
    }

    private static func nonEmpty(_ value: String?, default defaultValue: String) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultValue
        }
        return value
    }
}
