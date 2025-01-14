import SwiftUI
import AlertToast
import PINRemoteImage
import AVFoundation
import MediaPlayer

@MainActor
class ViewModel: ObservableObject {
    
    // MARK: - Web Socket
    
    var playerWebSocket: PlayerWebSocket?
    
    var playlistsWebSocket: PlaylistsWebSocket?
    
    var playlistWebSocket: PlaylistWebSocket?
    
    var eventWebSocket: EventWebSocket?
    
    // MARK: - Player Queue
    
    let playerQueue = DispatchQueue(
        label: "PlayerQueue",
        qos: .userInteractive,
        attributes: [],
        autoreleaseFrequency: .inherit,
        target: .global(qos: .userInteractive)
    )
    
    // MARK: - Player Observe Counter
    
    var playerObserveCounter = 0
    
    // MARK: - API
    
    weak var api: API!
    
    // MARK: - Interface State
    
    enum InterfaceState {
        case player
        
        case queue
        
        case library
    }
    
    @Published
    var interfaceState = InterfaceState.player
    
    // MARK: - Player State
    
    enum PlayerState {
        case playing, paused
        
        mutating func toggle() {
            self = {
                switch self {
                case .playing:
                    return .paused
                    
                case .paused:
                    return .playing
                }
            }()
        }
    }
    
    @Published
    var playerState = PlayerState.paused
    
    // MARK: - Player Quality
    
    enum PlayerQuality: String {
        case standard = "STANDARD"
        
        case highFidelity = "HIGH_FIDELITY"
        
        static var key: String {
            "PlayerQuality"
        }
    }
    
    @Published
    var playerQuality: PlayerQuality = {
        guard
            let savedPlayerQualityRawValue = UserDefaults.standard
                .object(forKey: PlayerQuality.key) as? String,
            let savedPlayerQuality = PlayerQuality(rawValue: savedPlayerQualityRawValue)
        else {
            return .highFidelity
        }
        
        return savedPlayerQuality
    }() {
        didSet {
            UserDefaults.standard
                .set(
                    playerQuality.rawValue,
                    forKey: PlayerQuality.key
                )
            
            if playerState == .playing {
                Task {
                    try await pause()
                    try await resume()
                }
            }
        }
    }
    
    // MARK: - Library State
    
    enum LibraryState {
        case ownPlaylists, playlists, events
    }
    
    @Published
    var libraryState = LibraryState.ownPlaylists
    
    // MARK: - Repeat State
    
    enum RepeatState {
        case on, off
        
        mutating func toggle() {
            self = {
                switch self {
                case .on:
                    return .off
                    
                case .off:
                    return .on
                }
            }()
        }
    }
    
    @Published
    var repeatState = RepeatState.off
    
    // MARK: - Sign Out
    
    @Published
    var showingSignOutConfirmation = false
    
    // MARK: Interface Constants
    
    var placeholderTitle = "Not Playing"
    
    var defaultTitle = "Untitled"
    
    let primaryControlsColor = Color.primary
    
    let secondaryControlsColor = Color.primary.opacity(0.55)
    
    let tertiaryControlsColor = Color.primary.opacity(0.3)
    
    let gradient = (
        backgroundColor: Color(red: 0.2, green: 0.2, blue: 0.2),
        center: UnitPoint.center,
        startRadius: CGFloat(50),
        endRadius: CGFloat(600),
        blurRadius: CGFloat(150),
        material: Material.ultraThinMaterial,
        transition: AnyTransition.opacity,
        ignoresSafeAreaEdges: Edge.Set.all
        
    )
    
    // MARK: - Artwork
    
    var musicKit = MusicKit()
    
    @Published
    var artworkTransitionAnchor = UnitPoint.topLeading
    
    var playerArtworkPadding: CGFloat {
        switch playerState {
        case .playing:
            return .zero
            
        case .paused:
            return 34
        }
    }
    
    @MainActor
    var playerArtworkWidth: CGFloat?
    
    @Published
    var animatingPlayerState = false
    
    var artworkPlaceholder = (
        backgroundColor: Color(red: 0.33, green: 0.325, blue: 0.349),
        foregroundColor: Color(red: 0.462, green: 0.458, blue: 0.474)
    )
    
    @Published
    var artworkPrimaryColor = Color(red: 0.33, green: 0.325, blue: 0.349)
    
    let playlistArtworkWidth = CGFloat(64)
    
    let playlistQueueArtworkWidth = CGFloat(48)
    
    var artworkProxyPrimaryColor: Color?
    
    static var artworksCapacity = 32
    
    @MainActor
    @Published
    var artworks = [String?: Image](minimumCapacity: artworksCapacity)
    
    var playerScale: CGFloat {
        switch playerState {
        case .paused:
            return 0.8
            
        case .playing:
            return 1
        }
    }
    
    var artworkScale: CGFloat {
        guard
            let playerArtworkWidth = playerArtworkWidth
        else {
            return .zero
        }
        
        switch interfaceState {
        case .player, .library:
            return playlistArtworkWidth / (playerArtworkWidth * playerScale)
            
        case .queue:
            return (playerArtworkWidth * playerScale) / playlistArtworkWidth
        }
    }
    
    let placeholderArtworkImage = generateImage(
        CGSize(width: 1000, height: 1000),
        rotatedContext: { size, context in
            
            context.clear(CGRect(origin: CGPoint(), size: size))
            
            let musicNoteIcon = UIImage(systemName: "music.note")?
                .withConfiguration(UIImage.SymbolConfiguration(
                    pointSize: 1000 * 0.375,
                    weight: .medium
                ))
            ?? UIImage()
            
            drawIcon(
                context: context,
                size: size,
                icon: musicNoteIcon,
                iconSize: musicNoteIcon.size,
                iconColor: UIColor(displayP3Red: 0.462, green: 0.458, blue: 0.474, alpha: 1),
                backgroundColors: [
                    UIColor(displayP3Red: 0.33, green: 0.325, blue: 0.349, alpha: 1),
                    UIColor(displayP3Red: 0.33, green: 0.325, blue: 0.349, alpha: 1),
                ],
                id: nil
            )
        }
    )?
        .withRenderingMode(.alwaysOriginal) ?? UIImage()
    
    let placeholderCoverImage = generateImage(
        CGSize(width: 60, height: 60),
        rotatedContext: { size, context in
            
            context.clear(CGRect(origin: CGPoint(), size: size))
            
            let musicNoteIcon = UIImage(systemName: "music.note.list")?
                .withConfiguration(UIImage.SymbolConfiguration(
                    pointSize: 60 * 0.375,
                    weight: .medium
                ))
            ?? UIImage()
            
            drawIcon(
                context: context,
                size: size,
                icon: musicNoteIcon,
                iconSize: musicNoteIcon.size,
                iconColor: UIColor(displayP3Red: 0.462, green: 0.458, blue: 0.474, alpha: 1),
                backgroundColors: [
                    UIColor(displayP3Red: 0.33, green: 0.325, blue: 0.349, alpha: 1),
                    UIColor(displayP3Red: 0.33, green: 0.325, blue: 0.349, alpha: 1),
                ],
                id: nil
            )
        }
    )?
        .withRenderingMode(.alwaysOriginal) ?? UIImage()
    
    lazy var placeholderArtwork = Image(uiImage: placeholderArtworkImage)
    
    // MARK: - Track Progress
    
    struct TrackProgress: Equatable {
        let value: Double?
        
        let total: Double?
        
        struct Buffer: Equatable {
            let start: Double
            let duration: Double
        }
        
        let buffers: [Buffer]?
        
        var remaining: Double? {
            guard
                let value = value,
                let total = total
            else {
                return nil
            }
            
            return value - total
        }
    }
    
    @Published
    var trackProgress = TrackProgress(value: nil, total: nil, buffers: nil) {
        didSet {
            if Int(trackProgress.value ?? 0) != Int(oldValue.value ?? 0) {
                updateNowPlayingElapsedPlaybackTime(trackProgress.value)
            }
        }
    }
    
    @Published
    var animatingProgressSlider = false
    
    @Published
    var isLoadingProgress = false {
        didSet {
            guard isLoadingProgress else { return }
            
            seek()
        }
    }
    
    @Published
    var isTrackingProgress = false {
        didSet {
            animatingProgressPadding.toggle()
        }
    }
    
    // MARK: - Seek
    
    @MainActor
    func seek() {
        guard
            let progress = trackProgress.value
        else {
            if playerState == .playing {
                player.play()
            }
            
            return
        }
        
        Task.detached { [unowned self] in
            let timeScale = CMTimeScale(44100)
            let time = CMTime(seconds: progress, preferredTimescale: timeScale)
            
            let isSeeked = await self.player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            
            guard
                isSeeked
            else {
//                await self.seek()
                
                return
            }
            
            Task.detached { @MainActor [unowned self] in
                self.isLoadingProgress = false
                
                if playerState == .playing {
                    player.play()
                }
            }
        }
    }
    
    @Published
    var initialProgressValue: Double?
    
    @Published
    var animatingProgressPadding = false
    
    // MARK: - Update Data
    
    func updateData() {
        Task {
            do {
                try await updateOwnPlaylists()
            } catch {
                debugPrint(error)
            }
        }
        
        Task {
            do {
                try await updatePlaylists()
            } catch {
                debugPrint(error)
            }
        }
        
        Task {
            do {
                try await updateEvents()
            } catch {
                debugPrint(error)
            }
        }
        
        Task {
            do {
                try await updateUsers()
            } catch {
                debugPrint(error)
            }
        }
        
        Task {
            do {
                try await updateArtists()
            } catch {
                debugPrint(error)
            }
        }
        
        Task {
            do {
                try await updateTracks()
            } catch {
                debugPrint(error)
            }
        }
        
//        Task {
//            do {
//                try await updatePlayerSession()
//            } catch {
//                debugPrint(error)
//            }
//        }
        
        if playerWebSocket == nil, eventWebSocket == nil {
            subscribeToPlayer()
        }
        
        if playlistsWebSocket == nil {
            subscribeToPlaylists()
        }
    }
    
    // MARK: - Own Playlists
    
    @Published
    var ownPlaylists = [Playlist]() {
        didSet {
            Task {
                do {
                    try await updatePlaylists()
                } catch {
                    debugPrint(error)
                }
            }
        }
    }
    
    func updateOwnPlaylists() async throws {
        Task {
            ownPlaylists = try await DiskCacheService.entity(name: "Own")
        }
        
        do {
            let ownPlaylists = try await api.ownPlaylistRequest()
            
            try await saveOwnPlaylists(ownPlaylists)
        } catch {
            debugPrint(error)
            
            try await DiskCacheService.updateEntity([Playlist]?.none, name: "Own")
        }
    }
    
    @MainActor
    func saveOwnPlaylists(_ ownPlaylists: [Playlist]) async throws {
        self.ownPlaylists = ownPlaylists
        
        try await DiskCacheService.updateEntity(ownPlaylists, name: "Own")
    }
    
    // MARK: - Playlists
    
    @Published
    var playlists = [Playlist]()
    
    func updatePlaylists() async throws {
        Task {
            playlists = try await DiskCacheService.entity(name: "All")
        }
        
        do {
            let playlists = try await api.playlistRequest()
            
            try await savePlaylists(playlists)
        } catch {
            debugPrint(error)
            
            try await DiskCacheService.updateEntity([Playlist]?.none, name: "All")
        }
    }
    
    @MainActor
    func savePlaylists(_ playlists: [Playlist]) async throws {
        self.playlists = playlists
        
        try await DiskCacheService.updateEntity(playlists, name: "All")
    }
    
    @Published
    var events = [Event]()
    
    func updateEvents() async throws {
        Task {
            events = try await DiskCacheService.entity(name: "All")
        }
        
        do {
            let events = try await api.eventRequest()
            
            try await saveEvents(events)
        } catch {
            debugPrint(error)
            
            try await DiskCacheService.updateEntity([Event]?.none, name: "All")
        }
    }
    
    @MainActor
    func saveEvents(_ events: [Event]) async throws {
        self.events = events
        
        try await DiskCacheService.updateEntity(events, name: "All")
    }
    
    // MARK: - Users
    
    @Published
    var users = [User]()
    
    func user(byID userID: Int) -> User? {
        users.first(where: { $0.id == userID })
    }
    
    func updateUsers() async throws {
        Task {
            users = try await DiskCacheService.entity(name: "All")
        }
        
        do {
            let users = try await api.usersRequest()
            
            self.users = users
            
            try await DiskCacheService.updateEntity(users, name: "All")
        } catch {
            debugPrint(error)
            
            try await DiskCacheService.updateEntity([User]?.none, name: "All")
        }
    }
    
    // MARK: - Artists
    
    @Published
    var artists = [Artist]()
    
    func artist(byID artistID: Int) -> Artist? {
        artists.first(where: { $0.id == artistID })
    }
    
    func updateArtists() async throws {
        Task {
            artists = try await DiskCacheService.entity(name: "All")
        }
        
        do {
            let artists = try await api.artistsRequest()
            
            self.artists = artists
            
            try await DiskCacheService.updateEntity(artists, name: "All")
        } catch {
            debugPrint(error)
            
            try await DiskCacheService.updateEntity([Artist]?.none, name: "All")
        }
    }
    
    // MARK: - Tracks
    
    @Published
    var tracks = [Track]() {
        didSet {
            tracksPlayerContent = tracks.compactMap { track in
                guard
                    let trackID = track.id,
                    let artist = artist(byID: track.artist)?.name
                else {
                    return nil
                }
                
                return .track(
                    id: trackID,
                    title: track.name,
                    artist: artist,
                    flacFile: track.flacFile,
                    mp3File: track.mp3File,
                    progress: nil,
                    playerSessionID: nil,
                    sessionTrackID: nil,
                    sessionTrackState: nil
                )
            }
        }
    }
    
    @Published
    var tracksPlayerContent = [PlayerContent]()
    
    func track(byID trackID: Int) -> Track? {
        tracks.first(where: { $0.id == trackID })
    }
    
    func updateTracks() async throws {
        Task {
            tracks = try await DiskCacheService.entity(name: "All")
        }
        
        do {
            let tracks = try await api.trackRequest()
            
            self.tracks = tracks
            
            try await DiskCacheService.updateEntity(tracks, name: "All")
        } catch {
            debugPrint(error)
            
            try await DiskCacheService.updateEntity([Track]?.none, name: "All")
        }
    }
    
    // MARK: Player Session
    
    @Published
    var playerSession: PlayerSession? {
        didSet {
            Task {
                try await DiskCacheService.updateEntity(playerSession, name: "")
            }
            
            Task {
                if tracks.isEmpty {
                    try await updateTracks()
                }
                
                await MainActor.run { [unowned self] in
                    withAnimation {
                        currentPlayerContent = { () -> PlayerContent? in
                            guard
                                let playerSession,
                                let sessionTrack = playerSession.trackQueue.first,
                                let track = track(byID: sessionTrack.track),
                                let trackID = track.id,
                                let artist = artist(byID: track.artist),
                                let playerSessionID = playerSession.id,
                                let sessionTrackID = sessionTrack.id
                            else {
                                return nil
                            }
                            
                            return .track(
                                id: trackID,
                                title: track.name,
                                artist: artist.name,
                                flacFile: track.flacFile,
                                mp3File: track.mp3File,
                                progress: sessionTrack.progress ?? 0,
                                playerSessionID: playerSessionID,
                                sessionTrackID: sessionTrackID,
                                sessionTrackState: sessionTrack.state
                            )
                        }()
                        
                        queuedPlayerContent = {
                            guard let playerSession else { return [] }
                            
                            return playerSession
                                .trackQueue
                                .dropFirst()
                                .compactMap { (sessionTrack) -> PlayerContent? in
                                    guard
                                        let track = track(byID: sessionTrack.track),
                                        let trackID = track.id,
                                        let artist = artist(byID: track.artist),
                                        let playerSessionID = playerSession.id,
                                        let sessionTrackID = sessionTrack.id
                                    else {
                                        return nil
                                    }
                                    
                                    return .track(
                                        id: trackID,
                                        title: track.name,
                                        artist: artist.name,
                                        flacFile: track.flacFile,
                                        mp3File: track.mp3File,
                                        progress: sessionTrack.progress ?? 0,
                                        playerSessionID: playerSessionID,
                                        sessionTrackID: sessionTrackID,
                                        sessionTrackState: sessionTrack.state
                                    )
                                }
                        }()
                        
                        switch playerSession?.mode {
                            
                        case .normal:
                            repeatState = .off
                            
                        case .repeat:
                            repeatState = .on
                            
                        default:
                            break
                        }
                        
//                        playCurrentTrack()
                    }
                }
            }
        }
    }
    
    func updatePlayerSession() async throws {
        Task {
            playerSession = try await DiskCacheService.entity(name: "")
        }
        
        do {
            let playerSession = try await api.playerSessionRequest()
            
            self.playerSession = playerSession
            
            try await DiskCacheService.updateEntity(playerSession, name: "")
        } catch {
            debugPrint(error)
            
            try await DiskCacheService.updateEntity(PlayerSession?.none, name: "")
        }
    }
    
    var currentTrackFile: File? {
        guard
            let currentPlayerContent
        else {
            return nil
        }
        
        switch playerQuality {
        case .standard:
            return currentPlayerContent.mp3File
            
        case .highFidelity:
            return currentPlayerContent.flacFile
        }
    }
    
    var queuedTracks = [(sessionTrackID: Int?, track: Track)]()
    
    @Published
    var currentPlayerContent: PlayerContent? {
        didSet {
            guard
                let currentPlayerContent
            else {
                return
            }
            
            let progressValue = (currentPlayerContent.progress as NSDecimalNumber?)
            
            let progressTotal = (currentTrackFile?.duration as NSDecimalNumber?)
            
            let buffers = self.player.currentItem?.loadedTimeRanges.map { timeRange in
                let startSeconds = timeRange.timeRangeValue.start.seconds
                let durationSeconds = timeRange.timeRangeValue.duration.seconds

                return TrackProgress.Buffer(start: startSeconds, duration: durationSeconds)
            }
            
            let trackProgress = TrackProgress(
                value: progressValue?.doubleValue,
                total: progressTotal?.doubleValue,
                buffers: buffers
            )
            
            if oldValue?.sessionTrackID != currentPlayerContent.sessionTrackID {
                self.trackProgress = trackProgress
            }
            
            switch currentPlayerContent.sessionTrackState {
                
            case .paused, .stopped:
                animatingPlayerState.toggle()
                
                playerState = .paused
                
                pauseCurrentTrack()
                
            case .playing:
                animatingPlayerState.toggle()
                
                if oldValue?.id != currentPlayerContent.id {
                    pauseCurrentTrack()
                    playCurrentTrack()
                }
                
                if playerState != .playing {
                    playCurrentTrack()
                }
                
                playerState = .playing
                
            default:
                break
            }
        }
    }
    
    var queuedPlayerContent = [PlayerContent]()
    
    // MARK: - Actions
    
    var isAuthorized: Bool {
        api.isAuthorized
    }
    
    @Published
    var isSignInToastShowing = false
    
    @Published
    var signInToastType: AlertToast.AlertType = .error(.red)
    
    @Published
    var signInToastTitle: String?
    
    @Published
    var signInToastSubtitle: String?
    
    @Published
    var isToastShowing = false
    
    @Published
    var toastType: AlertToast.AlertType = .complete(.green)
    
    @Published
    var toastTitle: String?
    
    @Published
    var toastSubtitle: String?
    
    func auth(_ username: String, _ password: String) async throws {
        if case .failure(let error) = try await api.authRequest(
            TokenObtainPair(
                username: username,
                password: password
            )
        ) {
            signInToastType = .error(.red)
            signInToastTitle = "Oops..."
            signInToastSubtitle = error.username?.first ?? error.password?.first
            
            isSignInToastShowing = true
            
            let greetings: String = {
                let hour = Calendar.current.component(.hour, from: Date())
                  
                let newDay = 0
                let noon = 12
                let sunset = 18
                let midnight = 24
                
                switch hour {
                case newDay..<noon:
                    return "Good Morning"
                    
                case noon..<sunset:
                    return "Good Afternoon"
                    
                case sunset..<midnight:
                    return "Good Evening"
                    
                default:
                    return "Hello"
                }
            }()
            
            toastType = .complete(.green)
            toastTitle = "Signed In"
            toastSubtitle = "\(greetings), \(username)"
            
            throw error
        }
        
        isToastShowing = true
        
        updateData()
    }
    
    func signOut() async throws {
        api.signOut()
    }
    
    // MARK: - Player Web Socket
    
    func createSession(playlistID: Int, shuffle: Bool) async throws {
        try await api.playerWebSocket?.send(PlayerMessage(
            event: .createSession,
            payload: .createSession(
                playlist_id: playlistID,
                shuffle: shuffle
            )
        ))
    }
    
    var playerProgressTimeObserver: Any?
    var playerSyncTimeObserver: Any?
    var playerItemStatusObserver: Any?
    
    func backward() async throws {
        guard
            let playerSessionID = currentPlayerContent?.playerSessionID,
            let currentSessionTrackID = currentPlayerContent?.sessionTrackID,
            !queuedPlayerContent.isEmpty
        else {
            throw .api.custom(errorDescription: "")
        }
        
        player.pause()
        
        currentPlayerContent = queuedPlayerContent.removeLast()
        
        playCurrentTrack()
        
        if let playerWebSocket {
            try await playerWebSocket.send(PlayerMessage(
                event: .playPreviousTrack,
                payload: .playPreviousTrack(
                    player_session_id: playerSessionID,
                    track_id: currentSessionTrackID
                )
            ))
        } else if let eventWebSocket {
            try await eventWebSocket.send(EventMessage(
                event: .playPreviousTrack,
                payload: .playPreviousTrack(
                    player_session_id: playerSessionID,
                    track_id: currentSessionTrackID
                )
            ))
        }
    }
    
    func resume() async throws {
        guard
            let playerSessionID = currentPlayerContent?.playerSessionID,
            let currentSessionTrackID = currentPlayerContent?.sessionTrackID
        else {
            throw .api.custom(errorDescription: "")
        }
        
        playCurrentTrack()
        
        if let playerWebSocket {
            try await playerWebSocket.send(PlayerMessage(
                event: .resumeTrack,
                payload: .resumeTrack(
                    player_session_id: playerSessionID,
                    track_id: currentSessionTrackID
                )
            ))
        } else if let eventWebSocket {
            try await eventWebSocket.send(EventMessage(
                event: .resumeTrack,
                payload: .resumeTrack(
                    player_session_id: playerSessionID,
                    track_id: currentSessionTrackID
                )
            ))
        }
    }
    
    func pause() async throws {
        guard
            let playerSessionID = currentPlayerContent?.playerSessionID,
            let currentSessionTrackID = currentPlayerContent?.sessionTrackID
        else {
            throw .api.custom(errorDescription: "")
        }
        
        try await pauseCurrentTrack()
        
        if let playerWebSocket {
            try await playerWebSocket.send(PlayerMessage(
                event: .pauseTrack,
                payload: .pauseTrack(
                    player_session_id: playerSessionID,
                    track_id: currentSessionTrackID
                )
            ))
        } else if let eventWebSocket {
            try await eventWebSocket.send(EventMessage(
                event: .pauseTrack,
                payload: .pauseTrack(
                    player_session_id: playerSessionID,
                    track_id: currentSessionTrackID
                )
            ))
        }
    }
    
    func forward() async throws {
        guard
            let playerSessionID = currentPlayerContent?.playerSessionID,
            let currentSessionTrackID = currentPlayerContent?.sessionTrackID,
            !queuedPlayerContent.isEmpty
        else {
            throw .api.custom(errorDescription: "")
        }
        
        player.pause()
        
        currentPlayerContent = queuedPlayerContent.removeFirst()
        
        playCurrentTrack()
        
        if let playerWebSocket {
            try await playerWebSocket.send(PlayerMessage(
                event: .playNextTrack,
                payload: .playNextTrack(
                    player_session_id: playerSessionID,
                    track_id: currentSessionTrackID
                )
            ))
        } else if let eventWebSocket {
            try await eventWebSocket.send(EventMessage(
                event: .playNextTrack,
                payload: .playNextTrack(
                    player_session_id: playerSessionID,
                    track_id: currentSessionTrackID
                )
            ))
        }
    }
    
    func playTrack(sessionTrackID: Int) async throws {
        guard
            let playerSessionID = playerSession?.id
        else {
            throw .api.custom(errorDescription: "")
        }
        
        if let playerWebSocket {
            try await playerWebSocket.send(PlayerMessage(
                event: .playTrack,
                payload: .playTrack(
                    player_session_id: playerSessionID,
                    track_id: sessionTrackID
                )
            ))
        } else if let eventWebSocket {
            try await eventWebSocket.send(EventMessage(
                event: .playTrack,
                payload: .playTrack(
                    player_session_id: playerSessionID,
                    track_id: sessionTrackID
                )
            ))
        }
    }
    
    func delayPlayTrack(sessionTrackID: Int) async throws {
        guard
            let playerSessionID = playerSession?.id
        else {
            throw .api.custom(errorDescription: "")
        }
        
        if let playerWebSocket {
            try await playerWebSocket.send(PlayerMessage(
                event: .delayPlayTrack,
                payload: .delayPlayTrack(
                    player_session_id: playerSessionID,
                    track_id: sessionTrackID
                )
            ))
        } else if let eventWebSocket {
            try await eventWebSocket.send(EventMessage(
                event: .delayPlayTrack,
                payload: .delayPlayTrack(
                    player_session_id: playerSessionID,
                    track_id: sessionTrackID
                )
            ))
        }
    }
    
    func shuffle() async throws {
        guard
            let playerSessionID = currentPlayerContent?.playerSessionID,
            let currentSessionTrackID = currentPlayerContent?.sessionTrackID
        else {
            throw .api.custom(errorDescription: "")
        }
        
        do {
            if let playerWebSocket {
                try await playerWebSocket.send(PlayerMessage(
                    event: .shuffle,
                    payload: .shuffle(
                        player_session_id: playerSessionID,
                        track_id: currentSessionTrackID
                    )
                ))
            } else if let eventWebSocket {
                try await eventWebSocket.send(EventMessage(
                    event: .shuffle,
                    payload: .shuffle(
                        player_session_id: playerSessionID,
                        track_id: currentSessionTrackID
                    )
                ))
            }
        } catch {
            debugPrint(error)
        }
    }
    
    func subscribeToPlayer() {
        trackProgress = TrackProgress(
            value: 0,
            total: trackProgress.total,
            buffers: trackProgress.buffers
        )
        
        player.pause()
        playerState = .paused
        
        eventWebSocket?.close()
        eventWebSocket = nil
        
        playerWebSocket?.close()
        
        playerWebSocket = api.playerWebSocket
        
        if let playerWebSocket, !playerWebSocket.isSubscribed {
            playerWebSocket
                .onReceive { [unowned self] (message) in
                    debugPrint(message)
                    
                    switch message.payload {
                        
                    case .session(let playerSession):
                        Task { @MainActor in
                            self.playerSession = playerSession
                        }
                        
                    case .sessionChanged(let playerSession):
                        Task { @MainActor in
                            self.playerSession = playerSession
                        }
                        
                    default:
                        break
                    }
                }
        }
    }
    
    func subscribeToPlaylists() {
        playlistsWebSocket?.close()
        
        playlistsWebSocket = api.playlistsWebSocket
        
        if let playlistsWebSocket, !playlistsWebSocket.isSubscribed {
            playlistsWebSocket
                .onReceive { [unowned self] (message) in
                    switch message.payload {
                    case .playlistsChanged(let ownPlaylists):
                        Task {
                            try await saveOwnPlaylists(ownPlaylists)
                        }

                    default:
                        break
                    }
                }
        }
    }
    
    func subscribeToPlaylist(playlistID: Int) {
        playlistWebSocket?.close()
        
        playlistWebSocket = api.playlistWebSocket(playlistID: playlistID)
        
        if let playlistWebSocket, !playlistWebSocket.isSubscribed {
            playlistWebSocket
                .onReceive { [unowned self] (message) in
                    switch message.payload {
                    case .playlistChanged(let playlist):
                        Task {
                            if let playlistsIndex = playlists.firstIndex(where: {
                                $0.id == playlist.id
                            }) {
                                var playlists = playlists
                                
                                playlists[playlistsIndex] = playlist
                                
                                Task {
                                    try await savePlaylists(playlists)
                                }
                            }
                            
                            if let ownPlaylistsIndex = ownPlaylists.firstIndex(where: {
                                $0.id == playlist.id
                            }) {
                                var ownPlaylists = ownPlaylists
                                
                                ownPlaylists[ownPlaylistsIndex] = playlist
                                
                                Task {
                                    try await saveOwnPlaylists(ownPlaylists)
                                }
                            }
                        }
                        
                    default:
                        break
                    }
                }
        }
    }
    
    func subscribeToEvent(eventID: Int) {
        trackProgress = TrackProgress(
            value: 0,
            total: trackProgress.total,
            buffers: trackProgress.buffers
        )
        player.pause()
        playerState = .paused
        
        playerWebSocket?.close()
        playerWebSocket = nil
        
        eventWebSocket?.close()
        
        eventWebSocket = api.eventWebSocket(eventID: eventID)
        
        if let eventWebSocket, !eventWebSocket.isSubscribed {
            eventWebSocket
                .onReceive { [unowned self] (message) in
                    debugPrint(message)
                    
                    switch message.payload {
                    case .session(let playerSession):
                        Task { @MainActor in
                            self.playerSession = playerSession
                        }
                        
                    case .sessionChanged(let playerSession):
                        Task { @MainActor in
                            self.playerSession = playerSession
                        }
                        
                    default:
                        break
                    }
                }
        }
    }
    
    // MARK: - Player
    
    lazy var player = {
        let player = AVPlayer()
        
        MPRemoteCommandCenter.shared().playCommand.addTarget { event in
            Task {
                do {
                    try await self.resume()
                } catch {
                    self.playCurrentTrack()
                }
            }
            
            return .success
        }
        
        MPRemoteCommandCenter.shared().pauseCommand.addTarget { event in
            Task {
                do {
                    try await self.pause()
                } catch {
                    try await self.pauseCurrentTrack()
                }
            }
            
            return .success
        }
        
        MPRemoteCommandCenter.shared().nextTrackCommand.addTarget { event in
            Task {
                try await self.forward()
            }
            
            return .success
        }
        
        MPRemoteCommandCenter.shared()
            .previousTrackCommand.addTarget { event in
                Task.detached {
                    try await self.backward()
                }
                
                return .success
            }
        
        MPRemoteCommandCenter.shared()
            .changePlaybackPositionCommand.isEnabled = true
        
        MPRemoteCommandCenter.shared()
            .changePlaybackPositionCommand.addTarget { [weak self] event in
                guard
                    let self,
                    let changePlaybackPositionEvent = event as? MPChangePlaybackPositionCommandEvent
                else {
                    return .commandFailed
                }
                
                let time = changePlaybackPositionEvent.positionTime
                
                isLoadingProgress = true
                
                trackProgress = TrackProgress(
                    value: time,
                    total: self.trackProgress.total,
                    buffers: self.trackProgress.buffers
                )
                
                seek()
                
                return .success
            }
        
        return player
    }()
}
