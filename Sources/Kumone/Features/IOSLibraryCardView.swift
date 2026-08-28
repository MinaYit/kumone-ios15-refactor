#if os(iOS)
import SwiftUI

@available(iOS 16.0, *)
struct IOSLibraryCardView: View {
    @Binding var showLogin: Bool
    @EnvironmentObject private var account: AccountStore
    @State private var showSettings = false
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
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
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .navigationTitle("设置")
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") { showSettings = false }
                        }
                    }
            }
        }
        .alert("新建歌单", isPresented: $showNewPlaylist) {
            TextField("歌单名称", text: $newPlaylistName)
            Button("创建") { createPlaylist() }
            Button("取消", role: .cancel) { newPlaylistName = "" }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("我的")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 46, height: 46)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.7)
                    }
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
                        .frame(width: 58, height: 58)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.16), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(profile.nickname)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.primary)
                            if profile.vipType > 0 {
                                VIPBadge()
                            }
                        }
                        Text("已登录网易云音乐")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Theme.accent.opacity(0.28))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("登录网易云音乐")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("同步我喜欢的音乐、歌单与每日推荐")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(account.hasAuthCookie ? "账户资料" : "登录网易云音乐")
    }

    private var musicSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("我的音乐")

            VStack(spacing: 0) {
                if let liked = account.likedSongsPlaylist {
                    NavigationLink(value: Destination.playlist(liked.id)) {
                        IOSLibraryCardRow(icon: "heart.fill", title: "我喜欢的音乐", tint: Theme.accent)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { showLogin = true } label: {
                        IOSLibraryCardRow(icon: "heart.fill", title: "我喜欢的音乐", tint: Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
                IOSLibraryRowDivider()
                NavigationLink(value: Destination.daily) {
                    IOSLibraryCardRow(icon: "calendar", title: "每日推荐", tint: .blue)
                }
                .buttonStyle(.plain)
                IOSLibraryRowDivider()
                NavigationLink(value: Destination.recents) {
                    IOSLibraryCardRow(icon: "clock.fill", title: "最近播放", tint: .blue)
                }
                .buttonStyle(.plain)
                IOSLibraryRowDivider()
                NavigationLink(value: Destination.collections) {
                    IOSLibraryCardRow(icon: "star.fill", title: "我的收藏", tint: .blue)
                }
                .buttonStyle(.plain)
                IOSLibraryRowDivider()
                NavigationLink(value: Destination.cloud) {
                    IOSLibraryCardRow(icon: "icloud.fill", title: "音乐云盘", tint: .blue)
                }
                .buttonStyle(.plain)
            }
            .libraryPanel()
        }
    }

    @ViewBuilder
    private var playlistSections: some View {
        if !account.createdPlaylists.isEmpty {
            playlistShelf(
                title: "创建的歌单",
                playlists: account.createdPlaylists,
                allowsCreation: true
            )
        }
        if !account.subscribedPlaylists.isEmpty {
            playlistShelf(
                title: "收藏的歌单",
                playlists: account.subscribedPlaylists,
                allowsCreation: false
            )
        }
    }

    private func playlistShelf(
        title: LocalizedStringKey,
        playlists: [PlaylistSummary],
        allowsCreation: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle(title)
                Spacer()
                if allowsCreation {
                    Button { showNewPlaylist = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 30, height: 30)
                            .background(Theme.accent.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("新建歌单")
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(playlists.enumerated()), id: \.element.id) { index, playlist in
                    NavigationLink(value: Destination.playlist(playlist.id)) {
                        HStack(spacing: 12) {
                            CachedAsyncImage(url: playlist.coverURL?.resizedImageURL(96), animated: false)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(playlist.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("\(playlist.trackCount) 首")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(minHeight: 64)
                        .padding(.horizontal, 18)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < playlists.count - 1 {
                        IOSLibraryRowDivider()
                    }
                }
            }
            .libraryPanel()
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 12)
    }

    private func createPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        newPlaylistName = ""
        guard !name.isEmpty else { return }
        Task {
            do {
                try await NeteaseAPI.createPlaylist(name: name, isPrivate: false)
                await account.refreshLibrary()
                ToastCenter.shared.show(String(localized: "歌单已创建"))
            } catch {
                ToastCenter.shared.show(error.localizedDescription)
            }
        }
    }
}

@available(iOS 16.0, *)
private struct IOSLibraryCardRow: View {
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
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 64)
        .padding(.horizontal, 18)
        .contentShape(Rectangle())
    }
}

@available(iOS 16.0, *)
private struct IOSLibraryRowDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.primary.opacity(0.10))
            .padding(.leading, 62)
    }
}

@available(iOS 16.0, *)
private extension View {
    func libraryPanel() -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}
#endif
