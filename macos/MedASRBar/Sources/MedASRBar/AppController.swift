import Foundation

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
    @Published var inputSource: InputSource = .microphone

    private var microphone = MicrophoneCapture()
    private var systemAudio = NativeAudioCapture()

    private let asrProcess = PythonASRProcess()

    private var bytesReceived: Int = 0

    func toggle() {
        if isRunning {
            stop()
        } else {
            Task { await start() }
        }
    }

    func start() async {
        guard !isRunning else { return }
        bytesReceived = 0
        lastEventText = ""

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

        do {
            try await asrProcess.start(
                python: python,
                repoRoot: repoRoot,
                pythonPath: pythonPath,
                modelPath: modelPath
            ) { [weak self] event in
                Task { @MainActor in
                    self?.handle(event)
                }
            }
        } catch {
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
                Task { await asrProcess.stop() }
                return
            }

            do {
                try microphone.start { [weak self] pcm in
                    Task { @MainActor in
                        self?.forwardPCM(pcm)
                    }
                }
            } catch {
                statusText = "Failed to start microphone"
                lastEventText = String(describing: error)
                Task { await asrProcess.stop() }
                return
            }

        case .systemAudio:
            statusText = "Starting system audio…"
            do {
                try systemAudio.start { [weak self] pcm in
                    Task { @MainActor in
                        self?.forwardPCM(pcm)
                    }
                }
            } catch {
                statusText = "Failed to start system audio"
                lastEventText = String(describing: error)
                Task { await asrProcess.stop() }
                return
            }
        }

        isRunning = true
        statusText = "Listening…"
    }

    func stop() {
        microphone.stop()
        systemAudio.stop()
        Task { await asrProcess.stop() }
        isRunning = false
        statusText = "Ready"
    }

    private func forwardPCM(_ pcm: Data) {
        bytesReceived += pcm.count
        Task { await asrProcess.writePCM(pcm) }
    }

    private func handle(_ event: BackendEvent) {
        switch event {
        case .status(let message):
            if !message.isEmpty {
                statusText = message
            }
        case .error(let message):
            statusText = "Error"
            lastEventText = message
        case .asr(let text):
            if !text.isEmpty {
                lastEventText = text
            }
        }
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
