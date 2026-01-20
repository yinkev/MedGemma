import SwiftUI

struct SettingsView: View {
    @AppStorage("liveChunkLength") private var liveChunkLength: Double = 3.0
    @AppStorage("liveOverlap") private var liveOverlap: Double = 0.3
    @AppStorage("tutorArmedInterval") private var tutorArmedInterval: Int = 20
    @AppStorage("tutorMCQAutoSubmit") private var tutorMCQAutoSubmit: Bool = false
    @AppStorage("tutorCaptureMaxDimension") private var tutorCaptureMaxDimension: Int = 1400
    @AppStorage("tutorTokenPreset") private var tutorTokenPreset: String = "balanced"
    
    var body: some View {
        TabView {
            Form {
                Section("Live Transcription") {
                    VStack(alignment: .leading) {
                        Text("Chunk Length: \(liveChunkLength, specifier: "%.1f")s")
                        Slider(value: $liveChunkLength, in: 1.0...10.0, step: 0.5) {
                            Text("Chunk Length")
                        }
                        Text("Duration of audio segments sent to model")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Overlap: \(liveOverlap, specifier: "%.2f")")
                        Slider(value: $liveOverlap, in: 0.0...0.85, step: 0.05) {
                            Text("Overlap")
                        }
                        Text("Fraction of overlap between chunks to ensure continuity (must be < 0.9)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .tabItem {
                Label("General", systemImage: "gear")
            }
            .padding()
            
            Form {
                Section("Armed Mode") {
                    Picker("Capture Interval", selection: $tutorArmedInterval) {
                        Text("10 seconds").tag(10)
                        Text("15 seconds").tag(15)
                        Text("20 seconds").tag(20)
                        Text("30 seconds").tag(30)
                    }
                    .pickerStyle(.menu)
                    
                    Text("How often to capture screen in Armed mode")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section("Multiple Choice") {
                    Toggle("Auto-submit on click", isOn: $tutorMCQAutoSubmit)
                    Text("If enabled, clicking an option button will immediately submit the answer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Performance") {
                    Picker("Token Preset", selection: $tutorTokenPreset) {
                        Text("Fast").tag("fast")
                        Text("Balanced").tag("balanced")
                        Text("Quality").tag("quality")
                    }
                    .pickerStyle(.menu)

                    Text("Lower tokens = faster generation, less detail")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Stepper(value: $tutorCaptureMaxDimension, in: 800...2400, step: 100) {
                        Text("Capture Max Dimension: \(tutorCaptureMaxDimension)px")
                    }

                    Text("Downscales screenshots before sending to tutor")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tabItem {
                Label("Tutor", systemImage: "graduationcap")
            }
            .padding()
        }
        .frame(width: 450, height: 250)
    }
}
