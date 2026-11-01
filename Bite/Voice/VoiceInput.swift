import AVFoundation
import UIKit

/// Voice input: what's said is written at the end of the page as it's said, the words still being
/// made out drawn lighter, and once it's stopped it's tidied, into what one person speaking meant
/// to write, in the page's own kind of lines (user, 2026-11-01). Started and stopped from the "…"
/// menu, Record and Stop Recording, with no button of its own (user, 2026-11-01). It belongs to the
/// page it started on, which it goes on writing to as other pages are looked at, and from any of
/// which it can be stopped, but not started again meanwhile.
@MainActor @Observable
final class VoiceInput {
    static let shared = VoiceInput()

    enum Phase: Equatable {
        case idle
        /// Listening since `since`, writing on `page`.
        case listening(page: Int, since: Date)
        /// Stopped: the last words being heard, and the page tidied.
        case finishing(page: Int)
    }

    private(set) var phase = Phase.idle

    /// Whether Bite has voice input: built with its relay.
    var isAvailable: Bool {
        VoiceRelay.shared != nil
    }

    @ObservationIgnored private weak var editor: EditorController?
    @ObservationIgnored private weak var window: PageWindow?
    @ObservationIgnored private var capture: MicCapture?
    @ObservationIgnored private var session: SonioxSession?
    @ObservationIgnored private var interruptions: (any NSObjectProtocol)?
    /// How long the last words have, once stopped, before what's been heard is all there is.
    private static let lastWordsWait: Duration = .seconds(5)

    private init() {}

    /// Starts listening on `page`, or stops, from whichever page's menu.
    func toggle(page: Int, in window: PageWindow) {
        switch phase {
        case .idle: start(page: page, in: window)
        case .listening: stop()
        case .finishing: break
        }
    }

    private func start(page: Int, in window: PageWindow) {
        guard let relay = VoiceRelay.shared, let pager = window.pager, pager.controllers.indices.contains(page) else { return }
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined:
            Task {
                if await AVAudioApplication.requestRecordPermission() {
                    if phase == .idle { start(page: page, in: window) }
                } else {
                    showMicrophoneOff(in: window)
                }
            }
            return
        case .denied:
            showMicrophoneOff(in: window)
            return
        default:
            break
        }
        let editor = pager.controllers[page]
        let session = SonioxSession(configuration: Self.configuration(heardAgainst: editor.text(limit: 2000)))
        let capture = MicCapture { session.send($0) }
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .default, options: [.allowBluetoothHFP])
            try audio.setActive(true)
            try capture.start()
        } catch {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            show(error, in: window)
            return
        }
        self.editor = editor
        self.window = window
        self.capture = capture
        self.session = session
        editor.beginDictation()
        phase = .listening(page: page, since: .now)
        // A call or Siri taking the microphone stops it, as a tap would.
        interruptions = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init) == .began
            MainActor.assumeIsolated {
                if began { self?.stop() }
            }
        }
        Task { await listen(to: session, with: relay) }
    }

    /// Stops listening: the last words come, and then what was said is tidied.
    private func stop() {
        guard case .listening(let page, _) = phase else { return }
        phase = .finishing(page: page)
        stopRecording()
        session?.finish()
        let session = session
        Task {
            try? await Task.sleep(for: Self.lastWordsWait)
            session?.cancel()
        }
    }

    private func stopRecording() {
        capture?.stop()
        capture = nil
        if let interruptions { NotificationCenter.default.removeObserver(interruptions) }
        interruptions = nil
        // Music stopped for it plays on.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func listen(to session: SonioxSession, with relay: VoiceRelay) async {
        var failure: String?
        do {
            session.connect(key: try await relay.sonioxKey())
        } catch {
            failure = error.localizedDescription
            session.cancel()
        }
        for await event in session.events {
            switch event {
            case .words(let final, let pending):
                editor?.dictate(final, pending: pending)
            case .finished:
                break
            case .failed(let message):
                // Once stopped, the words were coming to an end anyway.
                if case .listening = phase { failure = message }
            }
        }
        // Cut short while listening, what was heard is tidied as when stopped.
        if case .listening(let page, _) = phase {
            phase = .finishing(page: page)
            stopRecording()
        }
        await tidy(with: relay)
        self.session = nil
        phase = .idle
        if let failure, let window {
            show(message: failure, in: window)
        }
    }

    /// Puts what was said, tidied, in its place. Not tidied, it stays as it was heard.
    private func tidy(with relay: VoiceRelay) async {
        guard let editor else { return }
        editor.settleDictation()
        guard let said = editor.dictatedMarkdown else {
            editor.endDictation()
            return
        }
        let page = editor.markdownBeforeDictation(limit: 4000)
        let tidied = try? await relay.tidy(said, after: page, speakers: 1)
        editor.endDictation(replacingWith: tidied, ifStill: said)
    }

    /// What Soniox is told first: the model, the audio's format, the languages to expect, and
    /// `text`, the page, for names and words on it to be heard as written there.
    private static func configuration(heardAgainst text: String) -> [String: Any] {
        var configuration: [String: Any] = [
            "model": "stt-rt-v5",
            "audio_format": "pcm_s16le",
            "sample_rate": 16000,
            "num_channels": 1,
            "language_hints": languageHints,
            // Words go final as soon as the speaker pauses, rather than waiting on what comes
            // next: less of the end of what's said is still being made out.
            "enable_endpoint_detection": true,
        ]
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            configuration["context"] = ["text": text]
        }
        return configuration
    }

    /// The languages the person reads, as Soniox names them, English among them: Chinese is
    /// spoken with English words in it (user, 2026-11-01).
    private static var languageHints: [String] {
        var hints: [String] = []
        for language in Locale.preferredLanguages {
            guard let code = Locale(identifier: language).language.languageCode?.identifier, !hints.contains(code) else { continue }
            hints.append(code)
        }
        if !hints.contains("en") { hints.append("en") }
        return Array(hints.prefix(4))
    }

    // MARK: Alerts

    private func showMicrophoneOff(in window: PageWindow) {
        let alert = UIAlertController(title: String(localized: "Microphone Off"),
                                      message: String(localized: "To write what you say, allow Bite to use the microphone in Settings."),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Settings"), style: .default) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        present(alert, in: window)
    }

    private func show(_ error: any Error, in window: PageWindow) {
        show(message: error.localizedDescription, in: window)
    }

    private func show(message: String, in window: PageWindow) {
        let alert = UIAlertController(title: String(localized: "Recording Stopped"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, in: window)
    }

    private func present(_ alert: UIAlertController, in window: PageWindow) {
        var shown = window.window?.rootViewController
        while let presented = shown?.presentedViewController, !presented.isBeingDismissed {
            shown = presented
        }
        shown?.present(alert, animated: true)
    }
}
