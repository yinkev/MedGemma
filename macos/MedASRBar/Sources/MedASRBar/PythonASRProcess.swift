import Foundation

enum BackendEvent {
    case status(String)
    case asr(String)
    case error(String)
}

actor PythonASRProcess {
    private var process: Process?
    private var stdinHandle: FileHandle?

    private func processDidTerminate(_ process: Process) {
        stdinHandle = nil
        if self.process === process {
            self.process = nil
        }
    }

    func start(
        python: URL,
        repoRoot: URL,
        pythonPath: String,
        modelPath: String,
        chunkLength: Double,
        overlap: Double,
        onEvent: @escaping @Sendable (BackendEvent) -> Void
    ) async throws {
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
                domain: "PythonASRProcess",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "ASR backend is already running (or still stopping). Try again in a moment."]
            )
        }

        let p = Process()
        p.executableURL = python
        p.currentDirectoryURL = repoRoot
        p.arguments = [
            "-u",
            "-m",
            "medasr_local.cli.stream",
            "--chunk-s",
            String(format: "%.1f", chunkLength),
            "--overlap",
            String(format: "%.2f", overlap),
            "--no-lm",
            "--model",
            modelPath,
            "--sample-rate",
            "16000",
        ]

        var env = ProcessInfo.processInfo.environment
        env["PYTHONPATH"] = pythonPath
        env["TOKENIZERS_PARALLELISM"] = "false"
        env["HF_HUB_DISABLE_TELEMETRY"] = "1"
        env["TRANSFORMERS_VERBOSITY"] = "error"
        env["HF_HUB_OFFLINE"] = "1"
        env["TRANSFORMERS_OFFLINE"] = "1"
        p.environment = env

        let stdinPipe = Pipe()
        p.standardInput = stdinPipe
        stdinHandle = stdinPipe.fileHandleForWriting

        let stdoutPipe = Pipe()
        p.standardOutput = stdoutPipe

        let stderrPipe = Pipe()
        p.standardError = stderrPipe

        let outHandle = stdoutPipe.fileHandleForReading
        let errHandle = stderrPipe.fileHandleForReading

        Thread {
            var buf = Data()
            while true {
                let chunk = outHandle.availableData
                if chunk.isEmpty { break }
                buf.append(chunk)
                while let nl = buf.firstIndex(of: 0x0A) {
                    let lineData = buf.prefix(upTo: nl)
                    buf.removeSubrange(...nl)
                    if let line = String(data: lineData, encoding: .utf8) {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty { continue }
                        if let event = Self.parseEvent(trimmed) {
                            onEvent(event)
                        }
                    }
                }
            }
        }.start()

        Thread {
            while true {
                let chunk = errHandle.availableData
                if chunk.isEmpty { break }
                if let s = String(data: chunk, encoding: .utf8) {
                    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty { continue }
                    if trimmed.hasPrefix("Loading weights") { continue }
                    if trimmed.contains("UserWarning") { continue }
                    onEvent(.status(trimmed))
                }
            }
        }.start()

        p.terminationHandler = { proc in
            onEvent(.status("python_exit: \(proc.terminationStatus)"))
            Task { await self.processDidTerminate(proc) }
        }

        try p.run()
        process = p
    }

    func writePCM(_ data: Data) {
        guard let stdinHandle else { return }
        try? stdinHandle.write(contentsOf: data)
    }

    func stop() {
        if let stdinHandle {
            try? stdinHandle.close()
        }
        stdinHandle = nil

        if let process {
            process.terminate()
        }
    }

    private static func parseEvent(_ jsonLine: String) -> BackendEvent? {
        guard let data = jsonLine.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let type = obj["type"] as? String
        if type == "asr" {
            return .asr(obj["text"] as? String ?? "")
        }
        if type == "status" {
            return .status(obj["message"] as? String ?? "")
        }
        if type == "error" {
            return .error(obj["message"] as? String ?? "")
        }
        return nil
    }
}
