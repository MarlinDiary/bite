import AVFoundation

/// The microphone, as Soniox takes it: 16 kHz mono 16-bit samples, handed on as they're recorded,
/// about a tenth of a second at a time.
nonisolated final class MicCapture: @unchecked Sendable {
    struct NoInput: LocalizedError {
        var errorDescription: String? { String(localized: "There's no microphone to record with.") }
    }

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    private let onAudio: @Sendable (Data) -> Void
    private var converter: AVAudioConverter?
    private var configurationObserver: (any NSObjectProtocol)?

    init(onAudio: @escaping @Sendable (Data) -> Void) {
        self.onAudio = onAudio
    }

    #if DEBUG
    /// `-dictateFile <path>` records a file of 16 kHz mono 16-bit samples instead, at the pace it
    /// was said, for voice input to be tried where nobody can speak to it, as in the simulator.
    private static let file: URL? = {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "-dictateFile"), index + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
    }()
    private var playback: Task<Void, Never>?
    #endif

    /// Starts recording, the audio session active for it.
    func start() throws {
        #if DEBUG
        if let file = Self.file {
            let samples = try Data(contentsOf: file)
            let onAudio = onAudio
            playback = Task.detached {
                // A tenth of a second at a time, as the microphone's are handed on, and then
                // silence, as a microphone goes on recording.
                var start = 0
                while !Task.isCancelled {
                    onAudio(start < samples.count ? samples.subdata(in: start..<min(start + 3200, samples.count)) : Data(count: 3200))
                    start += 3200
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            return
        }
        #endif
        try installTap()
        engine.prepare()
        try engine.start()
        // A headset put on or taken off changes the input, and stops the engine: the recording
        // goes on with what's there now.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.restart()
        }
    }

    func stop() {
        #if DEBUG
        playback?.cancel()
        #endif
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func restart() {
        engine.inputNode.removeTap(onBus: 0)
        guard (try? installTap()) != nil else { return }
        engine.prepare()
        try? engine.start()
    }

    private func installTap() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let converter = AVAudioConverter(from: inputFormat, to: format) else { throw NoInput() }
        converter.downmix = true
        self.converter = converter
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(inputFormat.sampleRate / 10), format: inputFormat) { [weak self] buffer, _ in
            self?.convert(buffer)
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
        // The buffer's handed over once; the converter keeps what it hasn't used for the next.
        var isGiven = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if isGiven {
                inputStatus.pointee = .noDataNow
                return nil
            }
            isGiven = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0, let samples = output.int16ChannelData else { return }
        onAudio(Data(bytes: samples[0], count: Int(output.frameLength) * MemoryLayout<Int16>.size))
    }
}
