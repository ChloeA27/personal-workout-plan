import Foundation
import Security

enum GitHubUploaderError: Error, LocalizedError {
    case missingToken
    case badResponse(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "还没有设置 GitHub Token"
        case .badResponse(let code, let body):
            return "GitHub API 返回 \(code): \(body)"
        }
    }
}

final class GitHubUploader {
    static let shared = GitHubUploader()

    // 按你的仓库改这两个值
    private let owner = "chloea27"
    private let repo = "personal-workout-plan"
    private let branch = "main"

    private var token: String? {
        KeychainStore.shared.read(key: "github_token")
    }

    func upload(summary: DailyHealthSummary) async throws {
        guard let token else { throw GitHubUploaderError.missingToken }

        let path = "health-data/\(summary.date).json"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(summary)
        let base64Content = jsonData.base64EncodedString()

        let existingSHA = try? await fetchExistingSHA(path: path, token: token)

        var request = URLRequest(url: contentsURL(path: path))
        request.httpMethod = "PUT"
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        var body: [String: Any] = [
            "message": "health data: \(summary.date)",
            "content": base64Content,
            "branch": branch,
        ]
        if let existingSHA {
            body["sha"] = existingSHA
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw GitHubUploaderError.badResponse(code, bodyText)
        }
    }

    private func fetchExistingSHA(path: String, token: String) async throws -> String? {
        var request = URLRequest(url: contentsURL(path: path, ref: branch))
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["sha"] as? String
    }

    private func contentsURL(path: String, ref: String? = nil) -> URL {
        var components = URLComponents(string: "https://api.github.com/repos/\(owner)/\(repo)/contents/\(path)")!
        if let ref {
            components.queryItems = [URLQueryItem(name: "ref", value: ref)]
        }
        return components.url!
    }
}

/// 极简 Keychain 封装，只用来存这一个 token
final class KeychainStore {
    static let shared = KeychainStore()
    private let service = "com.chloea27.HealthExporter"

    func save(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
