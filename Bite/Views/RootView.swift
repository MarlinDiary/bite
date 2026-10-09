import CoreSpotlight
import SwiftUI
import BiteKit

/// One of Bite's windows: the pages, on the page this window was last on. An iPad can have several
/// open (see `PageWindow`).
struct RootView: View {
    @Environment(DotStore.self) private var store
    /// The page this window was on, kept for it as Bite closes and opens again. A new window opens
    /// on the page Bite's on.
    @SceneStorage("page") private var savedPage = -1

    var body: some View {
        WindowPages(savedPage: $savedPage, firstPage: savedPage >= 0 ? savedPage : store.selection)
    }
}

private struct WindowPages: View {
    @Binding var savedPage: Int
    @State private var window: PageWindow
    @Environment(DotStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    /// Bite's welcome, the first time it opens (see `Welcome`).
    @State private var showsWelcome = false

    init(savedPage: Binding<Int>, firstPage: Int) {
        _savedPage = savedPage
        _window = State(initialValue: PageWindow(page: firstPage))
    }

    var body: some View {
        PagesView(leading: { FormatButton(dot: $0) }, trailing: { DotMenu(dot: $0) }, selection: Bindable(window).page)
            .environment(window)
            // What the menu bar acts on, in the window in front.
            .focusedSceneValue(window)
            .onChange(of: window.page, initial: true) { _, page in
                if savedPage != page { savedPage = page }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { store.saveNow() }
            }
            // A Spotlight result, opened here: Bite launched by it opened it already, before its
            // first frame (see `SceneDelegate`).
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                guard activity !== SceneDelegate.launchActivity else { return }
                PageWindows.shared.makeCurrent(window)
                SpotlightIndex.open(activity, in: store)
            }
            // A widget, tapped, opens the page it shows, here.
            .onOpenURL { link in
                PageWindows.shared.makeCurrent(window)
                if let page = PageTurns.page(openedBy: link) { store.open(dot: page) }
            }
            // Opened in a window already open, rather than a new one.
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
            .sheet(isPresented: $showsWelcome) {
                WelcomeSheet()
            }
            .onAppear {
                if Welcome.isDue(firstLaunch: store.isFirstLaunch) { showsWelcome = true }
            }
            #if DEBUG
            .onAppear {
                // `-showLinkSheet` brings up Add Link as Bite launches, with `-startLine`, for a
                // picture of it.
                // `-showWebPage <address>` opens a web page as a tapped link does, with `-startLine`.
                let arguments = CommandLine.arguments
                if let index = arguments.firstIndex(of: "-showWebPage"), index + 1 < arguments.count,
                   let url = URL(string: arguments[index + 1]) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        FormatBar.shared.editor?.textView.showWebPage(url)
                    }
                }
                // `-showFind <words>` finds the words on the page as ⌘F does, with `-startLine`.
                if let index = arguments.firstIndex(of: "-showFind"), index + 1 < arguments.count {
                    let words = arguments[index + 1]
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        guard let find = FormatBar.shared.editor?.textView.findInteraction else { return }
                        find.searchText = words
                        find.presentFindNavigator(showingReplace: false)
                    }
                }
                // `-newWindow` opens a second window, as New Window does.
                if arguments.contains("-newWindow"), UIApplication.shared.connectedScenes.count == 1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        PageWindows.shared.openWindow(from: window)
                    }
                }
                // `-barEnd` shows the format bar's second page, with `-startLine`, for a picture.
                if arguments.contains("-barEnd") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { FormatBar.shared.scrollButtonsToEnd() }
                }
                guard arguments.contains("-showLinkSheet") else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    FormatBar.shared.editor?.perform(.link)
                }
            }
            #endif
    }
}
