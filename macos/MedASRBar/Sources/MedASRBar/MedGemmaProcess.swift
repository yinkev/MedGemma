import Foundation

enum GemmaBackendEvent: Sendable {
    case status(String)
    case error(String)
    case result(Data)
}

actor MedGemmaProcess {
    private var process: Process?
    private var stdinHandle: FileHandle?

    private func processDidTerminate(_ process: Process) {
        stdinHandle = nil
        if self.process === process {
            self.process = nil
        }
    }
    
    func start(
        repoRoot: URL,
        onEvent: @escaping @Sendable (GemmaBackendEvent) -> Void
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
                domain: "MedGemmaProcess",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "MedGemma service is already running (or still stopping). Try again in a moment."]
            )
        }
        
        let pythonPath = repoRoot.appendingPathComponent("src").path
        let venvPython = repoRoot.appendingPathComponent(".venv314/bin/python")
        let modelPath = repoRoot.appendingPathComponent("models/medgemma").path
        
        guard FileManager.default.fileExists(atPath: venvPython.path) else {
            throw NSError(domain: "MedGemmaProcess", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing .venv314 python environment. Run setup.sh."])
        }
        
        let p = Process()
        p.executableURL = venvPython
        p.currentDirectoryURL = repoRoot
        p.arguments = [
            "-u",
            "-m",
            "medasr_local.cli.mm_service",
            "--model",
            modelPath
        ]
        
        var env = ProcessInfo.processInfo.environment
        env["PYTHONPATH"] = pythonPath
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
                        if let event = Self.parseEvent(trimmed, rawData: lineData) {
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
                    if trimmed.contains("Loading checkpoint") { onEvent(.status("Loading model weights...")) }
                    else { onEvent(.status(trimmed)) }
                }
            }
        }.start()

        p.terminationHandler = { proc in
            onEvent(.status("Service exited with code \(proc.terminationStatus)"))
            Task { await self.processDidTerminate(proc) }
        }

        try p.run()
        process = p
    }
    
    func send(task: String, payload: [String: Any]) {
        guard let stdinHandle else { return }
        var msg = payload
        msg["task"] = task
        msg["id"] = UUID().uuidString
        
        do {
            let data = try JSONSerialization.data(withJSONObject: msg, options: [])
            stdinHandle.write(data)
            stdinHandle.write("\n".data(using: .utf8)!)
        } catch {
            print("Failed to encode JSON: \(error)")
        }
    }
    
    func stop() {
        if let stdinHandle {
            try? stdinHandle.close()
        }
        self.stdinHandle = nil

        if let process {
            process.terminate()
        }
    }
    
    private static func parseEvent(_ jsonLine: String, rawData: Data) -> GemmaBackendEvent? {
        guard let data = jsonLine.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        
        guard let type = obj["type"] as? String else { return nil }
        
        switch type {
        case "status":
            return .status(obj["message"] as? String ?? "")
        case "error":
            let msg = obj["message"] as? String ?? "Unknown error"
            if let detail = obj["detail"] as? String {
                return .error("\(msg): \(detail)")
            }
            return .error(msg)
        case "result":
            return .result(data)
        default:
            return nil
        }
    }
}
