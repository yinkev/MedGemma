import Foundation
import AppKit

enum InputSource: String, CaseIterable, Identifiable {
    case microphone = "Microphone"
    case systemAudio = "System Audio"

    var id: String { rawValue }
}

@MainActor
final class AppController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var statusText = "Ready"
    @Published private(set) var lastEventText = ""
    @Published private(set) var transcriptLines: [String] = []
    @Published private(set) var transcriptText: String = ""
    @Published private(set) var transcriptFlushTick: Int = 0
    @Published var inputSource: InputSource = .microphone

    private var userStopRequested = false
    private var asrSessionID: UUID?

    private var microphone = MicrophoneCapture()
    private var systemAudio = NativeAudioCapture()

    private let asrProcess = PythonASRProcess()

    private var bytesReceived: Int = 0

    private let transcriptLineCap = 2000

    private let transcriptFlushIntervalNanoseconds: UInt64 = 200_000_000
    private var pendingTranscriptLines: [String] = []
    private var transcriptFlushTask: Task<Void, Never>?

    func toggle() {
        if isRunning {
            stop()
        } else {
            Task { await start() }
        }
    }

    func start() async {
        guard !isRunning else { return }

        stopTranscriptFlushTask()
        pendingTranscriptLines.removeAll(keepingCapacity: true)

        userStopRequested = false
        bytesReceived = 0
        lastEventText = ""
        transcriptLines.removeAll(keepingCapacity: true)
        transcriptText = ""
        transcriptFlushTick = 0

        let repoRoot: URL
        do {
            repoRoot = try resolveRepoRoot()
        } catch {
            statusText = "Repo not found"
            lastEventText = "Keep the app inside the MedASR repo while developing."
            return
        }

        let python = repoRoot.appendingPathComponent(".venv/bin/python")
        if !FileManager.default.isExecutableFile(atPath: python.path) {
            statusText = "Backend not ready"
            lastEventText = "Run ./setup.sh once to create .venv and download models."
            return
        }

        let pythonPath = repoRoot.appendingPathComponent("src").path
        let modelPath = repoRoot.appendingPathComponent("models/medasr").path

        let defaults = UserDefaults.standard

        let chunkLength = defaults.double(forKey: "liveChunkLength")
        let effectiveChunk = chunkLength > 0 ? chunkLength : 3.0

        let overlapKey = "liveOverlap"
        let effectiveOverlap: Double
        if defaults.object(forKey: overlapKey) == nil {
            effectiveOverlap = 0.3
        } else {
            effectiveOverlap = defaults.double(forKey: overlapKey)
        }

        guard effectiveOverlap >= 0, effectiveOverlap < 0.9 else {
            statusText = "Invalid settings"
            lastEventText = "Overlap must be in [0.0, 0.9). Update it in Settings."
            return
        }

        let sessionID = UUID()
        asrSessionID = sessionID

        do {
            try await asrProcess.start(
                python: python,
                repoRoot: repoRoot,
                pythonPath: pythonPath,
                modelPath: modelPath,
                chunkLength: effectiveChunk,
                overlap: effectiveOverlap
            ) { [weak self] event in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.asrSessionID == sessionID else { return }
                    self.handle(event)
                }
            }
        } catch {
            asrSessionID = nil
            statusText = "ASR backend failed"
            lastEventText = String(describing: error)
            return
        }

        switch inputSource {
        case .microphone:
            statusText = "Requesting microphone permission…"
            let granted = await microphone.requestPermission()
            guard granted else {
                statusText = "Microphone permission denied"
                asrSessionID = nil

                Task { await asrProcess.stop() }
                return
            }

            statusText = "Starting microphone…"
            do {
                try microphone.start { [weak self] pcm in
                    Task { @MainActor in
                        self?.forwardPCM(pcm)
                    }
                }
            } catch {
                statusText = "Failed to start microphone"
                lastEventText = String(describing: error)
                asrSessionID = nil
                Task { await asrProcess.stop() }
                return
            }

        case .systemAudio:
            statusText = "Starting system audio…"
            do {
                try await systemAudio.start { [weak self] pcm in
                    Task { @MainActor in
                        self?.forwardPCM(pcm)
                    }
                }
            } catch {
                statusText = "Failed to start system audio"
                lastEventText = String(describing: error)
                asrSessionID = nil
                Task { await asrProcess.stop() }
                return
            }
        }

        isRunning = true
        statusText = "Listening…"
    }

    func stop() {
        userStopRequested = true

        // Flush any buffered transcript before invalidating the session.
        if let sessionID = asrSessionID {
            stopTranscriptFlushTask()
            flushTranscriptBuffer(expectedSessionID: sessionID)
        }

        asrSessionID = nil
        pendingTranscriptLines.removeAll(keepingCapacity: true)

        microphone.stop()
        Task { await systemAudio.stop() }
        Task { await asrProcess.stop() }
        isRunning = false
        statusText = "Ready"
    }

    func clear() {
        pendingTranscriptLines.removeAll(keepingCapacity: true)
        transcriptLines.removeAll(keepingCapacity: true)
        transcriptText = ""
        lastEventText = ""
        transcriptFlushTick &+= 1
    }

    @discardableResult
    func copyTranscriptToClipboard() -> Bool {
        let text = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    private func forwardPCM(_ pcm: Data) {
        bytesReceived += pcm.count
        Task { await asrProcess.writePCM(pcm) }
    }

    private func handle(_ event: BackendEvent) {
        switch event {
        case .status(let message):
            if message.hasPrefix("python_exit:") {
                if userStopRequested {
                    statusText = "Ready"
                    return
                }

                if let sessionID = asrSessionID {
                    stopTranscriptFlushTask()
                    flushTranscriptBuffer(expectedSessionID: sessionID)
                }
                asrSessionID = nil
                pendingTranscriptLines.removeAll(keepingCapacity: true)

                microphone.stop()
                Task { await systemAudio.stop() }
                Task { await asrProcess.stop() }

                statusText = "ASR exited"
                lastEventText = message
                isRunning = false
                return
            }

            if !message.isEmpty {
                statusText = message
            }
        case .error(let message):
            statusText = "Error"
            lastEventText = message
        case .asr(let text):
            if !text.isEmpty {
                pendingTranscriptLines.append(text)
                ensureTranscriptFlushTask()
            }
        }
    }

    private func stopTranscriptFlushTask() {
        transcriptFlushTask?.cancel()
        transcriptFlushTask = nil
    }

    private func ensureTranscriptFlushTask() {
        guard transcriptFlushTask == nil else { return }
        guard let sessionID = asrSessionID else { return }

        transcriptFlushTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: transcriptFlushIntervalNanoseconds)
                } catch is CancellationError {
                    return
                } catch {
                    return
                }

                guard self.asrSessionID == sessionID else {
                    self.transcriptFlushTask = nil
                    return
                }

                self.flushTranscriptBuffer(expectedSessionID: sessionID)

                if self.pendingTranscriptLines.isEmpty {
                    self.transcriptFlushTask = nil
                    return
                }
            }
        }
    }

    private func flushTranscriptBuffer(expectedSessionID: UUID) {
        guard asrSessionID == expectedSessionID else {
            pendingTranscriptLines.removeAll(keepingCapacity: true)
            transcriptFlushTask?.cancel()
            transcriptFlushTask = nil
            return
        }

        guard !pendingTranscriptLines.isEmpty else { return }

        let linesToAppend = pendingTranscriptLines
        pendingTranscriptLines.removeAll(keepingCapacity: true)

        transcriptLines.append(contentsOf: linesToAppend)
        if transcriptLines.count > transcriptLineCap {
            transcriptLines.removeFirst(transcriptLines.count - transcriptLineCap)
            transcriptText = transcriptLines.joined(separator: "\n")
        } else {
            let batchText = linesToAppend.joined(separator: "\n")
            if transcriptText.isEmpty {
                transcriptText = batchText
            } else {
                transcriptText += "\n" + batchText
            }
        }

        if let last = linesToAppend.last {
            lastEventText = last
        }

        transcriptFlushTick &+= 1
    }

    private func resolveRepoRoot() throws -> URL {
        let fm = FileManager.default
        var dir = Bundle.main.bundleURL.deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir
            let marker = candidate.appendingPathComponent("src/medasr_local", isDirectory: true)
            if fm.fileExists(atPath: marker.path) {
                return candidate
            }
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path {
                break
            }
            dir = parent
        }
        throw NSError(domain: "AppController", code: 2)
    }
}
