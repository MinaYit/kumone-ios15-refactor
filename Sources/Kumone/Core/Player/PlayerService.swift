import AVFoundation
import Foundation

enum RepeatMode: String, CaseIterable {
    case off, all, one

    var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}

enum PlaybackRate: Float, CaseIterable {
    case threeQuarters = 0.75
    case one = 1.0
    case oneAndQuarter = 1.25
    case oneAndHalf = 1.5
    case two = 2.0

    var next: PlaybackRate {
        let all = Self.allCases
        let nextIndex = (all.firstIndex(of: self)! + 1) % all.count
        return all[nextIndex]
    }

    var displayName: String {
        rawValue == 1 ? "1×" : "\(rawValue.cleanRateText)×"
    }
}

private extension Float {
    var cleanRateText: String {
        truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", self)
            : String(format: "%g", self)
    }
}

/// Where the current queue came from — used for scrobbling and UI affordances.
enum PlaySource: Equatable {
    case playlist(Int)
    case album(Int)
    case artist(Int)
    case daily
    case cloud
    case none

    var sourceID: Int {
        switch self {
        case .playlist(let id), .album(let id), .artist(let id): return id
        default: return 0
        }
    }
}

/// Where playback started from — listed under "Recently Played" in the Dock
/// menu, where picking one reloads it and starts playing again.
///
/// This is deliberately separate from `PlaySource`: heartbeat mode plays out
/// of the liked-songs playlist for scrobbling purposes, but as a *place* it is
/// its own thing, and the recents page has no source at all.
struct PlayContext: Codable, Hashable {
    enum Kind: String, Codable {
        /// Reloaded by id.
        case playlist, album, artist
        /// Fixed per-account entry points, each reloaded from its own API.
        case daily, cloud, recents, heartbeat, fm
    }

    let kind: Kind
    /// Zero for the fixed entry points, which have no id of their own.
    let id: Int
    let name: String

    static func playlist(id: Int, name: String) -> PlayContext {
        .init(kind: .playlist, id: id, name: name)
    }

    static func album(id: Int, name: String) -> PlayContext {
        .init(kind: .album, id: id, name: name)
    }

    static func artist(id: Int, name: String) -> PlayContext {
        .init(kind: .artist, id: id, name: name)
    }

    static var daily: PlayContext { .init(kind: .daily, id: 0, name: String(localized: "每日推荐")) }
    static var cloud: PlayContext { .init(kind: .cloud, id: 0, name: String(localized: "音乐云盘")) }
    static var recents: PlayContext { .init(kind: .recents, id: 0, name: String(localized: "最近播放")) }
    static var heartbeat: PlayContext { .init(kind: .heartbeat, id: 0, name: String(localized: "心动模式")) }
    static var fm: PlayContext { .init(kind: .fm, id: 0, name: String(localized: "私人漫游")) }

    /// Identity is the place, not its current title — a renamed playlist is
    /// still the same entry in the recents list.
    static func == (lhs: PlayContext, rhs: PlayContext) -> Bool {
        lhs.kind == rhs.kind && lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(id)
    }
}

enum RightPanel {
    case lyrics, queue
}

#if os(iOS)
enum IOSNowPlayingStartPanel {
    case lyrics, queue
}
#endif

/// The playback engine: queue, shuffle/repeat, personal FM, URL resolution,
/// lyrics, scrobbling. Modeled on YesPlayMusic's Player class, backed by AVPlayer.
/// High-frequency playback position, isolated so per-tick updates only
/// re-render the scrubbers/lyrics that observe it — not every view holding
/// the PlayerService.
@MainActor
final class PlaybackClock: ObservableObject {
    @Published var progress: TimeInterval = 0
}

/// Which lyric line is current.
///
/// Every lyric view used to derive this itself, which meant observing the clock
/// and re-rendering on every tick just to discover the line hadn't changed —
/// and for the now-playing page, whose body is the whole immersive layout, that
/// was five full re-evaluations a second. Computing it once here and publishing
/// only on a change turns that into one re-render per lyric line.
@MainActor
final class LyricsCursor: ObservableObject {
    @Published var activeIndex: Int?
}

@MainActor
final class PlayerService: ObservableObject {
    static let shared = PlayerService()

    // MARK: - Observable state

    @Published private(set) var queue: [Track] = []
    @Published private(set) var shuffledQueue: [Track] = []
    @Published private(set) var playNextList: [Track] = []
    @Published private(set) var currentIndex = -1
    @Published private(set) var currentTrack: Track?
    @Published private(set) var source: PlaySource = .none
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var servedQuality: String?
    @Published private(set) var unblockSource: String?
    @Published private(set) var isTrial = false
    let clock = PlaybackClock()
    let lyricsCursor = LyricsCursor()
    /// Passthrough to the clock so existing `progress` reads/writes keep working.
    var progress: TimeInterval {
        get { clock.progress }
        set { clock.progress = newValue }
    }
    @Published var repeatMode: RepeatMode = .off {
        didSet { UserDefaults.standard.set(repeatMode.rawValue, forKey: "player.repeat") }
    }

    @Published private(set) var shuffleEnabled = false
    @Published var playbackRate: PlaybackRate = .one {
        didSet {
            UserDefaults.standard.set(playbackRate.rawValue, forKey: "player.playbackRate")
            guard isPlaying else { return }
            engine.rate = playbackRate.rawValue
            NowPlayingManager.shared.updateElapsed(progress, rate: Double(playbackRate.rawValue))
        }
    }
    @Published var volume: Float = 1 {
        didSet {
            engine.volume = volume
            UserDefaults.standard.set(volume, forKey: "player.volume")
        }
    }
    private var volumeBeforeMute: Float = 0.8

    @Published private(set) var isFMMode = false
    @Published private(set) var fmUpcoming: [Track] = []
    /// Where playback was most recently started from, newest first —
    /// surfaced as "Recently Played" in the Dock menu.
    @Published private(set) var recentContexts: [PlayContext] = []
    /// 本机最近播放用于补足远端 scrobble 的网络延迟或失败；页面仍沿用原有记录行样式。
    private var localPlaybackHistory: [LocalPlaybackHistoryItem] = []
    @Published private(set) var lyrics: ParsedLyrics?
    @Published var activePanel: RightPanel?
    @Published var showNowPlaying = false
    #if os(iOS)
    @Published var iosNowPlayingStartPanel: IOSNowPlayingStartPanel?
    #endif

    /// The list the player is walking through (shuffled or ordered).
    var activeQueue: [Track] { shuffleEnabled ? shuffledQueue : queue }

    var upcomingTracks: [Track] {
        guard !activeQueue.isEmpty, currentIndex >= 0 else { return playNextList }
        let rest = activeQueue.suffix(from: min(currentIndex + 1, activeQueue.count))
        return playNextList + Array(rest.prefix(200))
    }

    /// 本地回退记录按最后播放时间倒序，并使用远端页面相同的数据模型。
    func localPlayRecords(week: Bool = false) -> [PlayRecordItem] {
        let weekStart = Calendar.current.date(
            byAdding: .day,
            value: -7,
            to: .now
        ) ?? .distantPast
        return localPlaybackHistory
            .filter { !week || $0.lastPlayedAt >= weekStart }
            .sorted { $0.lastPlayedAt > $1.lastPlayedAt }
            .map { PlayRecordItem(playCount: $0.playCount, song: $0.track) }
    }

    var hasCurrentTrack: Bool { currentTrack != nil }

    // MARK: - Engine

    private let engine = AVPlayer()

    /// Live playback position straight from the player, for smooth per-frame
    /// karaoke highlighting (the published `progress` is intentionally coarse).
    var livePlaybackTime: TimeInterval {
        let t = engine.currentTime().seconds
        return t.isFinite ? t : progress
    }
    private var timeObserver: Any?
    /// Lock-screen metadata does not need display-frame refreshes; keep it bounded
    /// while the SwiftUI playback clock remains frame-accurate for lyrics and scrubbers.
    private var lastSystemElapsedUpdate: TimeInterval = -Double.infinity
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var resolveGeneration = 0
    private var consecutiveFailures = 0
    private var scrobbled = false
    private var startScrobbled = false

    private init() {
        engine.actionAtItemEnd = .pause
        volume = UserDefaults.standard.object(forKey: "player.volume") as? Float ?? 0.8
        engine.volume = volume
        repeatMode = UserDefaults.standard.string(forKey: "player.repeat")
            .flatMap(RepeatMode.init) ?? .off
        let storedRate = UserDefaults.standard.float(forKey: "player.playbackRate")
        playbackRate = PlaybackRate(rawValue: storedRate) ?? .one

        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to activate audio session: \(error)")
        }

        // Resume after interruptions (phone calls, WeChat voice messages, …).
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                self?.handleAudioInterruption(note)
            }
        }
        // Keep lock screen / Control Center state in sync when AirPlay, Bluetooth,
        // wired headphones, or the built-in output route changes. AirDrop itself is
        // system-owned and cannot be controlled by an app; this handles audio routes.
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let reasonValue = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                   let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
                   reason == .oldDeviceUnavailable, self.isPlaying {
                    self.pause()
                }
                self.refreshSystemPlaybackState()
            }
        }
        #endif

        // Keep in-app transport controls and timestamped lyrics on the same
        // AVPlayer clock at up to 120 Hz. SwiftUI coalesces this on the current
        // display frame; buffering, seeking, and rate changes remain exact.
        timeObserver = engine.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 120), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isScrubbing else { return }
                let seconds = time.seconds
                guard seconds.isFinite else { return }

// Lyrics need the full player cadence to stay in sync; the cursor itself
                // publishes only when the active line changes.
                self.updateLyricsCursor(at: seconds)

                // The iOS 15 compatibility screens bind this value directly, so
                // retain their finer update interval rather than the iOS 16+
                // throttling used by upstream.
                if abs(seconds - self.progress) > 0.001 {
                    self.progress = seconds
                }

                // MPNowPlayingInfoCenter extrapolates from elapsed time and rate.
                // Retain its lightweight 5 Hz refresh rate instead of publishing it
                // for every UI frame.
                if abs(seconds - self.lastSystemElapsedUpdate) >= 0.2 {
                    self.lastSystemElapsedUpdate = seconds
                    NowPlayingManager.shared.updateElapsed(
                        seconds,
                        rate: self.isPlaying ? Double(self.playbackRate.rawValue) : 0
                    )
                }
            }
        }

        statusObservation = engine.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            }
        }

        NowPlayingManager.shared.attach(to: self)
        restoreState()
    }

    /// Set while the user drags the seek bar so the time observer doesn't fight the thumb.
    var isScrubbing = false

    #if os(iOS)
    /// UI tests use a deterministic local model so playback-control assertions do
    /// not depend on account state, artwork download, or the streaming backend.
    func loadUITestDemoTrackIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-uiTestingDemoTrack"),
              currentTrack == nil else { return }
        let json = """
        {"id":15,"name":"UI Test Track","ar":[{"id":1,"name":"Kumone"}],"al":{"id":1,"name":"UI Test Album","picUrl":null},"dt":180000}
        """
        let nextJSON = """
        {"id":16,"name":"UI Test Next Track","ar":[{"id":1,"name":"Kumone"}],"al":{"id":2,"name":"Kumone Test Album","picUrl":null},"dt":181000}
        """
        guard let track = try? JSONDecoder().decode(Track.self, from: Data(json.utf8)),
              let nextTrack = try? JSONDecoder().decode(Track.self, from: Data(nextJSON.utf8)) else { return }
        queue = [track, nextTrack]
        shuffledQueue = []
        playNextList = []
        currentIndex = 0
        source = .none
        currentTrack = track
        duration = track.duration
        progress = 0
        isPlaying = false
        isBuffering = false
        playbackRate = .one
    }
    #endif

    #if os(iOS)
    private var wasPlayingBeforeInterruption = false

    private func handleAudioInterruption(_ note: Notification) {
        guard let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            if isPlaying {
                // The system already silenced us; sync our state and UI.
                isPlaying = false
                NowPlayingManager.shared.updateElapsed(progress, rate: 0)
            }
        case .ended:
            let optionsValue = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            guard wasPlayingBeforeInterruption, options.contains(.shouldResume) else { return }
            wasPlayingBeforeInterruption = false
            try? AVAudioSession.sharedInstance().setActive(true)
            resumePlayback()
            NowPlayingManager.shared.updateElapsed(progress, rate: Double(playbackRate.rawValue))
        @unknown default:
            break
        }
    }
    #endif

    // MARK: - Entry points

    /// - Parameter context: the place these tracks came from. Supplying it
    ///   lists that place in the Dock menu's recently played section; callers
    ///   playing an ad-hoc selection (search results, a single track) omit it.
    func play(tracks: [Track], source: PlaySource, startAt track: Track? = nil,
              context: PlayContext? = nil) {
        guard !tracks.isEmpty else { return }
        if let context { recordRecent(context) }
        isFMMode = false
        queue = tracks
        self.source = source
        playNextList.removeAll()
        let startTrack = track ?? tracks[0]
        if shuffleEnabled {
            reshuffle(keeping: startTrack)
            currentIndex = 0
        } else {
            currentIndex = tracks.firstIndex(where: { $0.id == startTrack.id }) ?? 0
        }
        startPlaying(activeQueue[currentIndex])
    }

    func playTrack(_ track: Track) {
        if let idx = activeQueue.firstIndex(where: { $0.id == track.id }) {
            currentIndex = idx
            startPlaying(track)
        } else {
            play(tracks: [track], source: .none)
        }
    }

    /// Insert a track right after the current one.
    func addToPlayNext(_ track: Track, playNow: Bool = false) {
        playNextList.append(track)
        if playNow || currentTrack == nil {
            advanceToNext(userInitiated: true)
        } else {
            ToastCenter.shared.show(String(localized: "已添加到下一首播放"))
        }
    }

    func togglePlayPause() {
        guard let track = currentTrack else { return }
        if isPlaying {
            engine.pause()
            isPlaying = false
            AudioSpectrum.shared.reset()
        } else if engine.currentItem == nil {
            // Restored session: re-resolve the source.
            startPlaying(track, indexUnchanged: true)
            return
        } else {
            resumePlayback()
        }
        NowPlayingManager.shared.updateElapsed(
            progress,
            rate: isPlaying ? Double(playbackRate.rawValue) : 0
        )
    }

    func pause() {
        engine.pause()
        isPlaying = false
        AudioSpectrum.shared.reset()
        NowPlayingManager.shared.updateElapsed(progress, rate: 0)
    }

    func cyclePlaybackRate() {
        playbackRate = playbackRate.next
    }

    var isMuted: Bool { volume <= 0.001 }

    func toggleMute() {
        if isMuted {
            volume = max(volumeBeforeMute, 0.05)
        } else {
            volumeBeforeMute = volume
            volume = 0
        }
    }

    #if os(iOS)
    func presentNowPlaying(startingWith panel: IOSNowPlayingStartPanel) {
        iosNowPlayingStartPanel = panel
        showNowPlaying = true
    }
    #endif

    /// Stops playback and clears the currently presented mini-player surface.
    /// Cancelling the active resolution generation prevents a delayed network result
    /// from restoring a track after the user explicitly closes the player.
    func closeCurrentTrack() {
        resolveGeneration += 1
        engine.pause()
        engine.replaceCurrentItem(with: nil)
        isPlaying = false
        isBuffering = false
        queue.removeAll()
        shuffledQueue.removeAll()
        playNextList.removeAll()
        currentIndex = -1
        currentTrack = nil
        source = .none
        isFMMode = false
        fmUpcoming.removeAll()
        duration = 0
        progress = 0
        lyrics = nil
        isScrubbing = false
        showNowPlaying = false
        activePanel = nil
        #if os(iOS)
        iosNowPlayingStartPanel = nil
        #endif
        NowPlayingManager.shared.clear()
        persistState()
    }

    private func resumePlayback() {
        engine.playImmediately(atRate: playbackRate.rawValue)
        isPlaying = true
    }

    func next() {
        advanceToNext(userInitiated: true)
    }

    func previous() {
        if isFMMode { return }
        if progress > 4 || activeQueue.isEmpty {
            seek(to: 0)
            return
        }
        var idx = currentIndex - 1
        if idx < 0 {
            guard repeatMode == .all else {
                seek(to: 0)
                return
            }
            idx = activeQueue.count - 1
        }
        currentIndex = idx
        startPlaying(activeQueue[idx])
    }

    /// Recomputes the current lyric line, publishing only on a change.
    /// The lead makes a line light up just before it is sung.
    private func updateLyricsCursor(at seconds: TimeInterval) {
        let index = lyrics?.activeIndex(at: seconds + 0.2)
        if index != lyricsCursor.activeIndex {
            lyricsCursor.activeIndex = index
        }
    }

    func seek(to seconds: TimeInterval, completion: (@MainActor () -> Void)? = nil) {
        progress = seconds
lastSystemElapsedUpdate = seconds
        updateLyricsCursor(at: seconds)
        engine.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            guard let completion else { return }
            Task { @MainActor in completion() }
        }
        NowPlayingManager.shared.updateElapsed(
            seconds,
            rate: isPlaying ? Double(playbackRate.rawValue) : 0
        )
    }

    func toggleShuffle() {
        guard !isFMMode else { return }
        shuffleEnabled.toggle()
        guard let current = currentTrack else { return }
        if shuffleEnabled {
            reshuffle(keeping: current)
            currentIndex = 0
        } else {
            currentIndex = queue.firstIndex(where: { $0.id == current.id }) ?? 0
        }
    }

    func cycleRepeatMode() {
        guard !isFMMode else { return }
        repeatMode = repeatMode.next
    }

    /// Single-button mode cycle for the iOS minimal transport row:
    /// sequential → loop all → loop one → shuffle → sequential.
    func cyclePlaybackMode() {
        guard !isFMMode else { return }
        if shuffleEnabled {
            toggleShuffle()
            repeatMode = .off
        } else {
            switch repeatMode {
            case .off:
                repeatMode = .all
            case .all:
                repeatMode = .one
            case .one:
                repeatMode = .off
                toggleShuffle()
            }
        }
    }

    /// Jump to a track in the upcoming list (queue panel click).
    func jumpTo(_ track: Track) {
        if let nextIdx = playNextList.firstIndex(where: { $0.id == track.id }) {
            playNextList.removeSubrange(0...nextIdx)
            startPlaying(track, indexUnchanged: true)
            return
        }
        if let idx = activeQueue.firstIndex(where: { $0.id == track.id }) {
            currentIndex = idx
            startPlaying(track)
        }
    }

    func removeFromUpcoming(_ track: Track) {
        if let idx = playNextList.firstIndex(where: { $0.id == track.id }) {
            playNextList.remove(at: idx)
            return
        }
        if let idx = queue.firstIndex(where: { $0.id == track.id }), idx != currentIndex || shuffleEnabled {
            queue.remove(at: idx)
        }
        if let idx = shuffledQueue.firstIndex(where: { $0.id == track.id }) {
            shuffledQueue.remove(at: idx)
        }
    }

    // MARK: - Personal FM

    func startFM() {
        guard !isFMMode || !isPlaying else { return }
        recordRecent(.fm)
        isFMMode = true
        shuffleEnabled = false
        repeatMode = .off
        queue = []
        shuffledQueue = []
        playNextList = []
        currentIndex = -1
        source = .none
        Task { await fmAdvance() }
    }

    func fmNext() {
        guard isFMMode else { return }
        Task { await fmAdvance() }
    }

    func fmTrash() {
        guard isFMMode, let track = currentTrack else { return }
        Task {
            await fmAdvance()
            try? await NeteaseAPI.fmTrash(id: track.id)
        }
    }

    private func fmAdvance() async {
        if fmUpcoming.isEmpty {
            for attempt in 0..<3 {
                if let tracks = try? await NeteaseAPI.personalFM(), !tracks.isEmpty {
                    fmUpcoming = tracks
                    break
                }
                if attempt == 2 {
                    ToastCenter.shared.show(String(localized: "获取私人漫游数据失败"))
                    return
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        guard !fmUpcoming.isEmpty else { return }
        let track = fmUpcoming.removeFirst()
        startPlaying(track, indexUnchanged: true)
        if fmUpcoming.count < 1 {
            if let more = try? await NeteaseAPI.personalFM() {
                fmUpcoming.append(contentsOf: more)
            }
        }
    }

    // MARK: - Advancing

    private func advanceToNext(userInitiated: Bool) {
        if isFMMode {
            Task { await fmAdvance() }
            return
        }
        if !playNextList.isEmpty {
            let track = playNextList.removeFirst()
            startPlaying(track, indexUnchanged: true)
            return
        }
        guard !activeQueue.isEmpty else { return }
        var idx = currentIndex + 1
        if idx >= activeQueue.count {
            guard repeatMode == .all else {
                if userInitiated {
                    ToastCenter.shared.show(String(localized: "已经是最后一首了"))
                } else {
                    isPlaying = false
                    NowPlayingManager.shared.updateElapsed(progress, rate: 0)
                }
                return
            }
            idx = 0
        }
        currentIndex = idx
        startPlaying(activeQueue[idx])
    }

    private func handleItemEnded() {
        scrobbleIfNeeded(completed: true)
        if repeatMode == .one, !isFMMode {
            scrobbled = false
            seek(to: 0)
            resumePlayback()
            return
        }
        advanceToNext(userInitiated: false)
    }

    // MARK: - Source resolution

    private func startPlaying(_ track: Track, indexUnchanged: Bool = false) {
        scrobbleIfNeeded(completed: false)
        currentTrack = track
        recordLocalPlayback(track)
        progress = 0
        duration = track.duration
        servedQuality = nil
        unblockSource = nil
        isTrial = false
        lyrics = nil
        scrobbled = false
        startScrobbled = false
        isPlaying = true
        lyricsCursor.activeIndex = nil
        // Before the URL is even resolved: holds the bars still rather than
        // letting them fall back to the decorative animation for the moment it
        // takes to find out whether this source can be tapped.
        AudioSpectrum.shared.beginPreparing()
        resolveGeneration += 1
        let generation = resolveGeneration

        NowPlayingManager.shared.updateMetadata(for: track, duration: track.duration)
        persistState()

        Task {
            await resolveAndLoad(track, generation: generation)
        }
        Task {
            await loadLyrics(for: track, generation: generation)
        }
    }

    private func resolveAndLoad(_ track: Track, generation: Int) async {
        let quality = SettingsManager.shared.audioQuality.rawValue
        var data = try? await NeteaseAPI.songURL(ids: [track.id], level: quality).first
        if data?.url == nil, quality != AudioQuality.standard.rawValue {
            data = try? await NeteaseAPI.songURL(ids: [track.id], level: AudioQuality.standard.rawValue).first
        }
        guard generation == resolveGeneration else { return }

        var resolvedURL: URL?
        if let urlString = data?.url {
            resolvedURL = URL(string: urlString.replacingOccurrences(of: "http://", with: "https://"))
        }

        // NetEase refused — try third-party sources (UnblockNeteaseMusic-style).
        if resolvedURL == nil || data?.freeTrialInfo != nil, SettingsManager.shared.enableUnblock {
            if let unblocked = await UnblockService.resolve(track) {
                guard generation == resolveGeneration else { return }
                resolvedURL = unblocked.url
                unblockSource = unblocked.source
                data = nil
                ToastCenter.shared.show(String(localized: "已使用第三方音源：\(unblocked.source)"))
            }
        }
        guard generation == resolveGeneration else { return }

        guard let url = resolvedURL else {
            consecutiveFailures += 1
            let reason = track.playability(privilege: nil,
                                           isLoggedIn: AccountStore.shared.isLoggedIn,
                                           vipType: AccountStore.shared.vipType).reason
            ToastCenter.shared.show(String(localized: "《\(track.name)》无法播放\(reason.map { "：\($0)" } ?? "")"))
            if consecutiveFailures < 5 {
                advanceToNext(userInitiated: false)
            } else {
                isPlaying = false
            }
            return
        }

        consecutiveFailures = 0
        servedQuality = data?.level
        if data?.freeTrialInfo != nil {
            isTrial = true
            ToastCenter.shared.show(String(localized: "VIP 歌曲，当前为试听片段"))
        }

        // Resolve the asset's audio track before the item goes live: an audio mix
        // attached after playback starts is silently ignored, so the spectrum tap
        // has to be spliced in here or not at all. Sources that refuse byte-range
        // requests never resolve a track — those play untapped and the UI falls
        // back to its decorative animation.
        let asset = AVURLAsset(url: url)
        let assetTrack = await loadAudioTrack(from: asset, timeout: 2)
        guard generation == resolveGeneration else { return }

        let item = AVPlayerItem(asset: asset)
        if let assetTrack, let mix = AudioSpectrum.shared.makeAudioMix(for: assetTrack) {
            item.audioMix = mix
        } else {
            AudioSpectrum.shared.markUntappable()
        }

        if let old = endObserver {
            NotificationCenter.default.removeObserver(old)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleItemEnded()
            }
        }
        engine.replaceCurrentItem(with: item)
        resumePlayback()

        if !startScrobbled {
            startScrobbled = true
            let tid = track.id
            let sid = source.sourceID
            Task.detached { await NeteaseAPI.scrobbleStart(trackID: tid, sourceID: sid) }
        }

        if let time = data?.time, time > 0 {
            duration = TimeInterval(time) / 1000
            NowPlayingManager.shared.updateMetadata(for: track, duration: duration)
        }
        NowPlayingManager.shared.updateElapsed(progress, rate: Double(playbackRate.rawValue))
    }

    /// Resolves the asset's audio track, giving up after `timeout` so a slow or
    /// uncooperative source delays playback no longer than it would today.
    private func loadAudioTrack(from asset: AVURLAsset, timeout: TimeInterval) async -> AVAssetTrack? {
        await withTaskGroup(of: AVAssetTrack?.self) { group in
            group.addTask {
                try? await asset.loadTracks(withMediaType: .audio).first
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func loadLyrics(for track: Track, generation: Int) async {
        let response = try? await NeteaseAPI.lyric(id: track.id)
        guard generation == resolveGeneration else { return }
        lyrics = response.map(LyricsParser.parse)
        updateLyricsCursor(at: progress)
    }

    #if os(iOS)
    /// Re-publish the authoritative elapsed time and rate after an output-route
    /// change so iOS 15 Control Center and external audio devices stay in sync.
    private func refreshSystemPlaybackState() {
        guard hasCurrentTrack else { return }
        NowPlayingManager.shared.updateElapsed(
            progress,
            rate: isPlaying ? Double(playbackRate.rawValue) : 0
        )
    }
    #endif

    // MARK: - Playback

    private func scrobbleIfNeeded(completed: Bool) {
        guard let track = currentTrack, !scrobbled, progress > 1 else { return }
        scrobbled = true
        let seconds = completed ? Int(duration) : Int(progress)
        let sourceID = source.sourceID
        Task.detached {
            await NeteaseAPI.scrobbleFinish(trackID: track.id, sourceID: sourceID, seconds: seconds)
        }
    }

    // MARK: - Shuffle helpers

    private func reshuffle(keeping first: Track) {
        var rest = queue.filter { $0.id != first.id }
        rest.shuffle()
        shuffledQueue = [first] + rest
    }

    // MARK: - Persistence

    private static let recentContextsLimit = 6
    private static let localPlaybackHistoryLimit = 300

    private struct LocalPlaybackHistoryItem: Codable, Hashable {
        let track: Track
        var playCount: Int
        var lastPlayedAt: Date
    }

    /// 在曲目选中后立即写入本机历史，不等待音源或歌词网络请求完成。
    /// 因此歌词页切换、快速下一曲和短暂网络失败都不会丢失最近播放记录。
    private func recordLocalPlayback(_ track: Track) {
        if let index = localPlaybackHistory.firstIndex(where: { $0.track.id == track.id }) {
            localPlaybackHistory[index].playCount += 1
            localPlaybackHistory[index].lastPlayedAt = .now
        } else {
            localPlaybackHistory.insert(
                .init(track: track, playCount: 1, lastPlayedAt: .now),
                at: 0
            )
        }
        localPlaybackHistory.sort { $0.lastPlayedAt > $1.lastPlayedAt }
        if localPlaybackHistory.count > Self.localPlaybackHistoryLimit {
            localPlaybackHistory.removeLast(
                localPlaybackHistory.count - Self.localPlaybackHistoryLimit
            )
        }
    }

    private func recordRecent(_ context: PlayContext) {
        recentContexts.removeAll { $0 == context }
        recentContexts.insert(context, at: 0)
        if recentContexts.count > Self.recentContextsLimit {
            recentContexts.removeLast(recentContexts.count - Self.recentContextsLimit)
        }
    }

    /// Reloads a place from the recents list and starts playing it again.
    func play(context: PlayContext) {
        // Personal FM is a stream, not a fixed list — restart it in place.
        guard context.kind != .fm else { return startFM() }
        Task {
            do {
                guard let resolved = try await resolve(context) else { return }
                play(tracks: resolved.tracks, source: resolved.source, context: context)
            } catch {
                ToastCenter.shared.show(error.localizedDescription)
            }
        }
    }

    private func resolve(_ context: PlayContext) async throws -> (tracks: [Track], source: PlaySource)? {
        switch context.kind {
        case .fm:
            return nil
        case .album:
            return (try await NeteaseAPI.album(id: context.id).songs, .album(context.id))
        case .artist:
            return (try await NeteaseAPI.artist(id: context.id).hotSongs, .artist(context.id))
        case .daily:
            return (try await NeteaseAPI.dailyRecommendSongs(), .daily)
        case .cloud:
            let songs = try await NeteaseAPI.cloudSongs().data?.compactMap(\.simpleSong) ?? []
            return (songs, .cloud)
        case .recents:
            guard let uid = AccountStore.shared.profile?.userId else { return nil }
            return (try await NeteaseAPI.playRecords(uid: uid, week: false).map(\.song), .none)
        case .heartbeat:
            // Regenerated from a fresh seed, the same way the Home card does it.
            guard let liked = AccountStore.shared.likedSongsPlaylist,
                  let seed = AccountStore.shared.likedTrackIDs.randomElement() else { return nil }
            let tracks = try await NeteaseAPI.intelligenceList(songID: seed, playlistID: liked.id)
            return (tracks, .playlist(liked.id))
        case .playlist:
            let response = try await NeteaseAPI.playlistDetail(id: context.id)
            var tracks = response.playlist.tracks
            // /v6/playlist/detail only carries the first page of tracks.
            let remaining = response.playlist.trackIds.map(\.id).dropFirst(tracks.count)
            for chunk in stride(from: 0, to: remaining.count, by: 500)
                .map({ Array(remaining.dropFirst($0).prefix(500)) }) {
                guard let more = try? await NeteaseAPI.songDetails(ids: chunk) else { break }
                tracks += more.songs
            }
            return (tracks, .playlist(context.id))
        }
    }

    private struct PersistedState: Codable {
        var queue: [Track]
        var currentID: Int?
        var repeatMode: String
        var shuffle: Bool
        /// Optional so state files written before recents existed still decode.
        var recentContexts: [PlayContext]?
        /// Optional so existing installations can upgrade without data migration.
        var localPlaybackHistory: [LocalPlaybackHistoryItem]?
    }

    private func persistState() {
        let state = PersistedState(
            queue: Array(queue.prefix(1000)),
            currentID: currentTrack?.id,
            repeatMode: repeatMode.rawValue,
            shuffle: shuffleEnabled,
            recentContexts: recentContexts,
            localPlaybackHistory: localPlaybackHistory
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        let url = Self.stateFileURL
        Task.detached {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func restoreState() {
        guard let data = try? Data(contentsOf: Self.stateFileURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data)
        else { return }
        // Recents outlive the queue: restore them before bailing out on an
        // empty queue, or the next played track persists an empty list over
        // them and the Dock menu loses its history for good.
        recentContexts = Array((state.recentContexts ?? []).prefix(Self.recentContextsLimit))
        localPlaybackHistory = Array(
            (state.localPlaybackHistory ?? [])
                .sorted { $0.lastPlayedAt > $1.lastPlayedAt }
                .prefix(Self.localPlaybackHistoryLimit)
        )
        guard !state.queue.isEmpty else { return }
        queue = state.queue
        shuffleEnabled = state.shuffle
        if shuffleEnabled {
            shuffledQueue = queue.shuffled()
        }
        if let id = state.currentID,
           let idx = activeQueue.firstIndex(where: { $0.id == id }) {
            currentIndex = idx
            currentTrack = activeQueue[idx]
            duration = activeQueue[idx].duration
            NowPlayingManager.shared.updateMetadata(for: activeQueue[idx], duration: duration)
            Task {
                await loadLyrics(for: activeQueue[idx], generation: resolveGeneration)
            }
        }
    }

    private static var stateFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kumone", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("player-state.json")
    }
}
