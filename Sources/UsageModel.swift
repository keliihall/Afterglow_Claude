import Foundation
import Combine
import CommonCrypto
import Security

/// One usage limit window (e.g. the rolling 5-hour, or the weekly all-models).
struct UsageRow: Identifiable {
    let id: String
    let label: String        // "5h" / "1w" / model name for scoped
    let usedPercent: Double   // 0...100
    let resetsAt: Date?
    let severity: String      // normal / warning / critical
    let isActive: Bool
    var remaining: Double { max(0, 100 - usedPercent) }
}

/// Fetches the REAL Anthropic plan usage (same data as Claude's tray "Plan usage"
/// panel) via the OAuth endpoint `/api/oauth/usage`, using the access token that
/// the Claude desktop app stores (Electron safeStorage–encrypted) in config.json.
final class UsageModel: ObservableObject {
    @Published var rows: [UsageRow] = []
    @Published var tier: String = ""          // e.g. "max"
    @Published var lastUpdated: Date?
    @Published var status: String = "加载中…"
    @Published var ok = false

    private let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    func start() { refresh() }

    func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            guard let creds = TokenStore.current() else {
                self.publish(status: "未找到 Claude 登录信息", ok: false)
                return
            }
            self.tierCache = creds.tier
            self.fetch(token: creds.token)
        }
    }

    private var tierCache = ""

    private func fetch(token: String) {
        var req = URLRequest(url: endpoint, timeoutInterval: 15)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("claude-cli/2.1.187 (external, cli)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
            guard let self else { return }
            if let err { self.publish(status: "网络错误", ok: false); _ = err; return }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 || code == 403 {
                self.publish(status: "登录过期，请打开 Claude", ok: false)
                return
            }
            guard code == 200, let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                self.publish(status: "数据读取失败(\(code))", ok: false)
                return
            }
            let rows = Self.parse(obj)
            DispatchQueue.main.async {
                self.rows = rows
                self.tier = self.tierCache
                self.ok = true
                self.status = ""
                self.lastUpdated = Date()
            }
        }.resume()
    }

    private func publish(status: String, ok: Bool) {
        DispatchQueue.main.async {
            self.status = status
            self.ok = ok
            if !ok { self.lastUpdated = self.lastUpdated }
        }
    }

    // MARK: - Parsing

    private static let iso: [ISO8601DateFormatter] = {
        let a = ISO8601DateFormatter(); a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let b = ISO8601DateFormatter(); b.formatOptions = [.withInternetDateTime]
        return [a, b]
    }()
    private static func date(_ s: Any?) -> Date? {
        guard let s = s as? String else { return nil }
        for f in iso { if let d = f.date(from: s) { return d } }
        return nil
    }

    /// Prefer the structured `limits` array; show 5h + weekly-all always, plus any
    /// scoped (per-model) window that is actually being used.
    static func parse(_ obj: [String: Any]) -> [UsageRow] {
        var out: [UsageRow] = []
        if let limits = obj["limits"] as? [[String: Any]] {
            for l in limits {
                let kind = l["kind"] as? String ?? ""
                let pct = (l["percent"] as? NSNumber)?.doubleValue ?? 0
                let sev = l["severity"] as? String ?? "normal"
                let active = l["is_active"] as? Bool ?? false
                let reset = date(l["resets_at"])
                switch kind {
                case "session":
                    out.append(UsageRow(id: "5h", label: "5h", usedPercent: pct, resetsAt: reset, severity: sev, isActive: active))
                case "weekly_all":
                    out.append(UsageRow(id: "1w", label: "1w", usedPercent: pct, resetsAt: reset, severity: sev, isActive: active))
                case "weekly_scoped":
                    let scope = l["scope"] as? [String: Any]
                    let model = (scope?["model"] as? [String: Any])?["display_name"] as? String ?? "scoped"
                    if pct > 0 {  // only surface a scoped cap once it's in play
                        out.append(UsageRow(id: "scoped-\(model)", label: model, usedPercent: pct, resetsAt: reset, severity: sev, isActive: active))
                    }
                default: break
                }
            }
        }
        // Fallback to named windows if `limits` was absent.
        if out.isEmpty {
            func window(_ key: String, _ label: String) {
                guard let w = obj[key] as? [String: Any],
                      let u = (w["utilization"] as? NSNumber)?.doubleValue else { return }
                out.append(UsageRow(id: label, label: label, usedPercent: u, resetsAt: date(w["resets_at"]), severity: "normal", isActive: label == "5h"))
            }
            window("five_hour", "5h")
            window("seven_day", "1w")
        }
        return out
    }
}

// MARK: - OAuth token from the Claude desktop app (Electron safeStorage)

enum TokenStore {
    struct Creds { let token: String; let tier: String }

    private static let configPath =
        (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/Claude/config.json")

    /// Reads + decrypts the current claude_code OAuth access token.
    static func current() -> Creds? {
        guard let data = FileManager.default.contents(atPath: configPath),
              let cfg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pw = safeStorageKey() else { return nil }
        let key = pbkdf2SHA1(password: [UInt8](pw), salt: Array("saltysalt".utf8), iterations: 1003, keyLen: 16)
        guard !key.isEmpty else { return nil }

        for cacheKey in ["oauth:tokenCacheV2", "oauth:tokenCache"] {
            guard let enc = cfg[cacheKey] as? String,
                  let plain = decryptSafeStorage(enc, key: key),
                  let cache = try? JSONSerialization.jsonObject(with: plain) as? [String: Any] else { continue }
            // Prefer the entry whose composite key includes the claude_code scope.
            var fallback: (token: String, tier: String)?
            for (compositeKey, value) in cache {
                guard let v = value as? [String: Any], let token = v["token"] as? String else { continue }
                let tier = v["subscriptionType"] as? String ?? ""
                if compositeKey.contains("claude_code") { return Creds(token: token, tier: tier) }
                if fallback == nil { fallback = (token, tier) }
            }
            if let f = fallback { return Creds(token: f.token, tier: f.tier) }
        }
        return nil
    }

    /// macOS keychain generic password "Claude Safe Storage" (the Electron app's key).
    /// First read may show a one-time keychain permission prompt — click Always Allow.
    private static func safeStorageKey() -> Data? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Safe Storage",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return nil }
        return d
    }

    private static func pbkdf2SHA1(password: [UInt8], salt: [UInt8], iterations: Int, keyLen: Int) -> [UInt8] {
        var derived = [UInt8](repeating: 0, count: keyLen)
        let status = password.withUnsafeBufferPointer { pw in
            salt.withUnsafeBufferPointer { sa in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    UnsafeRawPointer(pw.baseAddress)?.assumingMemoryBound(to: Int8.self), pw.count,
                    sa.baseAddress, sa.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), UInt32(iterations),
                    &derived, keyLen)
            }
        }
        return status == kCCSuccess ? derived : []
    }

    private static func decryptSafeStorage(_ b64: String, key: [UInt8]) -> Data? {
        guard let raw = Data(base64Encoded: b64), raw.count > 3 else { return nil }
        let prefix = String(bytes: raw.prefix(3), encoding: .ascii)
        guard prefix == "v10" || prefix == "v11" else { return nil }
        let cipher = [UInt8](raw.dropFirst(3))
        let iv = [UInt8](repeating: 0x20, count: 16)
        var out = [UInt8](repeating: 0, count: cipher.count + kCCBlockSizeAES128)
        var moved = 0
        let st = cipher.withUnsafeBufferPointer { c in
            key.withUnsafeBufferPointer { k in
                iv.withUnsafeBufferPointer { i in
                    CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            k.baseAddress, k.count,
                            i.baseAddress,
                            c.baseAddress, c.count,
                            &out, out.count, &moved)
                }
            }
        }
        guard st == kCCSuccess else { return nil }
        return Data(out.prefix(moved))
    }
}

// MARK: - Formatting

enum Fmt {
    /// Reset time: within a day → "重置 12:29", otherwise → "重置 6/30".
    static func reset(_ d: Date?) -> String {
        guard let d else { return "" }
        let now = Date()
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        if d.timeIntervalSince(now) < 24 * 3600 && d.timeIntervalSince(now) > -3600 {
            f.dateFormat = "HH:mm"
        } else {
            f.dateFormat = "M/d"
        }
        return "重置 " + f.string(from: d)
    }
    static func clock(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}
