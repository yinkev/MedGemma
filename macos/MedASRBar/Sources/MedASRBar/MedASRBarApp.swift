import SwiftUI
import Combine
import AppKit

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
            Group {
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

                Button("Settings…") {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",")

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
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }

                Divider()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleOverlay)) { _ in
                openWindow(id: "overlay")
                NSApp.activate(ignoringOtherApps: true)
            }
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
                .background(
                    WindowAccessor { window in
                        OverlayWindowRegistry.shared.register(window: window)
                        window.level = NSWindow.Level.floating
                        window.styleMask.insert(.fullSizeContentView)
                        window.titleVisibility = .hidden
                        window.titlebarAppearsTransparent = true
                        window.isOpaque = false
                        window.backgroundColor = .clear
                        window.hasShadow = false
                        window.isMovableByWindowBackground = true
                        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                    }
                )
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 320, height: 500)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        WindowGroup("Settings", id: "settings") {
            SettingsView()
        }
        .defaultSize(width: 450, height: 280)

        Settings {
            SettingsView()
        }
    }

    init() {
        GlobalHotKeyManager.shared.register()
        GlobalHotKeyManager.shared.onHotKeyPress = {
            Task { @MainActor in
                let handled = OverlayWindowRegistry.shared.toggle()
                if !handled {
                    NotificationCenter.default.post(name: .toggleOverlay, object: nil)
                }
            }
        }

        ScreenCaptureManager.shared.cleanupOldCaptures()
    }
}

extension Notification.Name {
    static let toggleOverlay = Notification.Name("medasr_toggle_overlay")
}

struct TranscriptView: View {
    @ObservedObject var controller: AppController

    @State private var isAutoScrollEnabled = true

    private let bottomAnchorID = "transcript-bottom"

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

            HStack(spacing: 10) {
                Button("Copy") {
                    controller.copyTranscriptToClipboard()
                }
                .disabled(controller.transcriptLines.isEmpty)

                Button("Clear") {
                    controller.clear()
                }
                .disabled(controller.transcriptLines.isEmpty)

                Spacer()

                Toggle("Auto-scroll", isOn: $isAutoScrollEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.horizontal)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if controller.transcriptLines.isEmpty {
                            Text("No audio detected yet.")
                                .foregroundStyle(.secondary)
                                .padding()
                        } else {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(controller.transcriptLines.indices, id: \.self) { index in
                                    Text(controller.transcriptLines[index])
                                        .font(.body)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding()
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchorID)
                    }
                }
                .onChange(of: controller.transcriptFlushTick) { _, _ in
                    guard isAutoScrollEnabled else { return }
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                }
                .onAppear {
                    guard isAutoScrollEnabled else { return }
                    guard !controller.transcriptLines.isEmpty else { return }
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
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
