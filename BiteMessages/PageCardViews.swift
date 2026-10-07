import SwiftUI
import BiteKit

/// The card a page is sent as: its lines as Bite shows them, on its wash, with room above them for
/// the badge Messages puts in the corner, and as much below them over the bar. As tall as its
/// lines, up to `PageCard.tallest`, whole: a line that doesn't fit isn't begun (see `PageCard.image`).
/// Its heading is in the bar (see `PageCard.barTitle`).
struct PageCardFace: View {
    let card: PageCard
    var height = PageCard.tallest
    /// Told where the lines end.
    var contentEnd: ContentEnd?
    static let top: CGFloat = 44
    static let bottom: CGFloat = 20
    static let side: CGFloat = 18

    var body: some View {
        let ink = DotPalette.colors[card.page]
        let glance = PageGlance(markdown: card.markdown).withoutTitle()
        ZStack(alignment: .topLeading) {
            PageWash(ink: ink)
            PageGlanceView(glance: glance, page: card.page, ink: ink, metrics: GlanceMetrics(scale: 0.8), ticks: false,
                           contentEnd: contentEnd)
                .padding(EdgeInsets(top: Self.top, leading: Self.side, bottom: Self.bottom, trailing: Self.side))
        }
        .frame(width: PageCard.size.width, height: height)
    }
}

/// What Bite in Messages shows: the pages to send, or a page sent, being read.
struct MessagesRoot: View {
    @Bindable var model: MessagesModel

    var body: some View {
        if let card = model.reading {
            PageReader(card: card)
        } else {
            PagePicker(model: model)
        }
    }
}

/// Every page, a card each, slid through or picked by its dot, as in Bite, empty ones too (user,
/// 2026-10-07): a card tapped goes into the message field, to be sent from there. Every card is the
/// same size, the page with its title, whatever's sent (user, the same day); what's sent is as tall
/// as the page, its title in the bar under it (see `PageCardFace`). A page with nothing on it says
/// so, and has nothing to send.
struct PagePicker: View {
    @Bindable var model: MessagesModel
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let isEmpty = model.pages.map { PageGlance(markdown: $0).isEmpty }
        VStack(spacing: 10) {
            DotRow(selection: $model.selection, isEmpty: isEmpty)
            TabView(selection: $model.selection) {
                ForEach(DotPalette.colors.indices, id: \.self) { page in
                    let card = PageCard(page: page, markdown: model.pages[page])
                    Button {
                        model.send(card)
                    } label: {
                        Group {
                            if let image = model.pickerImage(for: page, scale: displayScale) {
                                Image(uiImage: image).resizable()
                            } else {
                                Color.clear
                            }
                        }
                        .aspectRatio(PageCard.size, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isEmpty[page])
                    .accessibilityLabel(isEmpty[page] ? "\(DotPalette.colors[page].name) page, empty" : card.title)
                    .accessibilityHint(isEmpty[page] ? "" : "Adds the page to the message")
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .padding(.top, 10)
    }
}

/// A page as the picker shows it: its lines as Bite shows them, its title too, on its wash, as
/// many as fit, the last one going under the bottom edge. Drawn as a picture: drawn live in the
/// drawer, the fade at its bottom came out as a grey band, the drawer not taking the blend that
/// fades it.
struct PickerCardFace: View {
    let card: PageCard

    var body: some View {
        let ink = DotPalette.colors[card.page]
        let glance = PageGlance(markdown: card.markdown)
        ZStack(alignment: .topLeading) {
            PageWash(ink: ink)
            if glance.isEmpty {
                // As a widget says a page has nothing on it.
                DotStatement(title: ink.name, ink: ink, line: "Nothing here yet")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PageGlanceView(glance: glance, page: card.page, ink: ink, metrics: GlanceMetrics(scale: 0.8), ticks: false,
                               safeBottom: PageLines.bottom)
                    .padding(EdgeInsets(top: 18, leading: 18, bottom: 0, trailing: 18))
            }
        }
        .frame(width: PageCard.size.width, height: PageCard.size.height)
    }
}

/// Bite's dots, a ring each and the page picked solid, a page with nothing on it in grey, picked or
/// not, as Bite's dot bar has them: nothing goes on a page from here.
private struct DotRow: View {
    @Binding var selection: Int
    let isEmpty: [Bool]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DotPalette.colors.indices, id: \.self) { dot in
                Button {
                    withAnimation(.smooth(duration: 0.3)) { selection = dot }
                } label: {
                    DotRing(ink: isEmpty[dot] ? DotPalette.empty : DotPalette.colors[dot],
                            isSelected: dot == selection, size: 16)
                        .frame(width: 28, height: 28)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(DotPalette.colors[dot].name) page")
                .accessibilityAddTraits(dot == selection ? .isSelected : [])
            }
        }
    }
}

/// A page sent in Messages, read whole, as Bite shows it, on its wash: to read, not to change.
struct PageReader: View {
    let card: PageCard

    var body: some View {
        let ink = DotPalette.colors[card.page]
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageGlanceView(glance: PageGlance(markdown: card.markdown), page: card.page, ink: ink,
                               metrics: GlanceMetrics(scale: 1), ticks: false, showsAll: true)
                if card.isCut {
                    Text("The rest of this page was too long to send.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .textSelection(.enabled)
            .padding(EdgeInsets(top: 20, leading: 22, bottom: 32, trailing: 22))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(PageWash(ink: ink).ignoresSafeArea())
    }
}
