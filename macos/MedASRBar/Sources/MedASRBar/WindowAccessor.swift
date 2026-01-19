import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        WindowObservingView(onResolve: onResolve)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
    }
}

private final class WindowObservingView: NSView {
    private let onResolve: (NSWindow) -> Void

    init(onResolve: @escaping (NSWindow) -> Void) {
        self.onResolve = onResolve
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        onResolve(window)
    }
}
