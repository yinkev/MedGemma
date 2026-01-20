import SwiftUI
import Combine
import Foundation

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
    @Published var currentTutorImage: URL? {
        didSet {
            guard let oldValue else { return }
            guard oldValue != currentTutorImage else { return }
            guard ScreenCaptureManager.shared.isManagedCaptureURL(oldValue) else { return }

            let urlToDelete = oldValue
            Task.detached {
                try? FileManager.default.removeItem(at: urlToDelete)
            }
        }
    }

    var parsedTutorMCQ: TutorMCQ? {
        TutorMCQParser.parse(from: tutorQuestion)
    }
    
    private let process = MedGemmaProcess()
    private var repoRoot: URL?
    private let sessionId = UUID().uuidString
    private var serviceRunID: UUID?

    private var tutorRequestStartTimes: [String: Date] = [:]
    
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

        let runID = UUID()
        serviceRunID = runID

        Task {
            do {
                try await process.start(repoRoot: repoRoot) { [weak self] event in
                    Task { @MainActor in
                        guard let self else { return }
                        guard self.serviceRunID == runID else { return }
                        self.handle(event)
                    }
                }
                isServiceRunning = true
                serviceStatus = "MedGemma Active"
            } catch {
                isServiceRunning = false
                serviceRunID = nil
                lastError = error.localizedDescription
                serviceStatus = "Failed to start"
            }
        }
    }
    
    func stopService() {
        Task {
            await process.stop()
            isServiceRunning = false
            serviceRunID = nil
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

        let maxTokens = tutorMaxTokens(for: "tutor_next")
        tutorRequestStartTimes["tutor_next"] = Date()

        Task {
            var payload: [String: Any] = [
                "session_id": sessionId,
                "image_path": imagePath
            ]

            if let maxTokens {
                payload["max_tokens"] = maxTokens
            }

            await process.send(
                task: "tutor_next",
                payload: payload
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

        let maxTokens = tutorMaxTokens(for: "tutor_grade")
        tutorRequestStartTimes["tutor_grade"] = Date()

        Task {
            var payload: [String: Any] = [
                "session_id": sessionId,
                "image_path": imagePath,
                "prompt": tutorQuestion,
                "user_answer": answer
            ]

            if let maxTokens {
                payload["max_tokens"] = maxTokens
            }

            await process.send(
                task: "tutor_grade",
                payload: payload
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

        let maxTokens = tutorMaxTokens(for: "tutor_reveal")
        tutorRequestStartTimes["tutor_reveal"] = Date()

        Task {
            var payload: [String: Any] = [
                "session_id": sessionId,
                "image_path": imagePath
            ]

            if let maxTokens {
                payload["max_tokens"] = maxTokens
            }

            await process.send(
                task: "tutor_reveal",
                payload: payload
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

            if task.hasPrefix("tutor_"), let start = tutorRequestStartTimes.removeValue(forKey: task) {
                let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
                print("\(task)_ms=\(elapsedMs)")
            }
            
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

    private func tutorMaxTokens(for task: String) -> Int? {
        let presetRaw = UserDefaults.standard.string(forKey: "tutorTokenPreset") ?? "balanced"
        let preset = presetRaw.lowercased()

        switch preset {
        case "fast":
            switch task {
            case "tutor_next": return 128
            case "tutor_grade": return 128
            case "tutor_reveal": return 192
            default: return nil
            }
        case "quality":
            return nil
        default:
            switch task {
            case "tutor_next": return 192
            case "tutor_grade": return 192
            case "tutor_reveal": return 256
            default: return nil
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
