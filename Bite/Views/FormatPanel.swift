import SwiftUI
import UIKit
import BiteKit

/// The Aa button at the dot bar's start, on an iPad: Bite's format panel grows out of it, as
/// Notes' does out of its own. An iPad shows no format bar on its keys (see
/// `PagerContainerView.showsBar`). Nothing on a phone, whose bar has them.
struct FormatButton: View {
    let dot: Int
    /// The window it's in, of Bite's several on an iPad.
    @Environment(PageWindow.self) private var window

    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            SystemBarButton(symbol: "textformat", title: "Format", edge: .leading, tint: UIColor(DotPalette.colors[dot].color)) { item in
                // This window's page is the one the panel acts on.
                PageWindows.shared.makeCurrent(window)
                // With no page being typed in here, the page on screen takes the keys first, for
                // the styles to go on: at the caret where it was.
                if window.editor?.dot != dot { window.pager?.controllers[dot].focus() }
                FormatPanel.shared.show(from: item, in: window.window)
            }
            .frame(width: DotSwitcher.height, height: DotSwitcher.height)
            #if DEBUG
            .onAppear {
                // `-showFormatPanel` opens the panel as Bite launches, with `-startLine`, for a
                // picture of it. Out of the window's corner: the button isn't to hand here.
                guard CommandLine.arguments.contains("-showFormatPanel") else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    FormatPanel.shared.showForTesting()
                }
            }
            #endif
        }
    }
}

/// Bite's format panel, out of Aa, drawn as the system's own (`UITextFormattingViewController`,
/// Notes' and Mail's) is, with Bite's styles in it. The system's has an underline and a dashed
/// list, which Markdown hasn't, and no room for to-dos or quotes (user, 2026-10-08): the line as a
/// heading or plain text, in a row of its own; bold, italic, strikethrough and quote; bulleted and
/// numbered lists and to-dos, and indenting. Code blocks stay with the menu bar and Markdown.
/// What's on where the caret or selection is shows in the page's colour, kept up while it's out.
@MainActor @Observable
final class FormatPanel: NSObject, UIPopoverPresentationControllerDelegate {
    static let shared = FormatPanel()

    /// The heading level, or plain text, of the line the caret's on. Nil for a list's, a quote's
    /// or code.
    private(set) var lineStyle: BlockKind?
    /// The styles and kinds of line on where the caret or selection is.
    private(set) var lit: Set<FormatAction> = []
    @ObservationIgnored private weak var panel: UIViewController?

    /// The page being typed in, if one is.
    var editor: EditorController? {
        guard let editor = FormatBar.shared.editor, editor.textView.isFirstResponder else { return nil }
        return editor
    }

    /// The kinds of line the panel's buttons turn lines into, and back.
    static let lineKinds: [FormatAction: BlockKind] = [.bullet: .bullet, .ordered: .ordered, .todo: .todo, .quote: .quote]

    /// Opens the panel out of `item`, as a popover.
    func show(from item: UIBarButtonItem, in window: UIWindow?) {
        // One still out in another of Bite's windows goes first.
        if let panel, panel.view.window !== window {
            panel.presentingViewController?.dismiss(animated: false)
            self.panel = nil
        }
        guard panel == nil, var top = window?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        refresh()
        let tint = FormatBar.shared.editor?.textView.tintColor ?? .tintColor
        let panel = UIHostingController(rootView: FormatPanelView(panel: self).tint(Color(uiColor: tint)))
        panel.view.backgroundColor = .clear
        panel.preferredContentSize = FormatPanelView.size
        panel.modalPresentationStyle = .popover
        panel.popoverPresentationController?.sourceItem = item
        panel.popoverPresentationController?.delegate = self
        self.panel = panel
        top.present(panel, animated: true)
    }

    #if DEBUG
    /// Opens the panel as Aa does, out of the dot bar's start, for a picture of it.
    func showForTesting() {
        func button(in view: UIView) -> SystemBarButtonView? {
            if let button = view as? SystemBarButtonView, button.item.menu == nil { return button }
            return view.subviews.lazy.compactMap(button(in:)).first
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.first?.keyWindow, let aa = button(in: window) else { return }
        show(from: aa.item, in: window)
    }
    #endif

    /// Shows what's on now, as the caret moves while the panel is out.
    func refresh() {
        guard let editor = FormatBar.shared.editor else {
            lineStyle = nil
            lit = []
            return
        }
        let styles = editor.activeStyles
        var lit = Set(FormatAction.allCases.filter { $0.style.map(styles.contains) ?? false })
        for (action, kind) in Self.lineKinds where editor.linesAre(kind) {
            lit.insert(action)
        }
        if self.lit != lit { self.lit = lit }
        let lineStyle = editor.lineStyle
        if self.lineStyle != lineStyle { self.lineStyle = lineStyle }
    }

    func perform(_ action: FormatAction) {
        FormatBar.shared.editor?.perform(action)
        refresh()
    }

    func setLineStyle(_ kind: BlockKind) {
        FormatBar.shared.editor?.setLineStyle(kind)
        refresh()
    }

    /// A popover still on an iPad in a narrow window, not a sheet.
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        .none
    }
}

/// The panel's rows, laid out and coloured as the system's format panel's, measured from it on a
/// 13-inch iPad: 375 by 195 points, rows 44 tall and 15 apart, groups as capsules on the system's
/// fill, their buttons a point apart.
private struct FormatPanelView: View {
    let panel: FormatPanel

    static let size = CGSize(width: 375, height: 195)
    private static let rowHeight: CGFloat = 44
    private static let inset: CGFloat = 16

    /// Each line style in the page's own type, as the system's panel shows its styles.
    private static let lineStyles: [(title: String, kind: BlockKind, font: Font)] = [
        ("Heading 1", .heading1, .system(size: 28, weight: .bold)),
        ("Heading 2", .heading2, .system(size: 22, weight: .bold)),
        ("Heading 3", .heading3, .system(size: 19, weight: .semibold)),
        ("Text", .paragraph, .system(size: 17)),
    ]

    var body: some View {
        VStack(spacing: 15) {
            styleRow
            group([.bold, .italic, .strikethrough, .quote], width: Self.size.width - 2 * Self.inset)
            HStack(spacing: 14) {
                group([.bullet, .ordered, .todo], width: 200)
                group([.outdent, .indent], width: Self.size.width - 2 * Self.inset - 200 - 14)
            }
        }
        .padding(.top, 17)
        .padding(.bottom, 16)
        .frame(width: Self.size.width)
    }

    /// The line styles, in a row that scrolls to the panel's edges, the line's own lit.
    private var styleRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Self.lineStyles, id: \.title) { style in
                        let isOn = panel.lineStyle == style.kind
                        Button {
                            panel.setLineStyle(style.kind)
                        } label: {
                            Text(style.title)
                                .font(style.font)
                                .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                                .padding(.horizontal, 18)
                                .frame(height: Self.rowHeight)
                                .background {
                                    if isOn { Capsule().fill(.tint) }
                                }
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.highlight)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                        .id(style.kind)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, Self.inset, for: .scrollContent)
            .onAppear {
                // Only as far as it takes to show it, as the system's panel does.
                if let style = panel.lineStyle { proxy.scrollTo(style) }
            }
        }
        .frame(height: Self.rowHeight)
    }

    /// Buttons side by side in a capsule, a point apart, as the system's panel has its own.
    private func group(_ actions: [FormatAction], width: CGFloat) -> some View {
        HStack(spacing: 1) {
            ForEach(actions, id: \.self) { action in
                let isOn = panel.lit.contains(action)
                Button {
                    panel.perform(action)
                } label: {
                    (action.hasOwnSymbol ? Image(action.symbol) : Image(systemName: action.symbol))
                        .font(.system(size: 19))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(uiColor: .tertiarySystemFill)))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .accessibilityLabel(action.title)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .frame(width: width, height: Self.rowHeight)
        .clipShape(.capsule)
    }
}
