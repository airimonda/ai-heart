import AiHeartCore
import Foundation
import SwiftUI

/// Cloud model through OpenRouter (owner, 2026-11-04: the on-device 8B misread context and ran the
/// phone out of memory; she chose the cloud and asked that personal identifiers be removed first).
/// See docs/20. Every request is redacted on the phone (PIIRedactor), sent with
/// data_collection "deny", and the reply is mapped back on the phone. Photos are never sent.
/// All existing checks still run on the reply, and self-harm keyword checks run on the phone first.
enum CloudSettings {
    static let keyAccount = "openrouter.apiKey"
    static let modelKey = "cloud.model"
    static let onKey = "cloud.on"

    static var apiKey: String? { Keychain.get(keyAccount) }
    static var modelID: String { UserDefaults.standard.string(forKey: modelKey) ?? "" }
    static var wanted: Bool { UserDefaults.standard.bool(forKey: onKey) }
    static var isOn: Bool { wanted && !(apiKey ?? "").isEmpty && !modelID.isEmpty }

    /// What the cloud model is used for, and what it never sees, for any screen that says where text goes.
    static let scopeLine = "With the cloud model on, the text of your notes, talks, outlook questions, word help, checks and About me goes to it. Photos, media and anything that mentions hurting yourself never do."
}

struct OpenRouterModel: AiHeartCore.LanguageModel {
    let modelID: String
    let apiKey: String
    var name: String { modelID }
    /// Photos stay on the phone.
    var canSeeImages: Bool { false }

    struct Reply: Decodable {
        struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message }
        let choices: [Choice]
    }

    func generate(_ request: GenerationRequest) async throws -> String {
        guard request.image == nil else { throw CancellationError() }
        let redacted = PIIRedactor.redact([request.system, request.prompt])
        let body: [String: Any] = [
            "model": modelID,
            "messages": [["role": "system", "content": redacted.texts[0]], ["role": "user", "content": redacted.texts[1]]],
            // Reasoning models spend tokens thinking before they answer. With the small caps the on-device
            // pipeline uses, the thinking used the whole budget and the answer came back empty (owner,
            // 2026-11-04: Talk it through showed only its fixed line). Low effort, thinking left out of the
            // reply, and room for both.
            "max_tokens": max(request.maxTokens * 4, 1200),
            "reasoning": ["effort": "low", "exclude": true],
            "temperature": Double(request.temperature),
            // Only providers that do not store or train on prompts.
            "provider": ["data_collection": "deny"],
        ]
        var req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("AiHeart", forHTTPHeaderField: "X-Title")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let t0 = Date()
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            NSLog("AiHeartLLM cloud error %d", (response as? HTTPURLResponse)?.statusCode ?? -1)
            throw URLError(.badServerResponse)
        }
        let content = Self.content(from: data)
        if content.isEmpty {
            // Why it is empty, never the text: finish reason and token counts.
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let choice = (obj?["choices"] as? [[String: Any]])?.first
            let usage = obj?["usage"] as? [String: Any]
            let reasoning = (usage?["completion_tokens_details"] as? [String: Any])?["reasoning_tokens"] ?? "-"
            NSLog("AiHeartLLM cloud empty: finish=%@ completion=%@ reasoning=%@", "\(choice?["finish_reason"] ?? "-")",
                  "\(usage?["completion_tokens"] ?? "-")", "\(reasoning)")
        }
        // Timing and length only; never the text.
        NSLog("AiHeartLLM cloud %d chars in %.1f s, %d identifiers redacted", content.count, Date().timeIntervalSince(t0), redacted.map.count)
        return PIIRedaction(text: "", map: redacted.map).restore(content).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The answer text, whether the API returns a string or a list of parts.
    static func content(from data: Data) -> String {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let message = ((obj["choices"] as? [[String: Any]])?.first)?["message"] as? [String: Any] else { return "" }
        if let text = message["content"] as? String { return text }
        if let parts = message["content"] as? [[String: Any]] {
            return parts.compactMap { $0["text"] as? String }.joined()
        }
        return ""
    }

    struct ModelList: Decodable { struct M: Decodable { let id: String; let name: String?; let created: Double? }; let data: [M] }

    /// OpenRouter's live model list. Public; sends nothing about her.
    static func models() async throws -> [ModelList.M] {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "https://openrouter.ai/api/v1/models")!)
        return try JSONDecoder().decode(ModelList.self, from: data).data
    }

    /// Default: the newest Claude Sonnet on the list, else the newest Claude, else the first model.
    static func defaultModel(_ list: [ModelList.M]) -> String? {
        let newest = list.sorted { ($0.created ?? 0) > ($1.created ?? 0) }
        return (newest.first { $0.id.hasPrefix("anthropic/") && $0.id.contains("sonnet") }
            ?? newest.first { $0.id.hasPrefix("anthropic/") } ?? newest.first)?.id
    }
}

/// Cloud section of the Language model screen.
struct CloudModelSection: View {
    @State private var on = CloudSettings.wanted
    @State private var key = ""
    @State private var hasKey = !(CloudSettings.apiKey ?? "").isEmpty
    @State private var model = CloudSettings.modelID
    @State private var list: [String] = []
    @State private var status: String?
    @State private var busy = false
    private var llm = LLMService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Use a cloud model (OpenRouter)", isOn: $on)
                .font(.headline).tint(Palette.action)
                .onChange(of: on) { _, v in UserDefaults.standard.set(v, forKey: CloudSettings.onKey); Task { await llm.cloudChanged() } }
            Text("Your writing is sent to OpenRouter and the model's company to write notes, find words, read your outlook, check entries, listen and talk things through. Text that mentions hurting yourself is never sent: it stays on this phone. Before sending, names, places, organisations, emails, phone numbers, links and long numbers are replaced on your phone. Photos, media and captions are never sent. Only providers that do not store or train on your text are used.")
                .font(.footnote).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            if on {
                if hasKey {
                    HStack {
                        Text("API key saved on this phone").font(.subheadline).foregroundStyle(Palette.ink)
                        Spacer()
                        Button("Remove") { Keychain.set(nil, for: CloudSettings.keyAccount); hasKey = false; Task { await llm.cloudChanged() } }
                            .foregroundStyle(Palette.onTint)
                    }
                } else {
                    SecureField("OpenRouter API key", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(10).background(Palette.segment, in: RoundedRectangle(cornerRadius: 10))
                    Button("Save key") {
                        Keychain.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: CloudSettings.keyAccount)
                        key = ""; hasKey = true
                        Task { await loadList(); await llm.cloudChanged() }
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty).foregroundStyle(Palette.onTint)
                }
                if !list.isEmpty {
                    Picker("Model", selection: $model) { ForEach(list, id: \.self) { Text($0).tag($0) } }
                        .onChange(of: model) { _, v in UserDefaults.standard.set(v, forKey: CloudSettings.modelKey); Task { await llm.cloudChanged() } }
                } else {
                    Text(model.isEmpty ? "No model chosen yet." : "Model: \(model)").font(.subheadline).foregroundStyle(Palette.ink)
                    Button("Choose a model") { Task { await loadList() } }.foregroundStyle(Palette.onTint)
                }
                Button(busy ? "Testing…" : "Test the connection") { Task { await test() } }
                    .disabled(busy || !CloudSettings.isOn).foregroundStyle(Palette.onTint)
                if let status { Text(status).font(.footnote).foregroundStyle(Palette.muted) }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func loadList() async {
        guard let all = try? await OpenRouterModel.models() else { status = "Could not load the model list. Check the connection."; return }
        let sorted = all.sorted { ($0.created ?? 0) > ($1.created ?? 0) }
        list = sorted.map(\.id)
        if model.isEmpty, let d = OpenRouterModel.defaultModel(all) {
            model = d
            UserDefaults.standard.set(d, forKey: CloudSettings.modelKey)
            await llm.cloudChanged()
        }
    }

    private func test() async {
        busy = true
        defer { busy = false }
        guard let k = CloudSettings.apiKey else { return }
        let m = OpenRouterModel(modelID: CloudSettings.modelID, apiKey: k)
        do {
            let out = try await m.generate(GenerationRequest(system: "Answer with one word.", prompt: "Say ok.", maxTokens: 5, temperature: 0))
            status = out.isEmpty ? "Connected, but the reply was empty." : "Connected to \(m.modelID)."
        } catch {
            status = "Could not reach the model. Check the key and the connection."
        }
    }
}
