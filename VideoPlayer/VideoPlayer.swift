//
//  VideoPlayer.swift
//  VideoPlayer
//
//  Created by Raju Kumar on 02/03/24.
//

import Foundation
import UIKit
import AVFoundation
import AVKit
import Combine
import MediaPlayer

class VideoPlayerManager {
    static let shared = VideoPlayerManager()
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var playerLayer: AVPlayerLayer?
    
    // Subscribers and Publishers
    private var appLifeCycleNotificationSubscriber: AnyCancellable?
    var playbackProgressPublisher = PassthroughSubject<Float, Never>()
    var playbackDidFinishPublisher = PassthroughSubject<Void, Never>()
    var isPlayingPublisher = CurrentValueSubject<Bool, Never>(false)
    var currentTimePublisher = PassthroughSubject<Double, Never>()
    var totalDurationPublisher = PassthroughSubject<String, Never>()
    var loadingPublisher = CurrentValueSubject<Bool, Never>(false)
    var nextTrackPublisher = PassthroughSubject<Void, Never>()
    var previousTrackPublisher = PassthroughSubject<Void, Never>()
    var videoTitlePublisher = PassthroughSubject<String, Never>()
    
    private var playerItemStatusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var playerItemBufferObserver: NSKeyValueObservation?
    
    private var timeObserverToken: Any?
    
    private var originalVolume: Float = 0.5
    private var currentTitle = ""
    
    var currentPlayer: AVPlayer? {
        return player
    }
    
    var isMuted: Bool {
        return player?.volume == 0
    }
    
    var isPlaying: Bool {
        return player?.rate != 0 && player?.error == nil
    }
    
    private init() {
        subscribeToAppLifeCycleNotification()
    }
    
    deinit {
        cleanup()
    }
    
    func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session category. Error: \(error)")
        }
    }

    
    func setVideoPlayer(with urlString: String, title: String, view: UIView, autoPlay: Bool = false) {
        cleanup() // Clean up before setting a new player
        guard let url = URL(string: urlString) else { return }
        self.playerItem = AVPlayerItem(url: url)
        self.player?.allowsExternalPlayback = true
        self.player = AVPlayer(playerItem: self.playerItem)
        self.playerLayer = AVPlayerLayer(player: self.player)
        self.playerLayer?.videoGravity = .resize
        
        if let playerLayer = self.playerLayer {
            playerLayer.frame = view.frame
            view.layer.addSublayer(playerLayer)
            view.layoutIfNeeded()
        }
        self.originalVolume = player?.volume ?? 0.5
        setupPlayerObservers()
        self.currentTitle = title
        videoTitlePublisher.send(title)
        configureNowPlayingInfo(withTitle: title)
        if autoPlay {
            play()
        }
    }
    
    private func setupPlayerObservers() {
        
        // Observe time changes
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main, using: { [weak self] time in
            guard let duration = self?.player?.currentItem?.duration.seconds, duration > 0 else { return }
            let progress = Float(time.seconds / duration)
            self?.playbackProgressPublisher.send(progress)
        })
        
        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), queue: .main, using: { [weak self] time in
            let currentTimeSeconds = CMTimeGetSeconds(time)
            self?.currentTimePublisher.send(currentTimeSeconds)
        })
        
        playerItemStatusObserver = playerItem?.observe(\.status, options: [.new, .old], changeHandler: { [weak self] (playerItem, change) in
            guard let self else {return}
                DispatchQueue.main.async {
                    switch playerItem.status {
                        // Video is ready to play, hide loader
                    case .readyToPlay:
                        if let duration = self.player?.currentItem?.duration {
                            let totalSeconds = CMTimeGetSeconds(duration)
                            let totalTimeString = self.formatTimeFor(seconds: totalSeconds)
                            self.totalDurationPublisher.send(totalTimeString)
                        }
                        self.loadingPublisher.send(false)
                    case .unknown, .failed:
                        // Video is not ready, show loader
                        self.loadingPublisher.send(true)
                    @unknown default:
                        break
                    }
                }
            })

            playerItemBufferObserver = playerItem?.observe(\.isPlaybackLikelyToKeepUp, options: [.new, .old], changeHandler: { [weak self] (playerItem, change) in
                guard let self else {return}
                DispatchQueue.main.async {
                    
                    if playerItem.isPlaybackLikelyToKeepUp {
                        // Playback is smooth, hide loader
                        self.loadingPublisher.send(false)
                    } else {
                        // Buffering, show loader
                        self.loadingPublisher.send(true)
                    }
                }
            })
        
        rateObserver = player?.observe(\.rate, options: [.new], changeHandler: { [weak self] (player, value) in
            guard let self else {return}
            if player.rate == 0 {
                if let currentitemEndTime = player.currentItem?.duration,
                   currentitemEndTime == player.currentTime() {
                    self.playbackDidFinishPublisher.send()
                }else {
                    self.isPlayingPublisher.send(false)
                }
            }else {
                self.isPlayingPublisher.send(false)
            }
        })
        
    }
    
    private func formatTimeFor(seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        // Check if the total time includes hours
        if seconds >= 3600 {
            formatter.allowedUnits = [.hour, .minute, .second]
        } else {
            formatter.allowedUnits = [.minute, .second]
        }
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: TimeInterval(seconds)) ?? "00:00"
    }

    
    private func subscribeToAppLifeCycleNotification() {
        appLifeCycleNotificationSubscriber = NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification).sink(receiveValue: { [weak self] _ in
            self?.pause()
        })
    }
    
    func play() {
        self.configureAudioSession()
        configureNowPlayingInfo(withTitle: currentTitle)
        setupRemoteTransportControls()
        player?.play()
        isPlayingPublisher.send(true)
    }
    
    func pause() {
        player?.pause()
        isPlayingPublisher.send(false)
    }
    
    func toggleMute() {
        guard let player = self.player else { return }
        if player.volume > 0 {
            originalVolume = player.volume
            player.volume = 0
        } else {
            player.volume = originalVolume
        }
    }
    
    private func cleanup() {
        if let timeObserverToken = timeObserverToken {
            player?.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }
        player?.pause()
        playerLayer = nil
        player = nil
        playerItem = nil
        playerLayer?.removeFromSuperlayer()
        NotificationCenter.default.removeObserver(self)
        appLifeCycleNotificationSubscriber?.cancel()
        playerItemStatusObserver?.invalidate()
        playerItemBufferObserver?.invalidate()
        try? AVAudioSession.sharedInstance().setActive(false)
    }
    
    func forward(seconds: Int) {
        guard let player = currentPlayer, let duration = player.currentItem?.duration else { return }
        let playerCurrentTime = CMTimeGetSeconds(player.currentTime())
        let newTime = playerCurrentTime + Double(seconds)
        
        if newTime < CMTimeGetSeconds(duration) {
            let time: CMTime = CMTimeMake(value: Int64(newTime * 1000), timescale: 1000)
            player.seek(to: time)
        }
    }

    func backward(seconds: Int) {
        let playerCurrentTime = CMTimeGetSeconds(currentPlayer?.currentTime() ?? CMTime.zero)
        var newTime = playerCurrentTime - Double(seconds)
        
        if newTime < 0 {
            newTime = 0
        }
        
        let time: CMTime = CMTimeMake(value: Int64(newTime * 1000), timescale: 1000)
        currentPlayer?.seek(to: time)
    }
    
    func configureNowPlayingInfo(withTitle title: String) {
        var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
           nowPlayingInfo[MPMediaItemPropertyTitle] = title
        
        if let duration = player?.currentItem?.duration.seconds, !duration.isNaN {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player?.currentItem?.currentTime().seconds
        }
        
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = player?.rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    
    func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [unowned self] event in
            if !self.isPlaying {
                self.play()
                self.configureNowPlayingInfo(withTitle: self.currentTitle)
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.pauseCommand.addTarget { [unowned self] event in
            if self.isPlaying {
                self.pause()
                self.configureNowPlayingInfo(withTitle: self.currentTitle)
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.nextTrackPublisher.send()
            return .success
        }
        
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.previousTrackPublisher.send()
            return .success
        }
        
    }
}
