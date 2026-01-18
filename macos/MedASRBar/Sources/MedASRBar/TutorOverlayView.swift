import SwiftUI

struct TutorOverlayView: View {
    @ObservedObject var controller: GemmaController
    @State private var isCollapsed = false
    @State private var answerText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "wand.and.stars")
                Text("MedGemma Tutor")
                    .font(.headline)
                Spacer()
                Button(action: { withAnimation { isCollapsed.toggle() }}) {
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
            
            if !isCollapsed {
                VStack(spacing: 12) {
                    if let img = controller.currentTutorImage, let nsImage = NSImage(contentsOf: img) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 120)
                            .cornerRadius(6)
                    } else {
                        Button("Pick Image") {
                            selectImage()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    if !controller.tutorQuestion.isEmpty {
                        Text(controller.tutorQuestion)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    HStack {
                        TextField("Answer...", text: $answerText)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Go") {
                            controller.submitTutorAnswer(answerText)
                        }
                        .disabled(answerText.isEmpty)
                    }
                    
                    if !controller.tutorGrading.isEmpty {
                        Text(controller.tutorGrading)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    if !controller.tutorAnswerRevealed.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Answer:")
                                .font(.caption2)
                                .bold()
                                .foregroundStyle(.green)
                            Text(controller.tutorAnswerRevealed)
                                .font(.caption2)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                    }
                    
                    HStack {
                        Button("Next Question") {
                             if let p = controller.currentTutorImage?.path {
                                 controller.generateTutorQuestion(imagePath: p)
                             }
                        }
                        .font(.caption)
                        
                        Spacer()
                        
                        Button("Reveal") {
                            controller.revealTutorAnswer()
                        }
                        .font(.caption)
                    }
                }
                .padding(10)
                .background(Color.black.opacity(0.8))
            }
        }
        .frame(width: 300)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func selectImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.level = .floating
        if panel.runModal() == .OK {
            if let path = panel.url?.path {
                controller.generateTutorQuestion(imagePath: path)
            }
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
