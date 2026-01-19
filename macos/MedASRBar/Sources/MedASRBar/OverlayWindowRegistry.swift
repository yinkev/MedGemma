import Cocoa
import Combine

@MainActor
final class OverlayWindowRegistry: ObservableObject {
    static let shared = OverlayWindowRegistry()
    
    @Published var isClickThrough: Bool = false {
        didSet {
            weakWindow?.ignoresMouseEvents = isClickThrough
        }
    }
    
    private weak var weakWindow: NSWindow?
    
    private init() {}
    
    func register(window: NSWindow) {
        window.identifier = NSUserInterfaceItemIdentifier("medasr_tutor_overlay")
        self.weakWindow = window
        window.ignoresMouseEvents = isClickThrough
    }
    
    func toggle() -> Bool {
        if let window = weakWindow {
            if window.isVisible {
                window.orderOut(nil)
            } else {
                if isClickThrough {
                    isClickThrough = false
                }
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            return true
        }
        return false
    }
    
    var isWindowRegistered: Bool {
        return weakWindow != nil
    }
    
    var window: NSWindow? {
        return weakWindow
    }
}
