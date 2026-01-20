import Foundation

actor NativeAudioCapture {
    private var process: Process?
    private var pipe: Pipe?

    private func processDidTerminate(_ process: Process) async {
        if self.process === process {
            self.process = nil
        }
    }

    func start(onPCM16: @escaping @Sendable (Data) -> Void) async throws {
        if let process {
            if process.isRunning {
                let deadline = Date().addingTimeInterval(1.5)
                while process.isRunning, Date() < deadline {
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
            }

            if !process.isRunning {
                self.process = nil
            }
        }

        guard process == nil else {
            throw NSError(
                domain: "NativeAudioCapture",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "System audio capture is already running (or still stopping). Try again in a moment."]
            )
        }

        let executable = try resolveExecutable()

        let process = Process()
        process.executableURL = executable

        let stdout = Pipe()
        process.standardOutput = stdout

        let stderr = Pipe()
        process.standardError = stderr

        process.terminationHandler = { [weak self] proc in
            Task {
                guard let self else { return }
                await self.processDidTerminate(proc)
            }
        }

        try process.run()

        let readHandle = stdout.fileHandleForReading
        Thread {
            while process.isRunning {
                let data = readHandle.availableData
                if data.isEmpty {
                    break
                }
                onPCM16(data)
            }
        }.start()

        self.process = process
        self.pipe = stdout
    }

    func stop() {
        if let pipe {
            pipe.fileHandleForReading.readabilityHandler = nil
            try? pipe.fileHandleForReading.close()
        }
        pipe = nil

        if let process {
            process.terminate()
        }
    }

    private func resolveExecutable() throws -> URL {
        if let inResources = Bundle.main.url(forResource: "audiocapture", withExtension: nil) {
            return inResources
        }

        if let appExe = Bundle.main.executableURL {
            let inMacOS = appExe.deletingLastPathComponent().appendingPathComponent("audiocapture")
            if FileManager.default.isExecutableFile(atPath: inMacOS.path) {
                return inMacOS
            }
        }

        throw NSError(domain: "NativeAudioCapture", code: 1)
    }
}
