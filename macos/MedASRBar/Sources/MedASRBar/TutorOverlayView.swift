import SwiftUI

struct TutorOverlayView: View {
    @ObservedObject var controller: GemmaController
    @ObservedObject private var windowRegistry = OverlayWindowRegistry.shared

    @FocusState private var isAnswerFocused: Bool

    @State private var captureError: String?
    @State private var answerText: String = ""
    @State private var isCapturing: Bool = false
    @State private var isDropTargeted: Bool = false
    @State private var thinkingLabel: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if windowRegistry.isClickThrough {
                        clickThroughBanner
                    }

                    if let error = effectiveError {
                        errorCard(error)
                    }

                    imageCard

                    if controller.isTutorThinking {
                        thinkingCard
                    } else {
                        if !controller.tutorQuestion.isEmpty {
                            questionCard
                        }

                        if controller.currentTutorImage != nil {
                            actionTray

                            if !controller.tutorGrading.isEmpty {
                                gradingCard
                            }

                            if !controller.tutorAnswerRevealed.isEmpty {
                                revealCard
                            }
                        }
                    }
                }
                .padding(14)
            }
        }
        .background(.ultraThinMaterial)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .onExitCommand {
            windowRegistry.window?.orderOut(nil)
        }
        .onChange(of: controller.tutorQuestion) { _, newValue in
            if !newValue.isEmpty {
                isAnswerFocused = true
            }
        }
        .onChange(of: controller.isTutorThinking) { _, newValue in
            if !newValue {
                thinkingLabel = ""
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tutor")
                    .font(.headline)

                Text(controller.serviceStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("Click-through", isOn: $windowRegistry.isClickThrough)
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var clickThroughBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "cursorarrow.rays")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Click-through enabled")
                    .font(.subheadline)
                Text("Use Cmd+Shift+Space to regain control")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.10))
        .cornerRadius(12)
    }

    private var effectiveError: String? {
        captureError ?? controller.lastError
    }

    private func errorCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.primary)
            }

            if text.localizedCaseInsensitiveContains("screen recording") {
                Button("Open Screen Recording Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.10))
        .cornerRadius(12)
    }

    private var imageCard: some View {
        Group {
            if let imageURL = controller.currentTutorImage,
               let nsImage = NSImage(contentsOf: imageURL) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 220)
                        .cornerRadius(12)

                    HStack(spacing: 10) {
                        Button {
                            captureScreen()
                        } label: {
                            Label(isCapturing ? "Capturing…" : "Capture Screen", systemImage: "camera.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isCapturing || controller.isTutorThinking)

                        Button {
                            pickImage()
                        } label: {
                            Label("Choose Image", systemImage: "photo")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isCapturing || controller.isTutorThinking)
                    }

                    HStack {
                        Spacer()
                        Button("Clear") {
                            controller.currentTutorImage = nil
                            controller.tutorQuestion = ""
                            controller.tutorGrading = ""
                            controller.tutorAnswerRevealed = ""
                            answerText = ""
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color.black.opacity(0.05))
                .cornerRadius(14)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)

                    Text("Drop an image, capture your screen, or choose a file")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 10) {
                        Button {
                            captureScreen()
                        } label: {
                            Label(isCapturing ? "Capturing…" : "Capture Screen", systemImage: "camera.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isCapturing || controller.isTutorThinking)

                        Button {
                            pickImage()
                        } label: {
                            Label("Choose Image", systemImage: "photo")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isCapturing || controller.isTutorThinking)
                    }
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity)
                .padding(22)
                .background(isDropTargeted ? Color.accentColor.opacity(0.10) : Color.black.opacity(0.05))
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
                )
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                    handleDrop(providers)
                }
            }
        }
    }

    private var thinkingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(thinkingLabel.isEmpty ? "Working…" : thinkingLabel)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .background(Color.blue.opacity(0.08))
        .cornerRadius(12)
    }

    private var questionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Question")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            MarkdownView(text: controller.tutorQuestion)
        }
        .padding(12)
        .background(Color.blue.opacity(0.06))
        .cornerRadius(14)
    }

    private var actionTray: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Answer…", text: $answerText)
                .textFieldStyle(.roundedBorder)
                .focused($isAnswerFocused)
                .onSubmit {
                    submitAnswer()
                }

            HStack(spacing: 10) {
                Button("Next Question") {
                    guard let imagePath = controller.currentTutorImage?.path else { return }
                    thinkingLabel = "Generating question…"
                    controller.generateTutorQuestion(imagePath: imagePath)
                }
                .buttonStyle(.bordered)
                .disabled(controller.isTutorThinking || isCapturing)

                Button("Submit") {
                    submitAnswer()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Reveal") {
                    thinkingLabel = "Revealing…"
                    controller.revealTutorAnswer()
                }
                .buttonStyle(.bordered)
                .disabled(controller.isTutorThinking || isCapturing)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.04))
        .cornerRadius(14)
    }

    private var gradingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Feedback")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            MarkdownView(text: controller.tutorGrading)
        }
        .padding(12)
        .background(Color.green.opacity(0.06))
        .cornerRadius(14)
    }

    private var revealCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reveal")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            MarkdownView(text: controller.tutorAnswerRevealed)
        }
        .padding(12)
        .background(Color.purple.opacity(0.06))
        .cornerRadius(14)
    }

    private func submitAnswer() {
        let trimmed = answerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        thinkingLabel = "Grading…"
        controller.submitTutorAnswer(trimmed)
        answerText = ""
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.level = NSWindow.Level.floating
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "Choose"

        if panel.runModal() == .OK, let url = panel.url {
            controller.currentTutorImage = url
            thinkingLabel = "Generating question…"
            controller.generateTutorQuestion(imagePath: url.path)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else {
                        return
                    }

                    Task { @MainActor in
                        controller.currentTutorImage = url
                        thinkingLabel = "Generating question…"
                        controller.generateTutorQuestion(imagePath: url.path)
                    }
                }
                return true
            }
        }
        return false
    }

    private func captureScreen() {
        isCapturing = true
        captureError = nil
        thinkingLabel = "Capturing screen…"

        Task {
            let window = OverlayWindowRegistry.shared.window
            let wasVisible = window?.isVisible ?? false

            do {
                if wasVisible {
                    window?.alphaValue = 0
                    try await Task.sleep(nanoseconds: 200_000_000)
                }

                let image = try await ScreenCaptureManager.shared.captureScreen()

                if wasVisible {
                    window?.alphaValue = 1
                }

                let fileURL = try ScreenCaptureManager.shared.saveImageToTemp(image)

                await MainActor.run {
                    controller.currentTutorImage = fileURL
                    thinkingLabel = "Generating question…"
                    controller.generateTutorQuestion(imagePath: fileURL.path)
                    isCapturing = false
                }
            } catch {
                if wasVisible {
                    window?.alphaValue = 1
                }

                await MainActor.run {
                    captureError = error.localizedDescription
                    isCapturing = false
                    thinkingLabel = ""
                }
            }
        }
    }
}

struct MarkdownView: View {
    let text: String

    var body: some View {
        Text(text)
            .textSelection(.enabled)
    }
}
