import SwiftUI
import Combine

@MainActor
class GemmaController: ObservableObject {
    @Published var isServiceRunning = false
    @Published var serviceStatus = "Ready"
    @Published var lastError: String?
    
    @Published var pathologyReport: String = ""
    @Published var isAnalyzingPathology = false
    
    @Published var tutorQuestion: String = ""
    @Published var tutorGrading: String = ""
    @Published var tutorAnswerRevealed: String = ""
    @Published var isTutorThinking = false
    @Published var currentTutorImage: URL?
    
    private let process = MedGemmaProcess()
    private var repoRoot: URL?
    private let sessionId = UUID().uuidString
    
    init() {
        do {
            self.repoRoot = try resolveRepoRoot()
        } catch {
            self.lastError = "Could not find MedASR repo root."
        }
    }
    
    func startService() {
        guard !isServiceRunning else { return }
        guard let repoRoot = repoRoot else {
            lastError = "Repo root not found"
            return
        }
        
        serviceStatus = "Starting MedGemma..."
        
        Task {
            do {
                try await process.start(repoRoot: repoRoot) { [weak self] event in
                    Task { @MainActor in
                        self?.handle(event)
                    }
                }
                isServiceRunning = true
                serviceStatus = "MedGemma Active"
            } catch {
                isServiceRunning = false
                lastError = error.localizedDescription
                serviceStatus = "Failed to start"
            }
        }
    }
    
    func stopService() {
        Task {
            await process.stop()
            isServiceRunning = false
            serviceStatus = "Ready"
        }
    }
    
    func analyzePathology(imagePath: String) {
        ensureServiceStarted()
        isAnalyzingPathology = true
        pathologyReport = "Analyzing tissue sample..."

        Task {
            await process.send(
                task: "path_report",
                payload: [
                    "session_id": sessionId,
                    "image_path": imagePath,
                    "max_tiles": 4
                ]
            )
        }
    }
    
    func generateTutorQuestion(imagePath: String) {
        ensureServiceStarted()
        currentTutorImage = URL(fileURLWithPath: imagePath)
        isTutorThinking = true
        tutorQuestion = "Generating question..."
        tutorGrading = ""
        tutorAnswerRevealed = ""

        Task {
            await process.send(
                task: "tutor_next",
                payload: [
                    "session_id": sessionId,
                    "image_path": imagePath
                ]
            )
        }
    }
    
    func submitTutorAnswer(_ answer: String) {
        ensureServiceStarted()
        isTutorThinking = true
        tutorGrading = "Grading..."

        guard let imagePath = currentTutorImage?.path else {
            lastError = "No image selected"
            isTutorThinking = false
            return
        }

        Task {
            await process.send(
                task: "tutor_grade",
                payload: [
                    "session_id": sessionId,
                    "image_path": imagePath,
                    "prompt": tutorQuestion,
                    "user_answer": answer
                ]
            )
        }
    }
    
    func revealTutorAnswer() {
        ensureServiceStarted()
        isTutorThinking = true
        
        guard let imagePath = currentTutorImage?.path else {
            lastError = "No image selected"
            isTutorThinking = false
            return
        }

        Task {
            await process.send(
                task: "tutor_reveal",
                payload: [
                    "session_id": sessionId,
                    "image_path": imagePath
                ]
            )
        }
    }
    
    private func ensureServiceStarted() {
        if !isServiceRunning {
            startService()
        }
    }
    
    private func handle(_ event: GemmaBackendEvent) {
        switch event {
        case .status(let msg):
            if msg.contains("Keep alive") { return }
            serviceStatus = msg
            
        case .error(let msg):
            lastError = msg
            isAnalyzingPathology = false
            isTutorThinking = false
            
        case .result(let dataBytes):
            isAnalyzingPathology = false
            isTutorThinking = false
            
            guard let json = try? JSONSerialization.jsonObject(with: dataBytes) as? [String: Any],
                  let task = json["task"] as? String else { return }
            
            switch task {
            case "path_report":
                if let answer = json["answer"] as? String {
                    pathologyReport = answer
                }
            case "tutor_next":
                if let question = json["question"] as? String {
                    tutorQuestion = question
                }
            case "tutor_grade":
                if let grading = json["grading"] as? String {
                    tutorGrading = grading
                }
            case "tutor_reveal":
                if let reveal = json["reveal"] as? String {
                    tutorAnswerRevealed = reveal
                }
            default:
                break
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
            if parent.path == candidate.path { break }
            dir = parent
        }
        throw NSError(domain: "GemmaController", code: 2)
    }
}
