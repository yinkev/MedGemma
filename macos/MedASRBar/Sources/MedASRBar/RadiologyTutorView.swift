import SwiftUI

struct RadiologyTutorView: View {
    @ObservedObject var controller: GemmaController
    @State private var answerText: String = ""
    @State private var selectedImage: URL?
    
    var body: some View {
        HSplitView {
            VStack {
                if let selectedImage = selectedImage, let nsImage = NSImage(contentsOf: selectedImage) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                        .cornerRadius(8)
                } else {
                    Button("Select Radiograph") {
                        selectImage()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .layoutPriority(1)
            .padding()
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Question")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(controller.tutorQuestion.isEmpty ? "Select an image to start." : controller.tutorQuestion)
                        .font(.title3)
                        .padding(.vertical, 4)
                }
                
                Divider()
                
                VStack(alignment: .leading) {
                    Text("Your Findings")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $answerText)
                        .font(.body)
                        .padding(4)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .frame(minHeight: 100)
                    
                    HStack {
                        Button("Submit Answer") {
                            controller.submitTutorAnswer(answerText)
                        }
                        .disabled(answerText.isEmpty || controller.isTutorThinking)
                        
                        Button("Reveal Answer") {
                            controller.revealTutorAnswer()
                        }
                        .disabled(controller.isTutorThinking)
                    }
                }
                
                Divider()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !controller.tutorGrading.isEmpty {
                            Text("Grading")
                                .font(.headline)
                                .foregroundStyle(.orange)
                            Text(controller.tutorGrading)
                        }
                        
                        if !controller.tutorAnswerRevealed.isEmpty {
                            Text("Model Answer")
                                .font(.headline)
                                .foregroundStyle(.green)
                            Text(controller.tutorAnswerRevealed)
                        }
                    }
                }
            }
            .padding()
            .frame(minWidth: 300, maxWidth: 450)
        }
        .frame(minWidth: 800, minHeight: 600)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: selectImage) {
                    Label("Load Image", systemImage: "photo")
                }
            }
            ToolbarItem(placement: .automatic) {
                if controller.isTutorThinking {
                    ProgressView()
                }
            }
        }
    }
    
    private func selectImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK {
            self.selectedImage = panel.url
            self.answerText = ""
            if let path = panel.url?.path {
                controller.generateTutorQuestion(imagePath: path)
            }
        }
    }
}
