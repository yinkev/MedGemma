import SwiftUI

@main
struct MedASRBarApp: App {
    @StateObject private var controller = AppController()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra(
            "MedASR",
            systemImage: controller.isRunning ? "record.circle.fill" : "waveform.circle"
        ) {
            Picker("Input Source", selection: $controller.inputSource) {
                ForEach(InputSource.allCases) { source in
                    Text(source.rawValue).tag(source)
                }
            }
            .pickerStyle(.inline)
            .disabled(controller.isRunning)

            Divider()

            Button(controller.isRunning ? "Stop Transcription" : "Start Transcription") {
                controller.toggle()
            }

            Text(controller.statusText)
                .foregroundStyle(.secondary)

            Divider()

            Button("Open Transcript") {
                openWindow(id: "transcript")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("t")

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)

        WindowGroup("Transcript", id: "transcript") {
            TranscriptView(controller: controller)
        }
        .defaultSize(width: 500, height: 600)
    }
}

struct TranscriptView: View {
    @ObservedObject var controller: AppController

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            VStack(spacing: 4) {
                Text("Transcript")
                    .font(.title2)
                    .fontWeight(.medium)
                
                Text(controller.inputSource.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if controller.lastEventText.isEmpty {
                Text("No audio detected yet.")
                    .foregroundStyle(.secondary)
            } else {
                Text(controller.lastEventText)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
