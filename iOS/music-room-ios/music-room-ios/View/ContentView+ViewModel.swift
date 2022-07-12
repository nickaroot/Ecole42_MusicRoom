//
//  ContentView+ViewModel.swift
//  music-room-ios
//
//  Created by Nikita Arutyunov on 27.06.2022.
//

import SwiftUI
import PINRemoteImage
import AVFoundation

extension ContentView {
    
    @MainActor
    class ViewModel: ObservableObject {
        
        weak var api: API!
        
        // MARK: - Interface State
        
        enum InterfaceState {
            case player
            
            case playlist
            
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
        
        // MARK: - Library State
        
        enum LibraryState {
            case ownPlaylists, playlists, tracks
        }
        
        @Published
        var libraryState = LibraryState.ownPlaylists
        
        // MARK: - Shuffle State
        
        enum ShuffleState {
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
        var shuffleState = ShuffleState.off
        
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
        
        // MARK: - Image Manager
        
        enum ImageManager {
            static func cachedImage(_ trackName: String) -> UIImage? {
                guard
                    let pinCache = PINRemoteImageManager.shared().pinCache
                else {
                    return nil
                }
                
                let memoryCachedImage = pinCache.memoryCache.object(forKey: trackName) as? UIImage
                
                if let memoryCachedImage = memoryCachedImage {
                    return memoryCachedImage
                }
                
                guard
                    let imageData = pinCache.diskCache.object(forKey: trackName) as? NSData,
                    let image = UIImage(data: Data(imageData))
                else {
                    return nil
                }
                
                if memoryCachedImage == nil {
                    pinCache.memoryCache.setObjectAsync(image, forKey: trackName)
                }
                
                return image
            }
            
            static func downloadImage(_ trackName: String, url: URL) async throws -> UIImage {
                let downloadedImage: UIImage = try await withCheckedThrowingContinuation { continuation in
                    PINRemoteImageManager.shared().downloadImage(with: url) { result in
                        guard
                            let image = result.image
                        else {
                            return continuation.resume(throwing: NSError())
                        }
                        
                        return continuation.resume(returning: image)
                    }
                }
                
                guard
                    let pinCache = PINRemoteImageManager.shared().pinCache
                else {
                    return downloadedImage
                }
                
                await pinCache.memoryCache.setObjectAsync(downloadedImage, forKey: trackName)
                
                guard
                    let pngImageData = downloadedImage.pngData()
                else {
                    return downloadedImage
                }
                
                await pinCache.diskCache.setObjectAsync(NSData(data: pngImageData), forKey: trackName)
                
                return downloadedImage
            }
        }
        
        // MARK: Interface Constants
        
        var placeholderTitle = "Not Playing"
        
        let primaryControlsColor = Color.primary
        
        let secondaryControlsColor = Color.primary.opacity(0.55)
        
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
        
        var playerArtworkWidth: CGFloat?
        
        @Published
        var animatingPlayerState = false
        
        func updatePlayerArtworkWidth(_ geometry: GeometryProxy) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                self.playerArtworkWidth = geometry.size.width
            }
        }
        
        var artworkPlaceholder = (
            backgroundColor: Color(red: 0.33, green: 0.325, blue: 0.349),
            foregroundColor: Color(red: 0.462, green: 0.458, blue: 0.474)
        )
        
        @Published
        var artworkPrimaryColor = Color(red: 0.33, green: 0.325, blue: 0.349)
        
        let playlistArtworkWidth = CGFloat(64)
        
        let playlistQueueArtworkWidth = CGFloat(48)
        
        var artworkProxyPrimaryColor: Color?
        
        func cachedArtworkImage(_ trackName: String, shouldPickColor: Bool = false) -> UIImage? {
            guard
                let cachedImage = ImageManager.cachedImage(trackName)
            else {
                return nil
            }
            
            if shouldPickColor {
                setArtworkColor(artworkColor(cachedImage))
            }
            
            return cachedImage
        }
        
        func artworkColor(_ uiImage: UIImage) -> Color {
            guard
                let inputImage = CIImage(image: uiImage)
            else {
                return artworkPlaceholder.backgroundColor
            }
            
            let extentVector = CIVector(
                x: inputImage.extent.origin.x,
                y: inputImage.extent.origin.y,
                z: inputImage.extent.size.width,
                w: inputImage.extent.size.height
            )
            
            guard
                let filter = CIFilter(
                    name: "CIAreaAverage",
                    parameters: [
                        kCIInputImageKey: inputImage,
                        kCIInputExtentKey: extentVector,
                    ]
                ),
                let outputImage = filter.outputImage
            else {
                return artworkPlaceholder.backgroundColor
            }
            
            var bitmap = [UInt8](repeating: 0, count: 4)
            
            let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
            
            context.render(
                outputImage,
                toBitmap: &bitmap,
                rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: nil
            )
            
            let uiColor = UIColor(
                red: CGFloat(bitmap[0]) / 255,
                green: CGFloat(bitmap[1]) / 255,
                blue: CGFloat(bitmap[2]) / 255,
                alpha: CGFloat(bitmap[3]) / 255
            )
            
            return Color(uiColor: uiColor)
        }
        
        func setArtworkColor(_ color: Color) {
            guard color != artworkPrimaryColor else { return }
            
            artworkProxyPrimaryColor = nil
            
            DispatchQueue.main.async { [weak self] in
                withAnimation(.easeOut(duration: 0.75)) {
                    self?.artworkProxyPrimaryColor = color
                    self?.artworkPrimaryColor = color
                }
            }
        }
        
        @Published
        var downloadedArtworks = [String: UIImage]()
        
        func processArtwork(
            trackName: String,
            url: URL?,
            shouldChangeColor: Bool = false
        ) {
            func changeColor(by uiImage: UIImage) {
                if shouldChangeColor {
                    setArtworkColor(artworkColor(uiImage))
                }
            }
            
            guard
                let cachedImage = ImageManager.cachedImage(trackName)
            else {
                guard
                    let url = url
                else {
                    return
                }
                
                Task {
                    let image = try await ImageManager.downloadImage(trackName, url: url)
                    
                    await MainActor.run { [weak self] in
                        self?.downloadedArtworks[trackName] = image
                    }
                }
                
                return
            }
            
            changeColor(by: cachedImage)
        }
        
        var artworkScale: CGFloat {
            guard
                let playerArtworkWidth = playerArtworkWidth
            else {
                return .zero
            }
            
            switch interfaceState {
            case .player, .library:
                return playlistArtworkWidth / playerArtworkWidth
                
            case .playlist:
                return playerArtworkWidth / playlistArtworkWidth
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
                    colors: [
                        UIColor(displayP3Red: 0.33, green: 0.325, blue: 0.349, alpha: 1),
                        UIColor(displayP3Red: 0.33, green: 0.325, blue: 0.349, alpha: 1),
                    ]
                )
            }
        )?
            .withRenderingMode(.alwaysOriginal) ?? UIImage()
        
        // MARK: - Track Progress
        
        struct TrackProgress {
            let value: Double
            
            let total: Double
        }
        
        @Published
        var trackProgress = TrackProgress(value: 0, total: 0)
        
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
                    try await updateTracks()
                } catch {
                    debugPrint(error)
                }
            }
            
            Task {
                do {
                    try await updatePlayerSession()
                } catch {
                    debugPrint(error)
                }
            }
            
            subscribeToPlayer()
            subscribeToPlaylists()
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
        
        // MARK: - Tracks
        
        @Published
        var tracks = [Track]()
        
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
                withAnimation {
                    currentSessionTrack = playerSession?.trackQueue.first
                    
                    queuedTracks = {
                        playerSession?
                            .trackQueue
                            .dropFirst()
                            .map {
                                track(byID: $0.track) ?? Track(name: "Unknown", file: "", duration: 0)
                            } ?? []
                    }()
                    
                    switch playerSession?.mode {
                        
                    case .normal:
                        repeatState = .off
                        
                    case .repeat:
                        repeatState = .on
                        
                    default:
                        break
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
        
        @Published
        var currentSessionTrack: SessionTrack? {
            didSet {
                currentTrack = {
                    guard
                        let currentTrackID = currentSessionTrack?.track
                    else {
                        return nil
                    }
                    
                    return track(byID: currentTrackID)
                }()
                
                let currentSessionTrackProgressValue = currentSessionTrack?.progress
                let currentTrackDuration = currentTrack?.duration
                
                let progressValue = ((currentSessionTrackProgressValue ?? 0) as NSDecimalNumber)
                    .doubleValue
                
                let progressTotal = ((currentTrackDuration ?? 0) as NSDecimalNumber)
                    .doubleValue
                
                let trackProgress = TrackProgress(
                    value: progressValue,
                    total: progressTotal
                )
                
                self.trackProgress = trackProgress
                
                guard
                    let currentSessionTrack = currentSessionTrack
                else {
                    return
                }
                
                switch currentSessionTrack.state {
                    
                case .paused, .stopped:
                    animatingPlayerState.toggle()
                    
                    playerState = .paused
                    
                case .playing:
                    animatingPlayerState.toggle()
                    
                    playerState = .playing
                    
                default:
                    break
                }
            }
        }
        
        @Published
        var currentTrack: Track?
        
        var queuedTracks = [Track]()
        
        // MARK: - Actions
        
        var isAuthorized: Bool {
            api.isAuthorized
        }
        
        func auth(_ username: String, _ password: String) async throws {
            _ = try await api.authRequest(
                TokenObtainPairModel(
                    username: username,
                    password: password
                )
            )
            
            updateData()
        }
        
        func signOut() async throws {
            api.signOut()
        }
        
        // MARK: - Player WebSocket
        
        func createSession(playlistID: Int) async throws {
            try await api.playerWebSocket?.send(PlayerMessage(
                event: .createSession,
                payload: .createSession(
                    playlist_id: playlistID,
                    shuffle: {
                        switch shuffleState {
                        case .off:
                            return false
                            
                        case .on:
                            return true
                        }
                    }()
                )
            ))
        }
        
        private func playCurrentTrack() {
            guard
                let currentTrackFile = self.currentTrack?.file
                    .replacingOccurrences(of: "http://", with: "https://"),
                let currentTrackURL = URL(string: currentTrackFile)
            else {
                return
            }
            
            let playerItem = AVPlayerItem(url: currentTrackURL)
            
            player.replaceCurrentItem(with: playerItem)
            
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback)
            } catch {
                debugPrint(error.localizedDescription)
            }
            
            player.play()
            
            player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC)),
                queue: .main
            ) { cmTime in
                let value = CMTimeGetSeconds(cmTime)
                let total = NSDecimalNumber(decimal: self.currentTrack?.duration ?? 0).doubleValue
                
                withAnimation {
                    self.trackProgress = TrackProgress(value: value, total: total)
                }
                
                guard
                    let sessionID = self.playerSession?.id
                else {
                    return
                }
                
                Task {
                    try await self.api.playerWebSocket?.send(
                        PlayerMessage(
                            event: .syncTrack,
                            payload: .syncTrack(
                                player_session_id: sessionID,
                                progress: Int(value)
                            )
                        )
                    )
                }
            }
        }
        
        func backward() async throws {
            guard
                let playerSessionID = playerSession?.id,
                let currentTrackID = currentTrack?.id // TODO: Check CurrentTrack or SessionTrack
            else {
                throw .api.custom(errorDescription: "")
            }
            
            try await api.playerWebSocket?.send(PlayerMessage(
                event: .playPreviousTrack,
                payload: .playPreviousTrack(
                    player_session_id: playerSessionID,
                    track_id: currentTrackID
                )
            ))
        }
        
        func resume() async throws {
            guard
                let playerSessionID = playerSession?.id,
                let currentTrackID = currentTrack?.id // TODO: Check CurrentTrack or SessionTrack
            else {
                throw .api.custom(errorDescription: "")
            }
            
            playCurrentTrack()
            
            _ = try await api.playerWebSocket?.send(PlayerMessage(
                event: .resumeTrack,
                payload: .resumeTrack(
                    player_session_id: playerSessionID,
                    track_id: currentTrackID
                )
            ))
        }
        
        func pause() async throws {
            guard
                let playerSessionID = playerSession?.id,
                let currentTrackID = currentTrack?.id // TODO: Check CurrentTrack or SessionTrack
            else {
                throw .api.custom(errorDescription: "")
            }
            
            player.pause()
            
            try await api.playerWebSocket?.send(PlayerMessage(
                event: .pauseTrack,
                payload: .pauseTrack(
                    player_session_id: playerSessionID,
                    track_id: currentTrackID
                )
            ))
        }
        
        func forward() async throws {
            guard
                let playerSessionID = playerSession?.id,
                let currentTrackID = currentTrack?.id // TODO: Check CurrentTrack or SessionTrack
            else {
                throw .api.custom(errorDescription: "")
            }
            
            player.pause()
            
            currentTrack = queuedTracks.removeFirst()
            
            playCurrentTrack()
            
            try await api.playerWebSocket?.send(PlayerMessage(
                event: .playNextTrack,
                payload: .playNextTrack(
                    player_session_id: playerSessionID,
                    track_id: currentTrackID
                )
            ))
        }
        
        func playTrack(trackID: Int) async throws {
            guard
                let playerSessionID = playerSession?.id
            else {
                throw .api.custom(errorDescription: "")
            }
            
            try await api.playerWebSocket?.send(PlayerMessage(
                event: .playTrack,
                payload: .playTrack(
                    player_session_id: playerSessionID,
                    track_id: trackID
                )
            ))
        }
        
        func shuffle() async throws {
            guard
                let playerSessionID = playerSession?.id,
                let currentTrackID = currentTrack?.id // TODO: Check CurrentTrack or SessionTrack
            else {
                throw .api.custom(errorDescription: "")
            }
            
            try await api.playerWebSocket?.send(PlayerMessage(
                event: .shuffle,
                payload: .shuffle(
                    player_session_id: playerSessionID,
                    track_id: currentTrackID
                )
            ))
        }
        
        func subscribeToPlayer() {
            if let playerWebSocket = api.playerWebSocket, !playerWebSocket.isSubscribed {
                playerWebSocket
                    .onReceive { [unowned self] (message) in
                        switch message.payload {
                            
                        case .session(let playerSession):
                            if let playerSession = playerSession {
                                print(playerSession.trackQueue.map { $0.id! })
                            }
                            
                            Task { [unowned self] in
                                await MainActor.run { [unowned self] in
                                    self.playerSession = playerSession
                                }
                            }
                            
                        case .sessionChanged(let playerSession):
                            if let playerSession = playerSession {
                                print(playerSession.trackQueue.map { $0.id! })
                            }
                            
                            Task { [unowned self] in
                                await MainActor.run { [unowned self] in
                                    self.playerSession = playerSession
                                }
                            }
                            
                        default:
                            break
                        }
                    }
            }
        }
        
        func subscribeToPlaylists() {
            if let playlistsWebSocket = api.playlistsWebSocket, !playlistsWebSocket.isSubscribed {
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
            if let playlistWebSocket = api.playlistWebSocket(playlistID: playlistID), !playlistWebSocket.isSubscribed {
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
        
        // MARK: - Player
        
        lazy var player = {
            let player = AVPlayer()
            
            return player
        }()
    }
}
