import Cocoa
import ScreenCaptureKit

@MainActor
final class ScreenCaptureManager {
    static let shared = ScreenCaptureManager()
    
    private init() {}
    
    func captureScreen() async throws -> NSImage {
        let content: SCShareableContent

        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            if !CGPreflightScreenCaptureAccess() {
                throw NSError(
                    domain: "MedASR",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Screen Recording permission missing. Enable it in System Settings → Privacy & Security → Screen Recording."
                    ]
                )
            }
            throw error
        }
        
        guard let display = content.displays.first else {
            throw NSError(domain: "MedASR", code: 2, userInfo: [NSLocalizedDescriptionKey: "No display found to capture."])
        }
        
        let excludedWindows = content.windows.filter { 
            $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier 
        }
        
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: excludedWindows)
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.showsCursor = false
        
        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return NSImage(cgImage: cgImage, size: NSSize(width: display.width, height: display.height))
    }
    
    func saveImageToTemp(_ image: NSImage) throws -> URL {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "MedASR", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to PNG"])
        }
        
        let tempDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("MedASRBar") ?? URL(fileURLWithPath: NSTemporaryDirectory())
        
        if !FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        }
        
        let fileName = "capture_\(Int(Date().timeIntervalSince1970)).png"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        try pngData.write(to: fileURL)
        return fileURL
    }
}
