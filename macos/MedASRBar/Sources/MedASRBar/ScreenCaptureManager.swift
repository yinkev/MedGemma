import Cocoa
import CoreImage
import ScreenCaptureKit

@MainActor
final class ScreenCaptureManager {
    static let shared = ScreenCaptureManager()

    private let defaultTutorCaptureMaxDimension = 1400
    
    private init() {}

    private var tutorCaptureMaxDimension: Int {
        let raw = UserDefaults.standard.integer(forKey: "tutorCaptureMaxDimension")
        return raw > 0 ? raw : defaultTutorCaptureMaxDimension
    }
    
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
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    func captureScreenToTempFile() async throws -> URL {
        let image = try await captureScreen()
        return try saveImageToTemp(image)
    }
    
    private var captureDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MedASRBar", isDirectory: true)
    }

    func cleanupOldCaptures(maxAgeSeconds: TimeInterval = 24 * 60 * 60) {
        let dir = captureDirectory
        let fm = FileManager.default

        guard let urls = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let cutoff = Date().addingTimeInterval(-maxAgeSeconds)
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            guard let modified = values?.contentModificationDate else { continue }
            guard modified < cutoff else { continue }
            try? fm.removeItem(at: url)
        }
    }

    func isManagedCaptureURL(_ url: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL == captureDirectory.standardizedFileURL
    }

    func saveImageToTemp(_ image: NSImage) throws -> URL {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = downscaledBitmapIfNeeded(bitmap).representation(using: .png, properties: [:]) else {
            throw NSError(domain: "MedASR", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to PNG"])
        }

        let tempDir = captureDirectory

        if !FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        }

        let fileName = "capture_\(UUID().uuidString).png"
        let fileURL = tempDir.appendingPathComponent(fileName)

        try pngData.write(to: fileURL)
        return fileURL
    }

    private func downscaledBitmapIfNeeded(_ bitmap: NSBitmapImageRep) -> NSBitmapImageRep {
        let maxDimension = tutorCaptureMaxDimension
        guard maxDimension > 0 else { return bitmap }

        guard let cgImage = bitmap.cgImage else { return bitmap }

        let width = cgImage.width
        let height = cgImage.height
        let maxSide = max(width, height)

        guard maxSide > maxDimension else { return bitmap }

        let scale = Double(maxDimension) / Double(maxSide)

        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CILanczosScaleTransform") else { return bitmap }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        filter.setValue(1.0, forKey: kCIInputAspectRatioKey)

        guard let output = filter.outputImage else { return bitmap }

        let context = CIContext(options: nil)
        guard let scaled = context.createCGImage(output, from: output.extent) else { return bitmap }

        return NSBitmapImageRep(cgImage: scaled)
    }
}
