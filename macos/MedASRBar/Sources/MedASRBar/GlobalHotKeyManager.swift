import Cocoa
import Carbon

@MainActor
final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()
    
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    var onHotKeyPress: (() -> Void)?
    
    private init() {}
    
    func register() {
        unregister()
        
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D454441), id: 1)
        let modifiers = cmdKey | shiftKey
        let keyCode = kVK_Space
        
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        
        if status != noErr {
            print("Failed to register hotkey: \(status)")
            return
        }
        
        let eventSpec = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        ]
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ -> OSStatus in
                DispatchQueue.main.async {
                    GlobalHotKeyManager.shared.onHotKeyPress?()
                }
                return noErr
            },
            1,
            eventSpec,
            nil,
            &eventHandler
        )
        
    }
    
    func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}
