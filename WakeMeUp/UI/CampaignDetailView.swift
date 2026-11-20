import AVKit
import SwiftUI
import UIKit

enum CampaignImageCache {
    static let cache: URLCache = {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("wakito-campaign-images", isDirectory: true)
        return URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 64 * 1024 * 1024, directory: directory)
    }()

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: configuration)
    }()
}

struct CachedRemoteImage: View {
    var url: URL
    var fit: ContentMode = .fill
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fit)
            } else {
                ZStack {
                    Color.secondary.opacity(0.15)
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        if let cached = CampaignImageCache.cache.cachedResponse(for: request),
           let cachedImage = UIImage(data: cached.data) {
            image = cachedImage
            return
        }
        do {
            let (data, response) = try await CampaignImageCache.session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let loaded = UIImage(data: data) else {
                return
            }
            let stored = CachedURLResponse(response: response, data: data, storagePolicy: .allowed)
            CampaignImageCache.cache.storeCachedResponse(stored, for: request)
            image = loaded
        } catch {
            return
        }
    }
}

struct CampaignPhotoStrip: View {
    var photos: [CampaignPhoto]
    var title: LocalizedStringKey?
    @State private var pager: CampaignPager?

    var body: some View {
        if !photos.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let title {
                    Text(title)
                        .font(.headline)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                            if let url = photo.link {
                                Button {
                                    pager = CampaignPager(photos: photos, index: index)
                                } label: {
                                    CachedRemoteImage(url: url)
                                        .frame(width: 148, height: 110)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(caption(photo) ?? String(localized: "achievements.photos"))
                            }
                        }
                    }
                }
            }
            .fullScreenCover(item: $pager) { pager in
                CampaignPhotoPager(photos: pager.photos, index: pager.index)
            }
        }
    }

    private func caption(_ photo: CampaignPhoto) -> String? {
        photo.visibleCaption?.resolved(languageCode: CampaignLanguage.current)
    }
}

struct CampaignPager: Identifiable {
    var photos: [CampaignPhoto]
    var index: Int
    var id: String { "\(index)-\(photos.count)" }
}

struct CampaignPhotoPager: View {
    var photos: [CampaignPhoto]
    var index: Int
    @Environment(\.dismiss) private var dismiss
    @State private var page: Int

    init(photos: [CampaignPhoto], index: Int) {
        self.photos = photos
        self.index = index
        _page = State(initialValue: index)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $page) {
                ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                    ZoomablePhotoPage(photo: photo)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.45))
            }
            .padding()
            .accessibilityLabel(Text("achievements.close"))
        }
    }
}

private struct ZoomablePhotoPage: View {
    var photo: CampaignPhoto
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: 12) {
            Group {
                if let url = photo.link {
                    CachedRemoteImage(url: url, fit: .fit)
                }
            }
            .scaleEffect(scale)
            .offset(offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(magnify)
            .simultaneousGesture(drag, including: scale > 1.01 ? .all : .none)
            .onTapGesture(count: 2) { toggleZoom() }
            if let caption = photo.visibleCaption?.resolved(languageCode: CampaignLanguage.current) {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
            }
        }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(4, max(1, baseScale * value.magnification))
            }
            .onEnded { _ in
                baseScale = scale
                if scale <= 1.01 {
                    scale = 1
                    baseScale = 1
                    offset = .zero
                    baseOffset = .zero
                }
            }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1.01 else { return }
                offset = CGSize(
                    width: baseOffset.width + value.translation.width,
                    height: baseOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                baseOffset = offset
            }
    }

    private func toggleZoom() {
        withAnimation(.spring(duration: 0.25)) {
            if scale > 1.01 {
                scale = 1
                baseScale = 1
                offset = .zero
                baseOffset = .zero
            } else {
                scale = 2.5
                baseScale = 2.5
            }
        }
    }
}

struct CampaignUpdatesSection: View {
    var updates: [CampaignUpdate]

    var body: some View {
        if !updates.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("achievements.updates")
                    .font(.headline)
                ForEach(Array(updates.enumerated()), id: \.offset) { _, update in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(CampaignLanguage.day(update.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let title = update.visibleTitle?.resolved(languageCode: CampaignLanguage.current) {
                            Text(title)
                                .font(.headline)
                        }
                        Text(update.text.resolved(languageCode: CampaignLanguage.current))
                            .font(.subheadline)
                        CampaignPhotoStrip(photos: update.gallery, title: nil)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}

struct CampaignThanksSection: View {
    var notes: [CampaignThanks]
    @State private var pager: CampaignPager?
    @State private var video: IdentifiedURL?

    var body: some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("achievements.thanks")
                    .font(.headline)
                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                    VStack(alignment: .leading, spacing: 6) {
                        if note.author != nil || note.day != nil {
                            Text([note.author, note.day.map(CampaignLanguage.day)].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(note.text.resolved(languageCode: CampaignLanguage.current))
                            .font(.subheadline)
                        if let photo = note.photo {
                            Button {
                                pager = CampaignPager(
                                    photos: [CampaignPhoto(url: photo.absoluteString, caption: nil)],
                                    index: 0
                                )
                            } label: {
                                CachedRemoteImage(url: photo)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 160)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                        if let videoURL = note.video {
                            Button {
                                video = IdentifiedURL(url: videoURL)
                            } label: {
                                Label("achievements.watch", systemImage: "play.circle.fill")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .fullScreenCover(item: $pager) { pager in
                CampaignPhotoPager(photos: pager.photos, index: pager.index)
            }
            .sheet(item: $video) { item in
                NavigationStack {
                    VideoPlayer(player: AVPlayer(url: item.url))
                        .ignoresSafeArea(edges: .bottom)
                        .navigationTitle("achievements.watch")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("achievements.close") { video = nil }
                            }
                        }
                }
            }
        }
    }
}

struct CampaignDetailView: View {
    var campaign: AchievementCampaign

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(campaign.who.resolved(languageCode: CampaignLanguage.current))
                    .foregroundStyle(.secondary)
                ForEach(Array(campaign.story(languageCode: CampaignLanguage.current).enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                }
                if let link = SecureLink.url(from: campaign.linkURL) {
                    Link("achievements.more", destination: link)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .navigationTitle(campaign.title.resolved(languageCode: CampaignLanguage.current))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("campaign-detail")
    }
}

private struct IdentifiedURL: Identifiable {
    var url: URL
    var id: String { url.absoluteString }
}

enum CampaignLanguage {
    static var current: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    static func day(_ raw: String) -> String {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: raw) else { return raw }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
