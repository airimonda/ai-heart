import AiHeartCore
import SwiftData
import SwiftUI

/// Changes a guessed mood point. Her touch makes it hers, so it is no longer marked as a guess.
struct GuessedPointPad: View {
    let entry: Entry
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var point = MoodPoint.center

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Drag the point to where it sits.").font(.subheadline).foregroundStyle(Palette.muted)
                MoodPad(point: Binding(get: { point }, set: { point = $0; apply($0) })).frame(height: 340)
                Spacer()
            }
            .padding(24)
            .background(Palette.surface.ignoresSafeArea())
            .navigationTitle("How it felt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { point = MoodPoint(valence: entry.valence ?? 0, arousal: entry.arousal ?? 0) }
        }
        .presentationDetents([.large])
    }

    private func apply(_ p: MoodPoint) {
        entry.valence = p.valence
        entry.arousal = p.arousal
        entry.moodGuessed = false
        entry.updatedAt = .now
        try? context.save()
    }
}
