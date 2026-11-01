import Foundation

/// Bite's voice relay (Server/voice): it hands out short-lived Soniox keys to transcribe with, and
/// has Claude tidy what was said, so neither service's own key is ever in the app.
nonisolated struct VoiceRelay: Sendable {
    let url: URL
    let token: String

    /// The relay Bite was built with, from VoiceRelay.plist: none in a build without one, which
    /// then has no voice input. The plist holds the token the relay lets Bite in by, so it's kept
    /// out of git; Server/voice/app-config.sh makes it.
    static let shared: VoiceRelay? = {
        guard let file = Bundle.main.url(forResource: "VoiceRelay", withExtension: "plist"),
              let values = NSDictionary(contentsOf: file),
              let address = values["URL"] as? String, let url = URL(string: address),
              let token = values["Token"] as? String, !token.isEmpty else { return nil }
        return VoiceRelay(url: url, token: token)
    }()

    struct Failure: LocalizedError {
        let status: Int
        var errorDescription: String? { "The voice relay answered \(status)." }
    }

    /// A tidy that stopped before Claude finished it.
    struct CutShort: Error {}

    /// What the relay sends after the tidy text once Claude has finished it (Server/voice
    /// src/written.ts). A reply without it was cut short: by Claude reaching how much it may
    /// write, after a long recording, or by a failure on the way.
    static let finished: Character = "\u{4}"

    /// A Soniox key for one live transcription, to be used within 5 minutes, once.
    func sonioxKey() async throws -> String {
        let (data, response) = try await URLSession.shared.data(for: request("v1/soniox-key", body: nil))
        try check(response)
        struct Key: Decodable {
            let api_key: String
        }
        return try JSONDecoder().decode(Key.self, from: data).api_key
    }

    /// `said`, written into a page after `page`, tidied by Claude: into what one person speaking
    /// meant to write there, or with several speaking, only cleaned up. Throws unless all of it
    /// came.
    func tidy(_ said: String, after page: String, speakers: Int) async throws -> String {
        struct Body: Encodable {
            let said: String
            let page: String
            let speakers: Int
        }
        let body = try JSONEncoder().encode(Body(said: said, page: page, speakers: speakers))
        let (data, response) = try await URLSession.shared.data(for: request("v1/tidy", body: body))
        try check(response)
        return try Self.whole(String(decoding: data, as: UTF8.self))
    }

    /// The tidy text in a reply, as long as all of it came: put in place of everything said, the
    /// part that came would lose the rest.
    static func whole(_ reply: String) throws -> String {
        guard reply.last == finished else { throw CutShort() }
        return String(reply.dropLast())
    }

    private func request(_ path: String, body: Data?) -> URLRequest {
        var request = URLRequest(url: url.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }

    private func check(_ response: URLResponse) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure(status: status) }
    }
}
