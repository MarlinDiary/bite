import SwiftUI
import BiteKit

/// A page's words, characters and paragraphs, and when it last changed, from the "…" menu: a
/// drawer like Settings.
struct StatisticsView: View {
    let statistics: PageStatistics
    let modified: Date?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Words", value: statistics.words, format: .number)
                    LabeledContent("Characters", value: statistics.characters, format: .number)
                    LabeledContent("Paragraphs", value: statistics.paragraphs, format: .number)
                }
                if let modified {
                    Section {
                        LabeledContent("Modified", value: ModifiedDate.text(modified))
                    }
                }
            }
            .fittedSheet()
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
