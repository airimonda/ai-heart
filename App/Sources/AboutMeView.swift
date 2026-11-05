import AiHeartCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// About me. Not in the mockups (README lists it as not designed); built from the
/// template's sections in the app's card style. Her words, kept on her devices only.
struct AboutMeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AboutMe.updatedAt) private var rows: [AboutMe]
    @State private var doc = AboutMeDoc.template
    @State private var loaded = false
    @State private var importing = false
    @State private var confirmReplace: AboutMeDoc?
    @State private var addingSection = false
    @State private var newTitle = ""
    @State private var importError = false
    @State private var open: Set<String> = []
    @State private var reviewing = false
    @State private var tidyDismissed = false

    private var tidy: AboutMeDoc.Tidied { doc.tidied() }
    private var tidySummary: String {
        let n = tidy.repeats.count, f = tidy.foldedSections.count
        var bits: [String] = []
        if f > 0 { bits.append("\(f) section\(f == 1 ? "" : "s") to merge") }
        if n > 0 { bits.append("\(n) line\(n == 1 ? "" : "s") said twice") }
        return bits.joined(separator: ", ") + ". Nothing changes until you say."
    }

    /// Filled sections and any she just opened, the three from her memory seed first.
    private var shownTitles: [String] {
        let shown = doc.sections.filter { !$0.body.isEmpty || open.contains($0.title) }.map(\.title)
        let first = [AboutMeDoc.aboutHerTitle, AboutMeDoc.voiceTitle, AboutMeDoc.nowTitle].filter(shown.contains)
        return first + shown.filter { !first.contains($0) }
    }

    /// Empty sections stay out of the way until she picks one.
    private var hiddenTitles: [String] {
        doc.sections.filter { $0.body.isEmpty && !open.contains($0.title) }.map(\.title)
    }

    private func bodyBinding(_ title: String) -> Binding<String> {
        Binding(
            get: { doc.sections.first { $0.title == title }?.body ?? "" },
            set: { v in if let i = doc.sections.firstIndex(where: { $0.title == title }) { doc.sections[i].body = v } })
    }

    /// Closed: the title and two lines. Open: all of it, editable.
    private func sectionCard(_ title: String) -> some View {
        let isOpen = open.contains(title)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isOpen { open.remove(title) } else { open.insert(title) }
                }
            } label: {
                HStack {
                    Text(title).font(.headline).foregroundStyle(Palette.ink).multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold)).foregroundStyle(Palette.muted)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .frame(minHeight: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "Closes this section" : "Opens this section")
            if isOpen {
                TextField("Anything, or nothing.", text: bodyBinding(title), axis: .vertical)
                    .font(.journal(.body))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2...40)
            } else {
                Text(bodyBinding(title).wrappedValue)
                    .font(.journal(.subheadline))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .contextMenu {
            if !AboutMeDoc.templateTitles.contains(title) {
                Button("Remove section", systemImage: "minus.circle", role: .destructive) {
                    doc.sections.removeAll { $0.title == title }
                    open.remove(title)
                }
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("About me")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Palette.ink)
                    Text(CloudSettings.isOn ? "In your words. It is stored on this phone; with the cloud model on, it goes with some requests." : "In your words. It stays on this phone.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }

                if tidy.hasWork && !tidyDismissed {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Some of this repeats").font(.headline).foregroundStyle(Palette.ink)
                        Text(tidySummary).font(.subheadline).foregroundStyle(Palette.muted)
                        HStack(spacing: 16) {
                            Button("Review") { reviewing = true }
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.onTint).frame(minHeight: 44)
                            Button("Leave it") { tidyDismissed = true }
                                .font(.subheadline).foregroundStyle(Palette.muted).frame(minHeight: 44)
                        }
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading).card()
                }

                ForEach(shownTitles, id: \.self) { title in
                    sectionCard(title)
                }

                if !hiddenTitles.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted)
                        FlowLayout(spacing: 8) {
                            ForEach(hiddenTitles, id: \.self) { title in
                                Chip(title: title) { open.insert(title) }
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                AboutMeProposalsCard(doc: $doc)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.surface.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Import from a file", systemImage: "doc") { importing = true }
                    Button("Add a section", systemImage: "plus") { addingSection = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, UTType(filenameExtension: "md") ?? .plainText]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { importError = true; return }
            let imported = AboutMeDoc.parse(text)
            if doc.isEmpty { doc = imported; save() } else { confirmReplace = imported }
        }
        .confirmationDialog("Replace what is here?", isPresented: Binding(get: { confirmReplace != nil }, set: { if !$0 { confirmReplace = nil } }), titleVisibility: .visible) {
            Button("Replace", role: .destructive) {
                if let d = confirmReplace { doc = d; save() }
                confirmReplace = nil
            }
            Button("Cancel", role: .cancel) { confirmReplace = nil }
        } message: {
            Text("The file's text takes the place of your current About me.")
        }
        .sheet(isPresented: $reviewing) {
            let t = tidy
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !t.foldedSections.isEmpty {
                            Text("Merged, with every word kept").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted)
                            ForEach(t.foldedSections, id: \.self) { Text($0).font(.body).foregroundStyle(Palette.ink) }
                        }
                        if !t.repeats.isEmpty {
                            Text("Removed, because a fuller copy stays").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted)
                            ForEach(t.repeats, id: \.self) { Text($0).font(.journal(.body)).foregroundStyle(Palette.ink) }
                        }
                        Button("Tidy up") {
                            doc = t.doc
                            save()
                            reviewing = false
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Palette.surface.ignoresSafeArea())
                .navigationTitle("Review").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { reviewing = false } } }
            }
        }
        .alert("Add a section", isPresented: $addingSection) {
            TextField("Title", text: $newTitle)
            Button("Add") {
                let t = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty, !doc.sections.contains(where: { $0.title == t }) {
                    doc.sections.append(.init(title: t, body: ""))
                    open.insert(t)
                }
                newTitle = ""
            }
            Button("Cancel", role: .cancel) { newTitle = "" }
        }
        .alert("That file could not be read.", isPresented: $importError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Choose a plain text or Markdown file.")
        }
        .onAppear {
            guard !loaded else { return }
            if let row = rows.first, !row.markdown.isEmpty { doc = AboutMeDoc.parse(row.markdown) }
            loaded = true
        }
        .onChange(of: doc) { if loaded { save() } }
        .onDisappear(perform: save)
    }

    /// Single row, enforced in code (no unique constraints with CloudKit).
    private func save() {
        let md = doc.markdown
        let row: AboutMe
        if let first = rows.first {
            row = first
            rows.dropFirst().forEach(context.delete)
        } else {
            row = AboutMe()
            context.insert(row)
        }
        guard row.markdown != md else { return }
        row.markdown = md
        row.updatedAt = .now
        try? context.save()
    }
}
