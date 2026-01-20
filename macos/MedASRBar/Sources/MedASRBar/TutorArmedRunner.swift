import Foundation
import AppKit

@MainActor
final class TutorArmedRunner: ObservableObject {
    @Published private(set) var isArmed = false
    @Published private(set) var secondsUntilNextCapture = 0
    @Published private(set) var lastError: String?

    private var loopTask: Task<Void, Never>?

    func start(intervalSeconds: Int, controller: GemmaController) {
        stop()

        let interval = max(1, intervalSeconds)
        isArmed = true
        lastError = nil
        secondsUntilNextCapture = 0

        loopTask = Task { [weak self] in
            guard let self else { return }
            await self.runLoop(intervalSeconds: interval, controller: controller)
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        isArmed = false
        secondsUntilNextCapture = 0
    }

    private func runLoop(intervalSeconds: Int, controller: GemmaController) async {
        while isArmed, !Task.isCancelled {
            while isArmed, !Task.isCancelled, controller.isTutorThinking {
                secondsUntilNextCapture = 0
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch is CancellationError {
                    return
                } catch {
                    lastError = error.localizedDescription
                    stop()
                    return
                }
            }

            do {
                let fileURL = try await ScreenCaptureManager.shared.captureScreenToTempFile()
                controller.generateTutorQuestion(imagePath: fileURL.path)
            } catch {
                lastError = error.localizedDescription
                stop()
                return
            }

            while isArmed, !Task.isCancelled, controller.isTutorThinking {
                secondsUntilNextCapture = 0
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch is CancellationError {
                    return
                } catch {
                    lastError = error.localizedDescription
                    stop()
                    return
                }
            }

            for remaining in stride(from: intervalSeconds, through: 1, by: -1) {
                if Task.isCancelled || !isArmed { break }
                secondsUntilNextCapture = remaining
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch is CancellationError {
                    return
                } catch {
                    lastError = error.localizedDescription
                    stop()
                    return
                }
            }
        }
    }
}
