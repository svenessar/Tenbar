import AppKit
import SwiftUI

/// Windows-style tooltip shown above a hovered view. SwiftUI's `.help` doesn't appear in
/// Tenbar's non-activating panels, because Tenbar is never the active app.
@MainActor
final class TooltipController {
    static let shared = TooltipController()

    private var panel: NSPanel?
    private var pending: DispatchWorkItem?
    private weak var anchor: NSView?

    func schedule(_ text: String, above view: NSView) {
        pending?.cancel()
        anchor = view
        let work = DispatchWorkItem { [weak self, weak view] in
            guard let self, let view, self.anchor === view else { return }
            self.show(text, above: view)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func hide(from view: NSView? = nil) {
        if let view, anchor !== view { return }
        pending?.cancel()
        pending = nil
        anchor = nil
        panel?.orderOut(nil)
    }

    private func show(_ text: String, above view: NSView) {
        guard let window = view.window, window.isVisible, !text.isEmpty else { return }
        let anchorRect = window.convertToScreen(view.convert(view.bounds, to: nil))
        let panel = panel ?? makePanel()
        self.panel = panel
        let host = NSHostingView(rootView: TooltipLabel(text: text))
        panel.contentView = host
        let size = host.fittingSize
        var origin = CGPoint(x: anchorRect.midX - size.width / 2, y: anchorRect.maxY + 6)
        if let screen = window.screen ?? NSScreen.main {
            let bounds = screen.frame
            origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - size.width - 4)
            origin.y = min(origin.y, bounds.maxY - size.height - 4)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        return panel
    }
}

private struct TooltipLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.94))
            .lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color(white: 0.17))
            .overlay(Rectangle().stroke(Color(white: 0.35), lineWidth: 1))
            .fixedSize()
    }
}

/// Invisible view that tells the tooltip where its SwiftUI view is on screen.
private struct TooltipAnchor: NSViewRepresentable {
    let holder: TooltipAnchorHolder

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        holder.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        holder.view = nsView
    }
}

@MainActor
private final class TooltipAnchorHolder {
    weak var view: NSView?
}

private struct HoverTooltip: ViewModifier {
    let text: String
    @State private var holder = TooltipAnchorHolder()

    func body(content: Content) -> some View {
        content
            .background(TooltipAnchor(holder: holder))
            .onHover { inside in
                guard let view = holder.view else { return }
                if inside {
                    TooltipController.shared.schedule(text, above: view)
                } else {
                    TooltipController.shared.hide(from: view)
                }
            }
            .simultaneousGesture(TapGesture().onEnded { TooltipController.shared.hide() })
            .onDisappear { TooltipController.shared.hide(from: holder.view) }
    }
}

extension View {
    /// Shows `text` above the view after a short hover, like a Windows tooltip.
    func hoverTooltip(_ text: String) -> some View {
        modifier(HoverTooltip(text: text))
    }
}
