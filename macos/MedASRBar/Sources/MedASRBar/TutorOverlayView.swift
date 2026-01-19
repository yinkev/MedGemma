import SwiftUI

struct TutorOverlayView: View {
    @ObservedObject var controller: GemmaController
    @ObservedObject private var windowRegistry = OverlayWindowRegistry.shared
    @State private var captureError: String?
    @State private var isCapturing: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Radiology Tutor")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Toggle("Click-through", isOn: $windowRegistry.isClickThrough)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            .padding()
            .background(.ultraThinMaterial)
            
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error = captureError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    if let imagePath = controller.currentTutorImage,
                       let nsImage = NSImage(contentsOf: imagePath) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                            .cornerRadius(8)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)
                            Text("No image selected")
                                .foregroundStyle(.secondary)
                            
                            Button(action: captureScreen) {
                                HStack {
                                    if isCapturing {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "camera.viewfinder")
                                    }
                                    Text(isCapturing ? "Capturing..." : "Capture Screen")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isCapturing)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(30)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5]))
                                .foregroundStyle(.tertiary)
                        )
                    }
                    
                    if controller.isTutorThinking {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Analyzing...")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                    } else if !controller.tutorQuestion.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tutor Analysis")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            
                            MarkdownView(text: controller.tutorQuestion)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(8)
                    }
                    
                    if controller.currentTutorImage != nil {
                         Button(action: captureScreen) {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath.camera")
                                Text("Recapture Screen")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
        }
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func captureScreen() {
        isCapturing = true
        captureError = nil

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
