import SwiftUI
import UniformTypeIdentifiers

struct PathologyLabView: View {
    @ObservedObject var controller: GemmaController
    @State private var isTargeted = false
    @State private var selectedImage: URL?
    
    var body: some View {
        HStack(spacing: 0) {
            VStack {
                if let selectedImage = selectedImage, let nsImage = NSImage(contentsOf: selectedImage) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.1))
                        .cornerRadius(8)
                        .onTapGesture {
                            selectImage()
                        }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "microscope")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Drag & Drop Pathology Image")
                            .font(.headline)
                        Text("or click to browse")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10]))
                            .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.3))
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectImage()
                    }
                }
                
                Button(action: {
                    if let path = selectedImage?.path {
                        controller.analyzePathology(imagePath: path)
                    }
                }) {
                    Text("Generate Report")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedImage == nil || controller.isAnalyzingPathology)
            }
            .padding()
            .frame(width: 300)
            .onDrop(of: [.image], isTargeted: $isTargeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            self.selectedImage = url
                        }
                    }
                }
                return true
            }
            
            Divider()
            
            VStack(alignment: .leading) {
                Text("Structured Report")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                if controller.isAnalyzingPathology {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                
                ScrollView {
                    Text(controller.pathologyReport.isEmpty ? "No analysis yet." : controller.pathologyReport)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                
                HStack {
                    Text(controller.serviceStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.top, 8)
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 500)
    }
    
    private func selectImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK {
            self.selectedImage = panel.url
        }
    }
}
