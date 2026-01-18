import Foundation

final class NativeAudioCapture {
    private var process: Process?
    private var pipe: Pipe?

    func start(onPCM16: @escaping @Sendable (Data) -> Void) throws {
        guard process == nil else { return }

        let executable = try resolveExecutable()

        let process = Process()
        process.executableURL = executable

        let stdout = Pipe()
        process.standardOutput = stdout

        let stderr = Pipe()
        process.standardError = stderr

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
        process = nil
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
