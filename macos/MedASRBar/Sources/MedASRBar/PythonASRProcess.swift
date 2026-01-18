import Foundation

enum BackendEvent {
    case status(String)
    case asr(String)
    case error(String)
}

actor PythonASRProcess {
    private var process: Process?
    private var stdinHandle: FileHandle?

    func start(
        python: URL,
        repoRoot: URL,
        pythonPath: String,
        modelPath: String,
        onEvent: @escaping @Sendable (BackendEvent) -> Void
    ) throws {
        guard process == nil else { return }

        let p = Process()
        p.executableURL = python
        p.currentDirectoryURL = repoRoot
        p.arguments = [
            "-u",
            "-m",
            "medasr_local.cli.stream",
            "--chunk-s",
            "1.0",
            "--overlap",
            "0.0",
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
        self.stdinHandle = nil

        if let process {
            process.terminate()
        }
        self.process = nil
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
