import Foundation

/// One live transcription by Soniox, over a WebSocket: audio in as it's recorded, words out as
/// they're heard, Chinese and English mixed as they're said. Audio sent before the socket is open
/// waits for it, so recording starts at the tap, before the relay has handed over a key.
nonisolated final class SonioxSession: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    nonisolated enum Event: Sendable {
        /// Words heard for good since the last ones, and after them those still being made out,
        /// which the next words heard replace.
        case words(final: String, pending: String)
        /// All the audio sent has been heard.
        case finished
        case failed(String)
    }

    /// What's heard, as it is, till the transcription's over: finished, failed or cancelled.
    let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation
    /// Everything happens on this queue: the socket's callbacks, and what's sent to it.
    private let queue = DispatchQueue(label: "com.chenyeni.bite.soniox")
    private let configuration: String
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var isOpen = false
    /// Audio sent before the socket opened, sent once it is.
    private var waiting: [Data] = []
    private var isFinishing = false
    private var isOver = false
    private var lastPending = ""

    /// `configuration` is Soniox's, the first thing sent: the model, the audio's format, the
    /// languages to expect, and what to hear the words against.
    init(configuration: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: configuration)) ?? Data()
        self.configuration = String(decoding: data, as: UTF8.self)
        (events, continuation) = AsyncStream.makeStream(of: Event.self)
        super.init()
    }

    /// Opens the socket with a key from the relay.
    func connect(key: String) {
        queue.async { [self] in
            guard !isOver, let url = URL(string: "wss://stt-rt.soniox.com/transcribe-websocket") else { return }
            let delegateQueue = OperationQueue()
            delegateQueue.underlyingQueue = queue
            delegateQueue.maxConcurrentOperationCount = 1
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: delegateQueue)
            var request = URLRequest(url: url)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let task = session.webSocketTask(with: request)
            self.session = session
            self.task = task
            task.resume()
            receive()
        }
    }

    func send(_ audio: Data) {
        queue.async { [self] in
            guard !isOver, !isFinishing else { return }
            if isOpen {
                task?.send(.data(audio)) { _ in }
            } else {
                waiting.append(audio)
            }
        }
    }

    /// Says the audio's all sent: the last words come, and then `finished`.
    func finish() {
        queue.async { [self] in
            guard !isOver, !isFinishing else { return }
            isFinishing = true
            if isOpen { task?.send(.string("")) { _ in } }
        }
    }

    /// Ends it now, with nothing more heard.
    func cancel() {
        queue.async { [self] in
            end(with: nil)
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        guard !isOver else { return }
        isOpen = true
        webSocketTask.send(.string(configuration)) { _ in }
        for audio in waiting {
            webSocketTask.send(.data(audio)) { _ in }
        }
        waiting.removeAll()
        if isFinishing { webSocketTask.send(.string("")) { _ in } }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        end(with: .failed(error?.localizedDescription ?? "The connection closed."))
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            queue.async { self.handle(result) }
        }
    }

    private func handle(_ result: Result<URLSessionWebSocketTask.Message, any Error>) {
        guard !isOver else { return }
        switch result {
        case .failure(let error):
            end(with: .failed(error.localizedDescription))
        case .success(.string(let text)):
            read(Data(text.utf8))
        case .success(.data(let data)):
            read(data)
        case .success:
            break
        }
        if !isOver { receive() }
    }

    private nonisolated struct Response: Decodable {
        nonisolated struct Token: Decodable {
            let text: String
            let is_final: Bool
        }

        let tokens: [Token]?
        let finished: Bool?
        let error_type: String?
        let error_message: String?
    }

    private func read(_ data: Data) {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return }
        if let error = response.error_message ?? response.error_type {
            end(with: .failed(error))
            return
        }
        var final = ""
        var pending = ""
        // `<end>` marks where the speaker paused, `<fin>` where the words were made final on
        // request: neither is a word.
        for token in response.tokens ?? [] where token.text != "<end>" && token.text != "<fin>" {
            if token.is_final {
                final += token.text
            } else {
                pending += token.text
            }
        }
        if !final.isEmpty || pending != lastPending {
            lastPending = pending
            continuation.yield(.words(final: final, pending: pending))
        }
        if response.finished == true { end(with: .finished) }
    }

    private func end(with event: Event?) {
        guard !isOver else { return }
        isOver = true
        if let event { continuation.yield(event) }
        continuation.finish()
        waiting.removeAll()
        task?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()
    }
}
