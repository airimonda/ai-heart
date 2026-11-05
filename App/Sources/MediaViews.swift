import AiHeartCore
import AuthenticationServices
import CryptoKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Spotify (M18, owner 2026-11-02). Display only by Spotify's terms (CLAUDE.md #6): what it
/// fetches never reaches statistics, the outlook or any model. Sign-in is PKCE with her own
/// Spotify app's client ID; the token stays in this phone's Keychain and is only sent to Spotify.
@MainActor @Observable
final class SpotifyService: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = SpotifyService()
    static let clientKey = "spotify.clientId"
    static let refreshKey = "spotify.refresh"
    static let redirect = "aiheart://spotify-callback"

    var clientId: String = UserDefaults.standard.string(forKey: SpotifyService.clientKey) ?? ""
    var connected: Bool { Keychain.get(Self.refreshKey) != nil }
    var error: String?
    var syncing = false
    private var lastFetch: Date?
    private var access: (token: String, until: Date)?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }

    func saveClientId(_ id: String) {
        clientId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(clientId, forKey: Self.clientKey)
    }

    func connect() async {
        error = nil
        guard !clientId.isEmpty else { error = "Add your Spotify client ID first."; return }
        let verifier = Self.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: clientId), .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirect), .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge), .init(name: "scope", value: "user-read-recently-played"),
        ]
        let code: String? = await withCheckedContinuation { cont in
            let s = ASWebAuthenticationSession(url: c.url!, callbackURLScheme: "aiheart") { url, _ in
                cont.resume(returning: url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "code" }?.value })
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false
            s.start()
        }
        guard let code else { error = "Spotify sign-in was not finished."; return }
        guard await token(["grant_type": "authorization_code", "code": code, "redirect_uri": Self.redirect, "code_verifier": verifier]) else { return }
        NSLog("AiHeartMedia spotify: connected")
    }

    func disconnect(_ context: ModelContext) {
        Keychain.set(nil, for: Self.refreshKey)
        access = nil
        MediaStore.deleteAll(.spotify, context: context)
    }

    /// Recently played, at most once an hour. Quiet on failure (docs/14).
    func refresh(_ context: ModelContext, force: Bool = false) async {
        guard connected, !syncing else { return }
        if !force, let l = lastFetch, Date().timeIntervalSince(l) < 3600 { return }
        syncing = true
        defer { syncing = false }
        if access == nil || access!.until < .now {
            guard let r = Keychain.get(Self.refreshKey), await token(["grant_type": "refresh_token", "refresh_token": r]) else { return }
        }
        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/recently-played?limit=50")!)
        req.setValue("Bearer \(access!.token)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let items = try? MediaImport.spotifyRecentlyPlayed(data) else {
            error = "Spotify did not answer just now."
            return
        }
        // Owner, 2026-11-02: live songs also feed the vibe line (CLAUDE.md #6).
        let added = MediaStore.add(items, source: .spotify, context: context, fromExport: true)
        MediaStore.markSpotifyVibeEligible(context)
        await fillGenres(context)
        await MediaVibeStore.shared.refresh(context, force: added > 0)
        lastFetch = .now
        error = nil
        NSLog("AiHeartMedia spotify: fetched=%d added=%d", items.count, added)
    }

    /// Artist genres for songs that have none yet, in batches of 50 artists.
    private func fillGenres(_ context: ModelContext) async {
        guard let token = access?.token else { return }
        let rows = ((try? context.fetch(FetchDescriptor<MediaItem>())) ?? []).filter { $0.source == .spotify && $0.genres == nil && $0.artistIds != nil }
        let ids = Array(Set(rows.flatMap { ($0.artistIds ?? "").split(separator: ",").map(String.init) })).prefix(200)
        guard !ids.isEmpty else { return }
        var genres: [String: [String]] = [:]
        for chunk in stride(from: 0, to: ids.count, by: 50).map({ Array(ids[$0..<min($0 + 50, ids.count)]) }) {
            var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/artists?ids=\(chunk.joined(separator: ","))")!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let artists = j["artists"] as? [[String: Any]] else { continue }
            for a in artists { if let id = a["id"] as? String { genres[id] = a["genres"] as? [String] ?? [] } }
        }
        var filled = 0
        for r in rows {
            let g = (r.artistIds ?? "").split(separator: ",").flatMap { genres[String($0)] ?? [] }
            guard (r.artistIds ?? "").split(separator: ",").contains(where: { genres[String($0)] != nil }) else { continue }
            r.genres = Array(NSOrderedSet(array: g)).compactMap { $0 as? String }.prefix(4).joined(separator: ", ")
            filled += 1
        }
        if filled > 0 { try? context.save() }
        NSLog("AiHeartMedia spotify genres: artists=%d rows=%d", genres.count, filled)
    }

    private func token(_ form: [String: String]) async -> Bool {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var f = form; f["client_id"] = clientId
        req.httpBody = f.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }.joined(separator: "&").data(using: .utf8)
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let t = j["access_token"] as? String else {
            error = "Spotify sign-in did not work. Check the client ID and the redirect address."
            return false
        }
        access = (t, Date().addingTimeInterval(Double(j["expires_in"] as? Int ?? 3600) - 60))
        if let r = j["refresh_token"] as? String { Keychain.set(r, for: Self.refreshKey) }
        return true
    }

    static func randomString(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<n).map { _ in chars.randomElement()! })
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

/// Saving and clearing media items, de-duplicated.
@MainActor
enum MediaStore {
    @discardableResult
    static func add(_ items: [MediaImport.Parsed], source: MediaSource, context: ModelContext, fromExport: Bool = false) -> Int {
        let existing = Set(((try? context.fetch(FetchDescriptor<MediaItem>())) ?? []).map(\.dedupeKey))
        var added = 0
        let device = UIDevice.current.identifierForVendor?.uuidString ?? ""
        for p in items {
            let key = MediaImport.dedupeKey(source, p)
            guard !existing.contains(key) else { continue }
            let m = MediaItem(source: source, title: p.title, creator: p.creator, startedAt: p.startedAt, durationSec: p.durationSec)
            m.dedupeKey = key
            m.deviceId = device
            if !p.artistIds.isEmpty { m.artistIds = p.artistIds.joined(separator: ",") }
            // Her own exported data may be read on the phone for the vibe line (CLAUDE.md #6).
            m.aiEligible = fromExport
            context.insert(m)
            added += 1
        }
        try? context.save()
        return added
    }

    /// Live Spotify rows fetched before the owner's 2026-11-02 choice become vibe-eligible too.
    static func markSpotifyVibeEligible(_ context: ModelContext) {
        var changed = false
        for m in (try? context.fetch(FetchDescriptor<MediaItem>())) ?? [] where m.source == .spotify && !m.aiEligible {
            m.aiEligible = true; changed = true
        }
        if changed { try? context.save() }
    }

    static func deleteAll(_ source: MediaSource, context: ModelContext) {
        for m in (try? context.fetch(FetchDescriptor<MediaItem>())) ?? [] where m.source == source { context.delete(m) }
        try? context.save()
    }
}

/// My rules > Sources: Spotify, Netflix, YouTube. Nothing here needs daily input.
struct SourcesView: View {
    @Environment(\.modelContext) private var context
    @Query private var media: [MediaItem]
    @State private var spotify = SpotifyService.shared
    @State private var idDraft = ""
    @State private var importing: MediaSource?
    @State private var note: String?
    @State private var lyricsTick = 0
    /// A Netflix download with several profiles waits here until she picks hers.
    @State private var pendingNetflix: (files: [Data], profiles: [String])?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Fetched or imported when you choose. Shown as this week's totals. None of it is used by the AI or the outlook.")
                    .font(.subheadline).foregroundStyle(Palette.muted)
                spotifyCard
                importCard(.netflix, how: """
                1. In Safari, open netflix.com/viewingactivity and sign in. Pick your profile if asked.
                2. Scroll to the bottom and tap Download all. The file goes to Files › Downloads.
                3. Tap Import file below and pick NetflixViewingHistory.csv.
                The full Netflix data download (a ZIP from Account › Security & privacy) works too.
                """)
                AppOpensSetupCard()
                importCard(.youtube, how: "On takeout.google.com: choose only YouTube › History, format JSON. Share the ZIP here, or watch-history.json.")
            }
            .padding(20)
        }
        .background(Palette.surface.ignoresSafeArea())
        .navigationTitle("Sources")
        .fileImporter(isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } }),
                      allowedContentTypes: [.zip, .commaSeparatedText, .json, .plainText, .data]) { r in
            guard let source = importing, case .success(let url) = r else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { note = "Could not read that file."; return }
            do {
                // A bare history file, or the data download ZIP with the right files found inside.
                let files = try MediaImport.historyFiles(source, data: data)
                if source == .netflix {
                    let profiles = files.flatMap(MediaImport.netflixProfiles).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                    if profiles.count > 1 {
                        pendingNetflix = (files, profiles)
                        return
                    }
                }
                finishImport(source, files: files, profile: nil)
            } catch {
                note = source == .netflix
                    ? "That isn't a Netflix viewing history. Use NetflixViewingHistory.csv from netflix.com/viewingactivity, or the Netflix data download ZIP."
                    : source == .spotify
                    ? "That isn't a Spotify listening history. Use the ZIP from Spotify's Download your data email."
                    : "That doesn't look like a \(source.label) history file."
            }
        }
        .confirmationDialog("Which profile is yours?", isPresented: Binding(get: { pendingNetflix != nil }, set: { if !$0 { pendingNetflix = nil } }),
                            titleVisibility: .visible) {
            ForEach(pendingNetflix?.profiles ?? [], id: \.self) { p in
                Button(p) {
                    if let files = pendingNetflix?.files { finishImport(.netflix, files: files, profile: p) }
                    pendingNetflix = nil
                }
            }
        } message: {
            Text("This download has more than one profile. Only the one you pick is imported.")
        }
        .alert("Import", isPresented: Binding(get: { note != nil }, set: { if !$0 { note = nil } })) {
            Button("OK") { note = nil }
        } message: {
            Text(note ?? "")
        }
        .onAppear { idDraft = spotify.clientId }
    }

    private func count(_ s: MediaSource) -> Int { media.filter { $0.source == s }.count }

    private func finishImport(_ source: MediaSource, files: [Data], profile: String?) {
        do {
            let items = try MediaImport.parse(source, files: files, netflixProfile: profile)
            let added = MediaStore.add(items, source: source, context: context, fromExport: true)
            note = items.isEmpty
                ? "\(source.label): the file was read, but it had nothing to add."
                : "\(source.label): \(added) new, \(items.count - added) already here."
        } catch {
            note = "That doesn't look like a \(source.label) history file."
        }
    }

    private var spotifyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Spotify").font(.headline).foregroundStyle(Palette.ink)
                Spacer()
                Text(spotify.connected ? "Connected · \(count(.spotify))" : "Not connected").font(.footnote).foregroundStyle(Palette.muted)
            }
            Text("Recently played, fetched about once an hour while the app is open. You chose to let these songs feed the week's vibe line, which Spotify's developer terms do not allow; Spotify could switch this connection off.")
                .font(.footnote).foregroundStyle(Palette.muted)
            if spotify.connected {
                HStack {
                    Button("Fetch now") { Task { await spotify.refresh(context, force: true) } }
                    Spacer()
                    Button("Disconnect", role: .destructive) { spotify.disconnect(context) }
                }
                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            } else {
                DisclosureGroup("One-time setup (about 5 minutes)") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Open developer.spotify.com/dashboard and sign in with your Spotify account.")
                        Text("2. Create app. Name: AiHeart. Redirect URI: aiheart://spotify-callback. API: Web API.")
                        Text("3. Copy its Client ID and paste it below.")
                        TextField("Client ID", text: $idDraft).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(10).background(Palette.segment, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .font(.footnote).foregroundStyle(Palette.ink).padding(.top, 6)
                }
                .font(.subheadline)
                Button("Connect Spotify") { spotify.saveClientId(idDraft); Task { await spotify.connect(); await spotify.refresh(context, force: true) } }
                    .buttonStyle(PrimaryButtonStyle()).disabled(idDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let e = spotify.error { Text(e).font(.footnote).foregroundStyle(Palette.ink) }
            Divider().overlay(Palette.line)
            DisclosureGroup("Import older history (optional)") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. In Safari, open spotify.com/account/privacy and sign in.")
                    Text("2. Under Download your data, tick Account data (ready in about 5 days) or Extended streaming history (all years, up to 30 days). Tap Request data, then confirm in the email.")
                    Text("3. When the second email says it is ready, open its link on this iPhone and download the ZIP. It goes to Files \u{203A} Downloads.")
                    Text("4. Tap Import file and pick the ZIP. No need to unzip it.")
                    Button("Import file") { importing = .spotify }
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                }
                .font(.footnote).foregroundStyle(Palette.ink).padding(.top, 6)
            }
            .font(.subheadline)
            Toggle(isOn: Binding(get: { LyricsLookup.enabled }, set: { LyricsLookup.enabled = $0; lyricsTick += 1 })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use lyrics for the vibe").font(.subheadline).foregroundStyle(Palette.ink)
                    Text("Looks up lyrics on lrclib.net for your Spotify songs. The site sees those titles and artists. Lyrics are read on your phone and never kept.")
                        .font(.caption).foregroundStyle(Palette.muted)
                }
            }
            .tint(Palette.action)
            .id(lyricsTick)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private func importCard(_ s: MediaSource, how: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(s.label).font(.headline).foregroundStyle(Palette.ink)
                Spacer()
                Text(count(s) == 0 ? "Nothing yet" : "\(count(s)) items").font(.footnote).foregroundStyle(Palette.muted)
            }
            Text(how).font(.footnote).foregroundStyle(Palette.muted)
            HStack {
                Button("Import file") { importing = s }
                Spacer()
                if count(s) > 0 { Button("Remove all", role: .destructive) { MediaStore.deleteAll(s, context: context) } }
            }
            .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).card()
    }
}

/// Media: this week, never a live counter (docs/14).
struct MediaView: View {
    @Query private var media: [MediaItem]
    @Query private var settingsRows: [AppSettings]
    @State private var weeksBack = 0

    var body: some View {
        let dayStart = settingsRows.first?.dayStartHour ?? 4
        let today = DayAnchor.day(for: .now, timeZone: .current, dayStartHour: dayStart).adding(days: -7 * weeksBack)
        let s = MediaWeek.summary(media.map { ($0.source, $0.title, $0.creator, $0.startedAt, $0.durationSec) },
                                  weekContaining: today, dayStartHour: dayStart, timeZone: .current, rolling: weeksBack == 0)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button { weeksBack += 1 } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Earlier week")
                    Spacer()
                    Text(weeksBack == 0 ? "Past 7 days" : "Week of \(s.weekStart.date(in: .current).formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.headline).foregroundStyle(Palette.ink)
                    Spacer()
                    Button { weeksBack = max(0, weeksBack - 1) } label: { Image(systemName: "chevron.right") }
                        .disabled(weeksBack == 0).accessibilityLabel("Later week")
                }
                .font(.title3).foregroundStyle(Palette.onTint).frame(minHeight: 44)
                Text(MediaWeek.describe(s)).font(.body).foregroundStyle(Palette.ink)
                MediaVibeCard(weekKey: s.weekStart.key)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hours by day").font(.headline).foregroundStyle(Palette.ink)
                    HStack(alignment: .bottom, spacing: 8) {
                        let peak = max(s.byDay.map(\.hours).max() ?? 1, 1)
                        ForEach(Array(s.byDay.enumerated()), id: \.offset) { _, d in
                            VStack(spacing: 4) {
                                Capsule().fill(Palette.pink).frame(height: max(4, CGFloat(d.hours / peak) * 110))
                                Text(d.day.date(in: .current).formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(Palette.muted)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 130, alignment: .bottom)
                }
                .padding(18).card()
                ForEach(MediaSource.allCases, id: \.self) { src in
                    if let top = s.top[src], !top.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(src.label).font(.headline).foregroundStyle(Palette.ink)
                                Spacer()
                                Text(String(format: "%.1f h", s.hoursBySource[src] ?? 0)).font(.subheadline).foregroundStyle(Palette.muted)
                            }
                            ForEach(Array(top.enumerated()), id: \.offset) { _, t in
                                HStack { Text(t.title).lineLimit(1).foregroundStyle(Palette.ink); Spacer(); Text("×\(t.count)").foregroundStyle(Palette.muted) }
                                    .font(.subheadline)
                            }
                        }
                        .padding(18).card()
                    }
                }
                AppOpensCard(weekStart: s.weekStart, dayStart: dayStart)
                if !s.replays.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("On repeat").font(.headline).foregroundStyle(Palette.ink)
                        ForEach(Array(s.replays.enumerated()), id: \.offset) { _, r in
                            HStack { Text(r.title).lineLimit(1).foregroundStyle(Palette.ink); Spacer(); Text("×\(r.count)").foregroundStyle(Palette.muted) }
                                .font(.subheadline)
                        }
                    }
                    .padding(18).card()
                }
                Text("Counts and times only. Shown for you to look at; not used by the AI or the outlook.").font(.caption).foregroundStyle(Palette.muted)
            }
            .padding(20)
        }
        .background(Palette.surface.ignoresSafeArea())
        .navigationTitle("Media")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink("Sources") { SourcesView() } } }
    }
}

/// Small card on Insights · Today, only when there is media this week.
struct MediaCard: View {
    @Query private var media: [MediaItem]
    @Query private var settingsRows: [AppSettings]

    var body: some View {
        let dayStart = settingsRows.first?.dayStartHour ?? 4
        let today = DayAnchor.day(for: .now, timeZone: .current, dayStartHour: dayStart)
        let s = MediaWeek.summary(media.map { ($0.source, $0.title, $0.creator, $0.startedAt, $0.durationSec) },
                                  weekContaining: today, dayStartHour: dayStart, timeZone: .current, rolling: true)
        let empty = s.itemsBySource.values.reduce(0, +) == 0
        if media.isEmpty {
            NavigationLink { SourcesView() } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Media").font(.headline).foregroundStyle(Palette.ink)
                        Text("Connect Spotify, or import Netflix and YouTube history, to see your week.").font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Palette.onTint)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink { MediaView() } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Media, past 7 days").font(.headline).foregroundStyle(Palette.ink)
                        if let v = MediaVibeStore.shared.current {
                            Text(v.tags.joined(separator: " · ")).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                        }
                        Text(empty ? "Nothing yet this week." : MediaWeek.describe(s)).font(.subheadline).foregroundStyle(Palette.muted).lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Palette.onTint)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
            }
            .buttonStyle(.plain)
        }
    }
}

extension MediaWeek {
    static func contains(_ d: Date, weekStart: AnchoredDay, dayStartHour: Int) -> Bool {
        let day = DayAnchor.day(for: d, timeZone: .current, dayStartHour: dayStartHour)
        return day >= weekStart && day < weekStart.adding(days: 7)
    }
}

/// The week's media vibe, made once per week (and again when new songs arrive), kept on
/// this phone. Read by Now, Insights and the Media screen.
@MainActor @Observable
final class MediaVibeStore {
    static let shared = MediaVibeStore()
    var current: MediaVibe?
    var working = false

    private static let latestKey = "media.vibe2.latest"

    /// The latest vibe (the last 7 days as of the day it was written).
    func load(weekKey: String = "") {
        guard let d = UserDefaults.standard.data(forKey: Self.latestKey), let v = try? JSONDecoder().decode(MediaVibe.self, from: d) else { return }
        current = v
    }

    /// Writes the vibe for this week if there is none, or if `force`.
    func refresh(_ context: ModelContext, force: Bool = false) async {
        let dayStart = ((try? context.fetch(FetchDescriptor<AppSettings>())) ?? []).first?.dayStartHour ?? 4
        let today = DayAnchor.day(for: .now, timeZone: .current, dayStartHour: dayStart)
        // A rolling 7 days, rewritten once a day, so Mondays are never empty.
        let from = today.adding(days: -6)
        load()
        guard force || current?.weekKey != today.key, !working else { return }
        let items = ((try? context.fetch(FetchDescriptor<MediaItem>())) ?? [])
            .filter { $0.aiEligible && MediaWeek.contains($0.startedAt, weekStart: from, dayStartHour: dayStart) }
        guard items.count >= 3 else { NSLog("AiHeartLLM media vibe: skipped, items=%d", items.count); return }
        let llm = LLMService.shared
        // CLAUDE.md #6 and Spotify's terms: media is read by the on-device model only, never the cloud.
        guard llm.isDownloaded, !CloudSettings.isOn else { return }
        working = true
        defer { working = false }
        if llm.state != .ready { await llm.prepare() }
        guard llm.canAnswer(.media) else { return }

        var counts: [String: (MediaItem, Int)] = [:]
        for i in items { let k = i.title.lowercased(); counts[k] = (counts[k]?.0 ?? i, (counts[k]?.1 ?? 0) + 1) }
        let ranked = counts.values.sorted { $0.1 > $1.1 }.prefix(40)
        let list = ranked.map { (m, n) in
            "- \(m.source.label): \(m.title)\(m.creator.map { " (\($0))" } ?? "")\((m.genres ?? "").isEmpty ? "" : " [genres: \(m.genres!)]")\(n > 1 ? " x\(n)" : "")"
        }.joined(separator: "\n")
        var lyricLines: [String] = []
        for (item, _) in ranked where item.source == .spotify {
            guard lyricLines.count < 6 else { break }
            if let l = await LyricsLookup.lyrics(title: item.title, artist: item.creator) { lyricLines.append("\(item.title): \(l)") }
        }
        let lyricsBlock = lyricLines.isEmpty ? "" : "\n\nLyric excerpts of the most played songs:\n" + lyricLines.joined(separator: "\n")
        let prompt = "Here is what someone watched and listened to this week:\n\(list)\(lyricsBlock)\n\nDescribe the overall theme and mood of this media: genres, energy, tone, what the songs are about. Describe the media only, never the person. No advice. Do not quote lyrics.\n\(MediaVibe.format)"
        let quiet = ((try? context.fetch(FetchDescriptor<QuietTopic>())) ?? []).map(\.term)
        for _ in 0..<3 {
            let req = GenerationRequest(system: "You describe the mood and themes of songs and shows in plain, warm words. Never judge, diagnose or advise.",
                                        prompt: prompt, maxTokens: 110, temperature: 0.4)
            guard let raw = try? await llm.model(for: .media).generate(req), let v = MediaVibe.parse(raw, weekKey: today.key) else { continue }
            let text = v.line + " " + v.tags.joined(separator: " ")
            guard OutputValidator.check(text, OutputPolicy(input: prompt, quietTopics: quiet, maxCharacters: 280)).isEmpty else { continue }
            current = v
            if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: Self.latestKey) }
            NSLog("AiHeartLLM media vibe: ok lyrics=%d", lyricLines.count)
            return
        }
        NSLog("AiHeartLLM media vibe: no valid answer, using genres")
        // Plain fallback from genres so the line is never missing.
        var g: [String: Int] = [:]
        for i in items { for x in (i.genres ?? "").split(separator: ",") { g[x.trimmingCharacters(in: .whitespaces).lowercased(), default: 0] += 1 } }
        let top = g.sorted { $0.value > $1.value }.map(\.key).filter { !$0.isEmpty }.prefix(3)
        guard top.count >= 1 else { return }
        let v = MediaVibe(tags: Array(top), valence: 0, energy: 0, line: "Mostly " + top.prefix(2).joined(separator: " and ") + ".", weekKey: today.key)
        current = v
        if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: Self.latestKey) }
    }
}

/// Soft gradient in the mood colors around the vibe's point, the visual for the week.
struct VibeGradient: View {
    let vibe: MediaVibe
    var body: some View {
        let a = MoodColor.color(valence: vibe.valence, arousal: vibe.energy)
        let b = MoodColor.color(valence: min(1, vibe.valence + 0.5), arousal: max(-1, vibe.energy - 0.5))
        let c = MoodColor.color(valence: max(-1, vibe.valence - 0.4), arousal: min(1, vibe.energy + 0.5))
        LinearGradient(colors: [Color(red: a.r, green: a.g, blue: a.b), Color(red: b.r, green: b.g, blue: b.b), Color(red: c.r, green: c.g, blue: c.b)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// The big vibe card on the Media screen.
struct MediaVibeCard: View {
    @Environment(\.modelContext) private var context
    @State private var store = MediaVibeStore.shared
    let weekKey: String

    var body: some View {
        Group {
            if let v = store.current {
                VStack(alignment: .leading, spacing: 12) {
                    Text("YOUR LAST 7 DAYS").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.black.opacity(0.55))
                    HStack(spacing: 8) {
                        ForEach(v.tags, id: \.self) { t in
                            Text(t).font(.headline).foregroundStyle(.black.opacity(0.8))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(.white.opacity(0.55), in: Capsule())
                        }
                    }
                    Text(v.line).font(.journal(.title3)).foregroundStyle(.black.opacity(0.85))
                    HStack {
                        Spacer()
                        Button { Task { await store.refresh(context, force: true) } } label: { Image(systemName: "arrow.clockwise") }
                            .foregroundStyle(.black.opacity(0.6)).accessibilityLabel("Read the vibe again")
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(VibeGradient(vibe: v))
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            } else if store.working {
                HStack { ProgressView(); Text("Reading this week's vibe…").foregroundStyle(Palette.muted) }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading).card()
            }
        }
        .task(id: weekKey) {
            store.load(weekKey: weekKey)
            await store.refresh(context)
        }
    }
}

/// The succinct version on Now: a color dot and three words. Tap to open Media.
struct NowVibeLine: View {
    /// A caption under the body card instead of a card of its own (owner, 2026-11-04: Now felt crowded).
    var plain = false
    @State private var store = MediaVibeStore.shared
    @Query private var settingsRows: [AppSettings]
    @Query private var media: [MediaItem]
    @Environment(\.modelContext) private var context

    var body: some View {
        let today = DayAnchor.day(for: .now, timeZone: .current, dayStartHour: settingsRows.first?.dayStartHour ?? 4)
        let week = BodyBalanceModel.monday(today).key
        Group {
            if store.current == nil, store.working {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading the mood of your music…").font(.subheadline).foregroundStyle(Palette.muted)
                    Spacer()
                }
                .padding(.horizontal, plain ? 6 : 16).frame(minHeight: plain ? 34 : 50).modifier(CardIf(on: !plain))
            } else if let v = store.current {
                NavigationLink { MediaView() } label: {
                    HStack(spacing: 10) {
                        VibeGradient(vibe: v).frame(width: 26, height: 26).clipShape(Circle())
                        Text("Lately:").font(.subheadline).foregroundStyle(Palette.muted)
                        Text(v.tags.joined(separator: " · ")).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Palette.muted)
                    }
                    .padding(.horizontal, plain ? 6 : 16).frame(minHeight: plain ? 34 : 50)
                    .modifier(CardIf(on: !plain))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("This week's media sounds \(v.tags.joined(separator: ", "))")
            }
        }
        .onAppear { store.load(weekKey: week) }
        .task(id: media.count) {
            // Make (or refresh) it from Now too, once the model is ready.
            try? await Task.sleep(for: .seconds(6))
            await store.refresh(context)
        }
    }
}

/// Lyrics for the vibe line (owner choice B, 2026-11-02; CLAUDE.md #1 exception). Sends only
/// title and artist to lrclib.net, keeps lyrics in memory for one read, never stores them.
@MainActor
enum LyricsLookup {
    static let enabledKey = "media.lyrics"
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static func lyrics(title: String, artist: String?) async -> String? {
        guard enabled, let artist, !artist.isEmpty else { return nil }
        var c = URLComponents(string: "https://lrclib.net/api/get")!
        c.queryItems = [.init(name: "track_name", value: title), .init(name: "artist_name", value: artist)]
        guard let url = c.url else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("AiHeart personal app", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = j["plainLyrics"] as? String, !text.isEmpty else { return nil }
        // A short excerpt is enough for the mood, and keeps the prompt small.
        return String(text.replacingOccurrences(of: "\n", with: " / ").prefix(280))
    }
}


/// `.card()` only when asked.
struct CardIf: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.card() } else { content }
    }
}
