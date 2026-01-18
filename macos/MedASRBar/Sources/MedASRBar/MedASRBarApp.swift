import SwiftUI

@main
struct MedASRBarApp: App {
    @StateObject private var controller = AppController()
    @StateObject private var gemmaController = GemmaController()
    
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
            
            Group {
                Text("MedGemma Lab")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Button("Pathology Lab") {
                    openWindow(id: "pathlab")
                    NSApp.activate(ignoringOtherApps: true)
                }
                
                Button("Radiology Tutor") {
                    openWindow(id: "radtutor")
                    NSApp.activate(ignoringOtherApps: true)
                }
                
                Button("Tutor Overlay (HUD)") {
                    openWindow(id: "overlay")
                }
            }
            
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
        
        WindowGroup("Pathology Lab", id: "pathlab") {
            PathologyLabView(controller: gemmaController)
        }
        .defaultSize(width: 900, height: 600)
        
        WindowGroup("Radiology Tutor", id: "radtutor") {
            RadiologyTutorView(controller: gemmaController)
        }
        .defaultSize(width: 900, height: 600)
        
        WindowGroup("Tutor Overlay", id: "overlay") {
            TutorOverlayView(controller: gemmaController)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
                .onAppear {
                    if let window = NSApp.windows.first(where: { $0.title == "Tutor Overlay" && $0.className != "NSStatusBarWindow" }) {
                        window.level = .floating
                        window.styleMask.insert(.fullSizeContentView)
                        window.titleVisibility = .hidden
                        window.titlebarAppearsTransparent = true
                        window.isOpaque = false
                        window.backgroundColor = .clear
                        window.hasShadow = false
                        window.isMovableByWindowBackground = true
                        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 320, height: 500)
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
            
            ScrollView {
                if controller.lastEventText.isEmpty {
                    Text("No audio detected yet.")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    Text(controller.lastEventText)
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
