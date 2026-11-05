import AiHeartCore
import Photos
import SwiftUI
import UIKit

/// Today's photos from her library, offered on Now to write about (screen 02, "photos from
/// today"). Only today's: nothing older resurfaces (CLAUDE.md #5). Screenshots and videos
/// are left out. A chosen photo is copied into the app with its metadata stripped.
@MainActor @Observable
final class TodayPhotos {
    static let shared = TodayPhotos()

    var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    var assets: [PHAsset] = []
    private let manager = PHCachingImageManager()

    var canRead: Bool { status == .authorized || status == .limited }

    func requestAccess() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        reload()
    }

    /// Photos taken since the start of her anchored day.
    func reload(dayStartHour: Int = 4) {
        guard canRead else { assets = []; return }
        let cal = Calendar.current
        var start = cal.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: .now) ?? .now
        if start > .now { start = cal.date(byAdding: .day, value: -1, to: start) ?? start }
        let opts = PHFetchOptions()
        // Photos does not support bitwise tests in fetch predicates; screenshots are dropped below.
        opts.predicate = NSPredicate(format: "creationDate >= %@", start as NSDate)
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: opts)
        var out: [PHAsset] = []
        result.enumerateObjects { a, _, _ in
            if !a.mediaSubtypes.contains(.photoScreenshot) { out.append(a) }
        }
        assets = out
    }

    func thumbnail(_ asset: PHAsset, side: CGFloat) async -> UIImage? {
        await withCheckedContinuation { cont in
            let o = PHImageRequestOptions()
            o.deliveryMode = .highQualityFormat
            o.isNetworkAccessAllowed = true
            o.resizeMode = .fast
            manager.requestImage(for: asset, targetSize: CGSize(width: side * 3, height: side * 3), contentMode: .aspectFill, options: o) { img, _ in
                cont.resume(returning: img)
            }
        }
    }

    /// Full image, re-encoded so location and other metadata are dropped.
    func prepared(_ asset: PHAsset) async -> (photo: Data, thumb: Data)? {
        NSLog("AiHeartPhoto requesting today's photo")
        let data: Data? = await withCheckedContinuation { cont in
            let o = PHImageRequestOptions()
            o.isNetworkAccessAllowed = true
            o.version = .current
            manager.requestImageDataAndOrientation(for: asset, options: o) { d, _, _, _ in cont.resume(returning: d) }
        }
        NSLog("AiHeartPhoto got %d bytes", data?.count ?? -1)
        return data.flatMap(ImageTools.prepare)
    }

    // Which photos she already used or skipped today, so they are not offered again.
    private static func key(_ name: String) -> String { "todayPhotos.\(name).\(Int(Calendar.current.startOfDay(for: .now).timeIntervalSince1970))" }

    var skippedToday: Bool {
        get { UserDefaults.standard.bool(forKey: Self.key("skipped")) }
        set { UserDefaults.standard.set(newValue, forKey: Self.key("skipped")) }
    }

    var usedIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.key("used")) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.key("used")) }
    }

    /// iOS sheet for adding more photos to a limited selection.
    static func chooseMore() {
        guard let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else { return }
        var top = root
        while let p = top.presentedViewController { top = p }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top) { _ in
            Task { @MainActor in TodayPhotos.shared.reload() }
        }
    }

    /// Photos still on offer today.
    var available: [PHAsset] {
        guard canRead, !skippedToday else { return [] }
        let used = usedIDs
        return assets.filter { !used.contains($0.localIdentifier) }
    }
}

/// The card on Now: asks for access once, then shows today's photos. When there are none
/// (or she skipped them), Now shows the written suggestion instead.
struct TodayPhotosCard: View {
    let onPick: (PHAsset) -> Void
    /// Opens the system photo picker: her whole library, any date, chosen by her.
    var browse: () -> Void = {}
    var photos = TodayPhotos.shared
    @State private var refresh = 0

    var body: some View {
        let available = { _ = refresh; return photos.available }()
        Group {
            if photos.status == .notDetermined {
                card {
                    HStack(spacing: 14) {
                        CircleIcon(systemName: "photo.on.rectangle")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Photos from today").font(.headline).foregroundStyle(Palette.ink)
                            Text("AiHeart can show today's photos to write about. Only today's, never older ones.")
                                .font(.subheadline).foregroundStyle(Palette.muted)
                        }
                    }
                    Button("Show today's photos") { Task { await photos.requestAccess() } }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.onTint).frame(minHeight: 44)
                }
            } else if !available.isEmpty {
                card {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(available.count == 1 ? "1 photo from today" : "\(available.count) photos from today")
                                .font(.headline).foregroundStyle(Palette.ink)
                            Text("Pick one to write about. Skip them all if you like.")
                                .font(.subheadline).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Button("Skip") { photos.skippedToday = true; refresh += 1 }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.onTint).frame(minWidth: 44, minHeight: 44)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(available, id: \.localIdentifier) { a in
                                Button {
                                    photos.usedIDs.insert(a.localIdentifier)
                                    refresh += 1
                                    onPick(a)
                                } label: { Thumb(asset: a, side: 84) }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Photo from \(a.creationDate?.formatted(date: .omitted, time: .shortened) ?? "today")")
                            }
                        }
                    }
                    footer
                }
            }
        }
    }

    /// Limited access note, and the way into the whole library.
    @ViewBuilder private var footer: some View {
        if photos.status == .limited {
            HStack {
                Text("AiHeart sees only the photos you allowed.").font(.footnote).foregroundStyle(Palette.muted)
                Spacer()
                Button("Choose more photos") { TodayPhotos.chooseMore() }
                    .font(.footnote.weight(.semibold)).foregroundStyle(Palette.onTint).frame(minHeight: 44)
            }
        }
        Button(action: browse) {
            Label("Browse your photos", systemImage: "photo.on.rectangle.angled")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.onTint).frame(minHeight: 44)
        }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
    }
}

struct Thumb: View {
    let asset: PHAsset
    let side: CGFloat
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Palette.tint1
            if let image { Image(uiImage: image).resizable().scaledToFill() }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: asset.localIdentifier) { image = await TodayPhotos.shared.thumbnail(asset, side: side) }
    }
}
