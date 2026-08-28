#if os(iOS)
import SwiftUI

/// iOS 15 的精选浏览页。保留 0.3.7 的数据模型与搜索/播放行为，
/// 但使用 iOS 15 可用的目的地式 NavigationLink。
struct IOS15ExploreView: View {
    @StateObject private var model = ExploreViewModel.shared
    @EnvironmentObject private var player: PlayerService

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                categoryChips
                    .padding(.top, 8)

                if model.selectedCategory == "排行榜" {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(model.toplists) { toplist in
                            NavigationLink(destination: PlaylistDetailView(playlistID: toplist.id)) {
                                IOS15ExploreCard(
                                    coverURL: toplist.coverImgUrl?.resizedImageURL(384),
                                    title: toplist.name,
                                    subtitle: toplist.updateFrequency
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.Layout.contentInset)
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(Array(model.playlists.enumerated()), id: \.element.id) { index, playlist in
                            NavigationLink(destination: PlaylistDetailView(playlistID: playlist.id)) {
                                IOS15ExploreCard(
                                    coverURL: playlist.coverURL?.resizedImageURL(384),
                                    title: playlist.name,
                                    playCount: playlist.playCount
                                ) {
                                    playPlaylist(playlist.id)
                                }
                            }
                            .buttonStyle(.plain)
                            .staggeredAppearance(index: index % 10, id: "ios15-explore-\(playlist.id)")
                        }
                    }
                    .padding(.horizontal, Theme.Layout.contentInset)

                    if model.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    } else if model.hasMore {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                Task { await model.loadMore() }
                            }
                    }
                }

                PlayerClearanceSpacer()
            }
        }
        .navigationBarTitle("精选", displayMode: .large)
        .task {
            if model.playlists.isEmpty, model.toplists.isEmpty {
                await model.loadMore()
            }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Color.clear.frame(width: Theme.Layout.contentInset - 12, height: 1)
                ForEach(ExploreViewModel.categories, id: \.self) { category in
                    Button {
                        IOS15SelectionFeedback.perform()
                        model.select(category)
                    } label: {
                        Text(LocalizedStringKey(category))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(model.selectedCategory == category ? .white : .primary.opacity(0.76))
                            .padding(.horizontal, 15)
                            .frame(height: 38)
                            .background(
                                model.selectedCategory == category
                                    ? AnyShapeStyle(Theme.accent)
                                    : AnyShapeStyle(.ultraThinMaterial),
                                in: Capsule(style: .continuous)
                            )
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(.white.opacity(model.selectedCategory == category ? 0.24 : 0.46), lineWidth: 0.6)
                            }
                    }
                    .buttonStyle(.pressable)
                    .accessibilityAddTraits(model.selectedCategory == category ? .isSelected : [])
                }
                Color.clear.frame(width: Theme.Layout.contentInset - 12, height: 1)
            }
            .padding(.vertical, 2)
        }
    }

    private func playPlaylist(_ id: Int) {
        Task {
            guard let detail = try? await NeteaseAPI.playlistDetail(id: id) else { return }
            var tracks = detail.playlist.tracks
            if tracks.isEmpty {
                let ids = detail.playlist.trackIds.map(\.id)
                tracks = (try? await NeteaseAPI.songDetails(ids: Array(ids.prefix(500))))?.songs ?? []
            }
            player.play(
                tracks: tracks,
                source: .playlist(id),
                context: .playlist(id: id, name: detail.playlist.name)
            )
        }
    }
}

private struct IOS15ExploreCard: View {
    let coverURL: URL?
    let title: String
    var subtitle: String? = nil
    var playCount: Int = 0
    var onPlay: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                CachedAsyncImage(url: coverURL)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                            .strokeBorder(.white.opacity(0.28), lineWidth: 0.7)
                    }

                if playCount > 0 {
                    PlayCountBadge(count: playCount)
                        .padding(7)
                }
            }
            .contentShape(Rectangle())
            .overlay(alignment: .bottomTrailing) {
                if let onPlay {
                    Button(action: onPlay) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Theme.accent, in: Circle())
                            .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
                    }
                    .buttonStyle(.pressable)
                    .padding(8)
                }
            }

            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 与 0.3.5 参考图对应的卡片式“我的”页面。目的地式链接由 NavigationView
/// 原生管理，因此 iOS 15 继续支持系统左缘滑动返回。
struct IOS15CardLibraryView: View {
    @Binding var showLogin: Bool
    @Binding var showSettings: Bool
    @EnvironmentObject private var account: AccountStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                profileCard
                musicSection

                if account.hasAuthCookie {
                    playlistSections
                }

                PlayerClearanceSpacer()
            }
            .padding(.horizontal, Theme.Layout.contentInset)
            .padding(.top, 20)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationBarHidden(true)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("我的")
                .font(.system(size: 42, weight: .bold))
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: 0.6))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("设置")
        }
    }

    private var profileCard: some View {
        Button {
            if !account.hasAuthCookie { showLogin = true }
        } label: {
            HStack(spacing: 14) {
                if let profile = account.profile {
                    CachedAsyncImage(url: profile.avatarUrl?.resizedImageURL(128), animated: false)
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.nickname)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("已登录网易云音乐")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(Theme.accent.opacity(0.26))
                    Text("登录网易云音乐")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.65))
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.54), lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(account.hasAuthCookie ? "账户资料" : "登录网易云音乐")
    }

    private var musicSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("我的音乐")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 12)

            VStack(spacing: 0) {
                if let liked = account.likedSongsPlaylist {
                    NavigationLink(destination: PlaylistDetailView(playlistID: liked.id, isLikedList: true)) {
                        IOS15LibraryRow(icon: "heart.fill", title: "我喜欢的音乐", tint: Theme.accent)
                    }
                } else {
                    Button { showLogin = true } label: {
                        IOS15LibraryRow(icon: "heart.fill", title: "我喜欢的音乐", tint: Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
                Divider().padding(.leading, 22)
                NavigationLink(destination: DailySongsView()) {
                    IOS15LibraryRow(icon: "calendar", title: "每日推荐", tint: .blue)
                }
                Divider().padding(.leading, 22)
                NavigationLink(destination: RecentsView()) {
                    IOS15LibraryRow(icon: "clock.fill", title: "最近播放", tint: .blue)
                }
                Divider().padding(.leading, 22)
                NavigationLink(destination: CollectionsView()) {
                    IOS15LibraryRow(icon: "star.fill", title: "我的收藏", tint: .blue)
                }
                Divider().padding(.leading, 22)
                NavigationLink(destination: CloudView()) {
                    IOS15LibraryRow(icon: "icloud.fill", title: "音乐云盘", tint: .blue)
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.50), lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.05), radius: 9, y: 3)
        }
    }

    @ViewBuilder
    private var playlistSections: some View {
        if !account.createdPlaylists.isEmpty {
            IOS15PlaylistShelf(title: "创建的歌单", playlists: account.createdPlaylists)
        }
        if !account.subscribedPlaylists.isEmpty {
            IOS15PlaylistShelf(title: "收藏的歌单", playlists: account.subscribedPlaylists)
        }
    }
}

private struct IOS15LibraryRow: View {
    let icon: String
    let title: LocalizedStringKey
    let tint: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28)
            Text(title)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.62))
        }
        .frame(minHeight: 64)
        .padding(.horizontal, 18)
        .contentShape(Rectangle())
    }
}

private struct IOS15PlaylistShelf: View {
    let title: LocalizedStringKey
    let playlists: [PlaylistSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
            VStack(spacing: 0) {
                ForEach(playlists) { playlist in
                    NavigationLink(destination: PlaylistDetailView(playlistID: playlist.id)) {
                        HStack(spacing: 12) {
                            CachedAsyncImage(url: playlist.coverURL?.resizedImageURL(80), animated: false)
                                .frame(width: 42, height: 42)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(playlist.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("\(playlist.trackCount) 首")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary.opacity(0.55))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
#endif
