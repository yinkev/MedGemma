@preconcurrency import AVFoundation

final class MicrophoneCapture {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat

    init(sampleRate: Double = 16000, channels: AVAudioChannelCount = 1) {
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: sampleRate,
                channels: channels,
                interleaved: true
            )
        else {
            fatalError("Failed to create output audio format")
        }
        self.outputFormat = format
    }

    @MainActor
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func start(onPCM16: @escaping (Data) -> Void) throws {
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)

        converter = AVAudioConverter(from: inputFormat, to: outputFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard let converter = self.converter else { return }

            let ratio = self.outputFormat.sampleRate / inputFormat.sampleRate
            let outFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1)
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: self.outputFormat, frameCapacity: outFrames) else {
                return
            }

            var err: NSError?
            let status = converter.convert(to: outBuffer, error: &err) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            if status == .error {
                return
            }

            let frames = Int(outBuffer.frameLength)
            let bytesPerFrame = Int(self.outputFormat.streamDescription.pointee.mBytesPerFrame)
            let bytes = frames * bytesPerFrame
            guard bytes > 0 else { return }
            guard let base = outBuffer.int16ChannelData else { return }
            onPCM16(Data(bytes: base.pointee, count: bytes))
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
    }
}
