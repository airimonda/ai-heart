import AiHeartCore
import CoreImage
import Foundation
import HuggingFace
import os
import SwiftData
import MLXLLM
import MLXLMCommon
import MLXVLM
import SwiftUI
import Tokenizers

/// The on-device models she can pick between (docs/19). Gemma stays the default. Each has its
/// own folder name (after its repo), so either can be copied from a Mac with devicectl.
enum ModelChoice: String, CaseIterable, Identifiable {
    case qwen8b = "qwen3-8b"
    case qwen = "qwen3-vl-4b"
    case gemma = "gemma-4-e2b"

    var id: String { rawValue }

    var configuration: MLXLMCommon.ModelConfiguration {
        switch self {
        case .gemma: VLMRegistry.gemma4_E2B_it_4bit
        case .qwen: VLMRegistry.qwen3VL4BInstruct4Bit
        case .qwen8b: LLMRegistry.qwen3_8b_4bit
        }
    }

    var displayName: String {
        switch self { case .gemma: "Gemma 4 E2B"; case .qwen: "Qwen3-VL 4B"; case .qwen8b: "Qwen3 8B" }
    }
    var pickerTitle: String {
        switch self {
        case .qwen8b: "Qwen3 8B (default, reads context best)"
        case .qwen: "Qwen3-VL 4B (smaller; also reads photos)"
        case .gemma: "Gemma 4 E2B (smallest, older)"
        }
    }
    var size: String {
        switch self { case .gemma: "3.6 GB"; case .qwen: "3.1 GB"; case .qwen8b: "4.6 GB" }
    }
    var folderName: String {
        switch self { case .gemma: "gemma-4-e2b-it-4bit"; case .qwen: "qwen3-vl-4b-instruct-mlx-4bit"; case .qwen8b: "qwen3-8b-4bit" }
    }
    /// Lower-case piece of the Hugging Face cache folder name for this model.
    var hubMatch: String {
        switch self { case .gemma: "gemma-4"; case .qwen: "qwen3-vl-4b"; case .qwen8b: "qwen3-8b" }
    }
    /// Gemma keeps its original key, so a phone that already has it is unchanged.
    var downloadedKey: String { self == .gemma ? "llm.downloaded" : "llm.downloaded.\(rawValue)" }
    /// Text-only models borrow the photo model for images (owner, 2026-11-04: 8B reads context best,
    /// but has no eyes). Loaded only for that request, one model in memory at a time.
    var seesImages: Bool { self != .qwen8b }
    /// The model whose files "Remove the other model's files" frees. With 8B, that is Gemma: the
    /// Qwen3-VL files stay because 8B borrows them for photos.
    var other: ModelChoice {
        switch self { case .gemma: .qwen; case .qwen: .gemma; case .qwen8b: .gemma }
    }

    /// Files copied onto the phone (same check as LLMService.hasLocalCopy, usable before it exists).
    var hasFiles: Bool {
        let fm = FileManager.default
        guard ["config.json", "tokenizer.json"].allSatisfy({ fm.fileExists(atPath: localDirectory.appendingPathComponent($0).path) }) else { return false }
        return ((try? fm.contentsOfDirectory(atPath: localDirectory.path)) ?? []).contains { $0.hasSuffix(".safetensors") }
    }

    var localDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Models/\(folderName)", isDirectory: true)
    }
}

/// The chosen model (Gemma 4 E2B or Qwen3-VL 4B, both 4-bit) through MLX, on this device only
/// (docs/03, docs/19). Downloaded once from Hugging Face; after that this model sends nothing off the
/// phone. With her cloud switch on, only the features on `LLMFeature.mayUseCloud` use the cloud (behind
/// the self-harm gate); photos, media and the rest stay here. Runs on demand, never in the background.
/// Only one model is in memory at a time.
@MainActor @Observable
final class LLMService {
    static let shared = LLMService()

    enum State: Equatable {
        case notDownloaded
        case downloading(Double)
        case loading
        case ready
        case failed(String)
        /// MLX has no GPU in the simulator; the built-in rules stand in.
        case unsupported
    }

    var state: State = .notDownloaded
    private var container: MLXLMCommon.ModelContainer?
    /// Per device: the files are per device. The picker also writes AppSettings.modelChoice.
    private(set) var choice: ModelChoice
    static let choiceKey = "llm.choice"
    static let downloadedKey = ModelChoice.gemma.downloadedKey

    var configuration: MLXLMCommon.ModelConfiguration { choice.configuration }
    var approximateSize: String { choice.size }

    init() {
        // Owner, 2026-11-04: Qwen3 8B read context best in the eval (docs/19); used when its files are here.
        let saved = UserDefaults.standard.string(forKey: Self.choiceKey).flatMap(ModelChoice.init(rawValue:))
        let fallback: ModelChoice = ModelChoice.qwen8b.hasFiles ? .qwen8b : .qwen
        choice = saved.map { $0 == .qwen && ModelChoice.qwen8b.hasFiles && !UserDefaults.standard.bool(forKey: "llm.choice.byHer") ? .qwen8b : $0 } ?? fallback
        #if targetEnvironment(simulator)
        state = .unsupported
        #endif
    }

    /// A model copied onto the phone from her Mac (faster than downloading on the phone).
    var localDirectory: URL { choice.localDirectory }

    func hasLocalCopy(_ c: ModelChoice) -> Bool {
        let d = c.localDirectory
        let fm = FileManager.default
        guard ["config.json", "tokenizer.json"].allSatisfy({ fm.fileExists(atPath: d.appendingPathComponent($0).path) }) else { return false }
        // One file or shards, depending on the repo.
        return ((try? fm.contentsOfDirectory(atPath: d.path)) ?? []).contains { $0.hasSuffix(".safetensors") }
    }

    var hasLocalCopy: Bool { hasLocalCopy(choice) }

    func isDownloaded(_ c: ModelChoice) -> Bool { hasLocalCopy(c) || UserDefaults.standard.bool(forKey: c.downloadedKey) }
    var isDownloaded: Bool { CloudSettings.isOn || isDownloaded(choice) }

    /// The model to use right now for one part of the app (owner, 2026-11-05). With the cloud switch on, the
    /// features on `LLMFeature.mayUseCloud` get the cloud model, behind the self-harm gate: a request that
    /// fails the gate, or carries a photo, goes to the on-device model instead. Photos, media captions and
    /// anything not on the list never use the cloud: they get the on-device model (loaded for that request
    /// when the cloud is on), or the built-in rules when it is not on the phone.
    func model(for feature: LLMFeature) -> any AiHeartCore.LanguageModel {
        if CloudSettings.isOn, let key = CloudSettings.apiKey {
            let local: (any AiHeartCore.LanguageModel)? = hasLocalCopy(.qwen) ? OnDeviceOnDemandModel() : nil
            guard feature.mayUseCloud else { return local ?? RuleBasedModel() }
            return GatedCloudModel(cloud: OpenRouterModel(modelID: CloudSettings.modelID, apiKey: key), local: local)
        }
        if let container, state == .ready {
            let borrow = !choice.seesImages && hasLocalCopy(.qwen)
            var m = OnDeviceModel(container: container, name: choice.displayName)
            m.seesImages = choice.seesImages || borrow
            m.thinkingModel = choice == .qwen8b
            if borrow {
                let v: @MainActor @Sendable (GenerationRequest) async throws -> String = { req in
                    try await LLMService.shared.generateWithPhotoModel(req)
                }
                m.vision = v
            }
            return m
        }
        return RuleBasedModel()
    }

    /// Whether `model(for:)` can answer at all right now: the cloud for its features (whether it is reachable
    /// is only known when a request is made), else the on-device model loaded or, with the cloud on, its files.
    func canAnswer(_ feature: LLMFeature) -> Bool {
        if CloudSettings.isOn { return feature.mayUseCloud || hasLocalCopy(.qwen) }
        return state == .ready
    }

    private var onDemand: MLXLMCommon.ModelContainer?
    private var onDemandBusy = false
    private var onDemandRelease: Task<Void, Never>?

    /// With the cloud on, the on-device model is not kept in memory. A request that must stay on the phone
    /// loads Qwen3-VL 4B, answers, and frees it after a minute of quiet (so a burst of calls loads it once).
    func generateOnDemand(_ request: GenerationRequest) async throws -> String {
        guard hasLocalCopy(.qwen) else { throw CloudRefusal() }
        while onDemandBusy { try await Task.sleep(nanoseconds: 200_000_000) }
        onDemandBusy = true
        defer { onDemandBusy = false }
        onDemandRelease?.cancel()
        let c: MLXLMCommon.ModelContainer
        if let onDemand { c = onDemand } else {
            c = try await loadModelContainer(from: ModelChoice.qwen.localDirectory, using: TransformersLoader())
            onDemand = c
            NSLog("AiHeartLLM on-device model loaded for this request, available memory %d MB", Int(os_proc_available_memory() / 1_000_000))
        }
        onDemandRelease = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            if !Task.isCancelled { self.onDemand = nil }
        }
        return try await OnDeviceModel(container: c, name: ModelChoice.qwen.displayName, seesImages: true).generate(request)
    }

    /// For a text-only model and a request with an image: free the text model, load the photo model
    /// for this one request, free it, and load the text model again. About 2 s each way on her phone.
    func generateWithPhotoModel(_ request: GenerationRequest) async throws -> String {
        if let loading { await loading.value }
        let keep = choice
        container = nil
        state = .loading
        defer { Task { @MainActor in if self.choice == keep { await self.prepare() } } }
        let vision = try await loadModelContainer(from: ModelChoice.qwen.localDirectory, using: TransformersLoader())
        NSLog("AiHeartLLM photo model borrowed, available memory %d MB", Int(os_proc_available_memory() / 1_000_000))
        return try await OnDeviceModel(container: vision, name: ModelChoice.qwen.displayName, seesImages: true).generate(request)
    }

    private var loading: Task<Void, Never>?

    /// Downloads (first time) and loads the model into memory. Only one load runs at a
    /// time; other callers wait for it (two at once would need twice the memory).
    func prepare() async {
        // Cloud: nothing to load, and the on-device model stays out of memory.
        if CloudSettings.isOn {
            if container != nil { container = nil }
            #if !targetEnvironment(simulator)
            state = .ready
            #endif
            return
        }
        if let loading { await loading.value; return }
        let t = Task { await self.load() }
        loading = t
        await t.value
        loading = nil
    }

    private func load() async {
        #if targetEnvironment(simulator)
        state = .unsupported
        return
        #else
        if case .ready = state { return }
        if case .downloading = state { return }
        let chosen = choice
        state = isDownloaded ? .loading : .downloading(0)
        do {
            if hasLocalCopy(chosen) {
                // Keep the weights out of iCloud backups.
                var dir = chosen.localDirectory
                var v = URLResourceValues(); v.isExcludedFromBackup = true
                try? dir.setResourceValues(v)
                let t0 = Date()
                NSLog("AiHeartLLM loading local copy of %@, available memory %d MB", chosen.rawValue, Int(os_proc_available_memory() / 1_000_000))
                let c = try await loadModelContainer(from: chosen.localDirectory, using: TransformersLoader())
                guard chosen == choice else { return }
                container = c
                NSLog("AiHeartLLM loaded in %d s, available memory %d MB", Int(Date().timeIntervalSince(t0)), Int(os_proc_available_memory() / 1_000_000))
                state = .ready
                return
            }
            let c = try await loadModelContainer(from: HubBridge(HubClient()), using: TransformersLoader(),
                                                 configuration: chosen.configuration) { progress in
                let f = progress.fractionCompleted
                Task { @MainActor in
                    if case .downloading = LLMService.shared.state { LLMService.shared.state = f >= 1 ? .loading : .downloading(f) }
                }
            }
            UserDefaults.standard.set(true, forKey: chosen.downloadedKey)
            guard chosen == choice else { return }
            container = c
            state = .ready
        } catch {
            NSLog("AiHeartLLM load failed: %@", "\(error)")
            state = .failed("Could not \(isDownloaded ? "load" : "download") the model. \(error.localizedDescription)")
        }
        #endif
    }

    /// The cloud switch, key or model changed: free the on-device model when cloud is on.
    func cloudChanged() async {
        container = nil
        onDemand = nil
        state = .notDownloaded
        NSLog("AiHeartLLM cloud %@", CloudSettings.isOn ? "on" : "off")
        if CloudSettings.isOn || isDownloaded { await prepare() }
    }

    /// Owner, 2026-11-04: with the cloud model chosen, remove the on-device models she will not need
    /// (Gemma 4 E2B and Qwen3 8B, about 8 GB). Qwen3-VL 4B stays: it reads photos, which never go to the
    /// cloud, and stands in offline. Runs once.
    func removeUnusedModelsOnce() {
        let flag = "cleanup.models.2026-11-04"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)
        if choice != .qwen {
            container = nil
            state = .notDownloaded
            choice = .qwen
            UserDefaults.standard.set(ModelChoice.qwen.rawValue, forKey: Self.choiceKey)
        }
        remove(.gemma)
        remove(.qwen8b)
        NSLog("AiHeartLLM removed unused on-device models")
    }

    /// Frees memory; the downloaded files stay.
    func unload() {
        container = nil
        onDemand = nil
        state = .notDownloaded
    }

    /// Switches model. The old one is freed from memory first, so only one is ever loaded; its
    /// files stay until she removes them. The new one downloads or loads when she asks (or when
    /// AiHeart next needs it, if its files are already here).
    func select(_ new: ModelChoice) async {
        guard new != choice else { return }
        UserDefaults.standard.set(true, forKey: "llm.choice.byHer")
        if let loading { await loading.value }
        unload()
        choice = new
        UserDefaults.standard.set(new.rawValue, forKey: Self.choiceKey)
        #if targetEnvironment(simulator)
        state = .unsupported
        #endif
        NSLog("AiHeartLLM model choice: %@", new.rawValue)
    }

    /// Deletes the downloaded weights of the chosen model.
    func remove() { remove(choice) }

    /// Deletes the downloaded weights of one model. If it is the one in use, it is unloaded first.
    func remove(_ c: ModelChoice) {
        if c == choice { unload() }
        try? FileManager.default.removeItem(at: c.localDirectory)
        let hub = URL.cachesDirectory.appendingPathComponent("huggingface/hub")
        if let items = try? FileManager.default.contentsOfDirectory(at: hub, includingPropertiesForKeys: nil) {
            for i in items where i.lastPathComponent.lowercased().contains(c.hubMatch) { try? FileManager.default.removeItem(at: i) }
        }
        UserDefaults.standard.set(false, forKey: c.downloadedKey)
    }
}

/// The on-device model for a request that must stay on the phone while the cloud is on (loaded on demand).
struct OnDeviceOnDemandModel: AiHeartCore.LanguageModel {
    var name: String { ModelChoice.qwen.displayName }
    var canSeeImages: Bool { true }
    func generate(_ request: GenerationRequest) async throws -> String {
        try await LLMService.shared.generateOnDemand(request)
    }
}

/// Adapter from the protocol to MLX's chat session. A fresh session per request, so it
/// carries no memory between requests.
struct OnDeviceModel: AiHeartCore.LanguageModel {
    let container: MLXLMCommon.ModelContainer
    let name: String
    var seesImages: Bool = true
    /// Qwen3 text models think out loud unless told not to; we want the answer only.
    var thinkingModel: Bool = false
    var vision: (@MainActor @Sendable (GenerationRequest) async throws -> String)? = nil
    var canSeeImages: Bool { seesImages }

    func generate(_ request: GenerationRequest) async throws -> String {
        // Text-only model, photo request: the photo model answers this one (vision is set only then).
        if request.image != nil, let vision { return try await vision(request) }
        let session = ChatSession(container, instructions: request.system,
                                  generateParameters: GenerateParameters(maxTokens: request.maxTokens, temperature: request.temperature),
                                  additionalContext: thinkingModel ? ["enable_thinking": false] : nil)
        let images: [UserInput.Image] = request.image.map { [.ciImage(CIImage(cgImage: $0))] } ?? []
        let t0 = Date()
        var out = try await session.respond(to: request.prompt, images: images, videos: [], audios: [])
        if let r = out.range(of: "</think>") { out = String(out[r.upperBound...]) }
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        // Timing and length only; never the text.
        NSLog("AiHeartLLM generated %d chars in %.1f s, image %d", out.count, Date().timeIntervalSince(t0), request.image != nil ? 1 : 0)
        return out
    }
}

/// My rules row and screen for the model.
struct LanguageModelRow: View {
    @State private var showing = false
    private var llm = LLMService.shared

    var body: some View {
        Button { showing = true } label: {
            RuleRow(title: "Language model", subtitle: CloudSettings.isOn ? "Cloud model for your writing. Photos stay on this phone. Never advises." : "On this phone only. Offers words; never advises.", trailing: trailing, chevron: true)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showing) { LanguageModelView() }
    }

    private var trailing: String {
        switch llm.state {
        case .ready: "On"
        case .downloading(let f): "\(Int(f * 100))%"
        case .loading: "Loading"
        case .unsupported: "Rules"
        case .failed: "Off"
        case .notDownloaded: llm.isDownloaded ? "On" : "Not set up"
        }
    }
}


struct LanguageModelView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var confirmRemove = false
    @State private var confirmRemoveOther = false
    private var llm = LLMService.shared

    private var switching: Bool {
        switch llm.state {
        case .downloading, .loading: true
        default: false
        }
    }

    var body: some View { bodyContent.keyboardHideButton() }

    @ViewBuilder private var bodyContent: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(llm.choice.displayName) runs on this phone. It offers words for a photo and helps you find words when you write. Every reply is checked before you see it: no advice, no labels, no reassurance, no quiet topics, and no numbers you did not give it.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                    CloudModelSection()
                    chooser
                    VStack(alignment: .leading, spacing: 10) {
                        status
                        actions
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                    Text("The download (about \(llm.approximateSize)) comes from Hugging Face, once. Use Wi-Fi and keep AiHeart open; it is faster to copy it from your Mac with the cable. After that it works offline. \(CloudSettings.isOn ? CloudSettings.scopeLine : "Nothing you write or photograph is sent anywhere.") iOS may clear it if storage runs low; you can download it again here.")
                        .font(.footnote).foregroundStyle(Palette.muted)
                }
                .padding(20)
            }
            .background(Palette.surface.ignoresSafeArea())
            .navigationTitle("Language model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Remove the model?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { llm.remove() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Frees about \(llm.approximateSize). The built-in rules take over until you download it again.") }
            .confirmationDialog("Remove \(llm.choice.other.displayName)'s files?", isPresented: $confirmRemoveOther, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { llm.remove(llm.choice.other) }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Frees about \(llm.choice.other.size). The model you are using is not touched.") }
        }
        .presentationDetents([.medium, .large])
    }

    /// Model picker: one at a time in memory. Switching frees the old one's memory.
    private var chooser: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model").font(.headline).foregroundStyle(Palette.ink)
            Picker("Model", selection: Binding(get: { llm.choice }, set: { pick($0) })) {
                ForEach(ModelChoice.allCases) { c in Text("\(c.pickerTitle), \(c.size)").tag(c) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .disabled(switching)
            Text("Switching downloads the new model and frees the old one's memory. Keep the old files until the new one works for you.")
                .font(.footnote).foregroundStyle(Palette.muted)
            if llm.isDownloaded(llm.choice.other) {
                Button("Remove the other model's files", role: .destructive) { confirmRemoveOther = true }
                    .frame(minHeight: 44)
                    .disabled(switching)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func pick(_ c: ModelChoice) {
        Task {
            await llm.select(c)
            let s = AiHeartStore.settings(in: context)
            s.modelChoice = c.rawValue
            s.updatedAt = .now
            try? context.save()
        }
    }

    @ViewBuilder private var status: some View {
        switch llm.state {
        case .unsupported:
            Text("Not available in the simulator. On your iPhone it downloads and runs here. Until then, built-in rules offer words from your own vocabulary.")
                .foregroundStyle(Palette.ink)
        case .downloading(let f):
            ProgressView(value: f) { Text("Downloading… \(Int(f * 100))%") }.tint(Palette.action)
        case .loading:
            ProgressView { Text("Loading into memory…") }
        case .ready:
            Label("Ready on this phone", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.ink)
        case .failed(let msg):
            Text(msg).foregroundStyle(Palette.ink)
        case .notDownloaded:
            Text(llm.isDownloaded ? "On. It loads when AiHeart opens and frees memory when you leave." : "Not downloaded yet.").foregroundStyle(Palette.ink)
        }
    }

    @ViewBuilder private var actions: some View {
        switch llm.state {
        case .unsupported, .downloading, .loading:
            EmptyView()
        case .ready:
            Button("Free memory") { llm.unload() }.foregroundStyle(Palette.onTint).frame(minHeight: 44)
            Button("Remove the model", role: .destructive) { confirmRemove = true }.frame(minHeight: 44)
        case .failed, .notDownloaded:
            Button(llm.isDownloaded ? "Load now" : "Download (\(llm.approximateSize))") { Task { await llm.prepare() } }
                .buttonStyle(PrimaryButtonStyle())
            if llm.isDownloaded {
                Button("Remove the model", role: .destructive) { confirmRemove = true }.frame(minHeight: 44)
            }
        }
    }
}

// Bridges to the Hugging Face hub and tokenizers, written out instead of using the
// package's macros so the project builds without trusting macro plug-ins.

struct HubBridge: MLXLMCommon.Downloader {
    private let upstream: HubClient
    init(_ upstream: HubClient) { self.upstream = upstream }

    func download(id: String, revision: String?, matching patterns: [String], useLatest: Bool,
                  progressHandler: @Sendable @escaping (Foundation.Progress) -> Void) async throws -> URL {
        guard let repoID = Repo.ID(rawValue: id) else {
            throw NSError(domain: "AiHeart", code: 2, userInfo: [NSLocalizedDescriptionKey: "Bad model id \(id)"])
        }
        return try await upstream.downloadSnapshot(of: repoID, revision: revision ?? "main", matching: patterns,
                                                   progressHandler: { @MainActor progress in progressHandler(progress) })
    }
}

struct TransformersLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TokenizerBridge(try await AutoTokenizer.from(modelFolder: directory))
    }
}

struct TokenizerBridge: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer
    init(_ upstream: any Tokenizers.Tokenizer) { self.upstream = upstream }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] { upstream.encode(text: text, addSpecialTokens: addSpecialTokens) }
    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String { upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens) }
    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }
    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
                           additionalContext: [String: any Sendable]?) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
