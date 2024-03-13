//
//  ViewController.swift
//  VideoPlayer
//
//  Created by Raju Kumar on 02/03/24.
//

import UIKit
import Combine
import AVFoundation
import AVKit
import MediaPlayer

class ViewController: UIViewController {
    
    //MARK: - IBOutlets
    @IBOutlet weak var videoPlayerView: UIView!
    @IBOutlet weak var thumbnailImgVw: UIImageView!
    @IBOutlet weak var muteUnmuteBtn: UIButton!
    @IBOutlet weak var nextBtn: UIButton!
    @IBOutlet weak var previousBtn: UIButton!
    @IBOutlet weak var currentTimeLbl: UILabel!
    @IBOutlet weak var totalTimeLbl: UILabel!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var seekBar: UISlider!
    @IBOutlet weak var videoControlsView: UIView!
    @IBOutlet weak var videoControlButtonSV: UIStackView!
    @IBOutlet weak var playPauseBtn: UIButton!
    
    @IBOutlet weak var airPlayContainerView: UIView!
    
    private var videoURLs: [Video] = []
    var currentPlayingIndex: Int = 0
    var isPlaying: Bool = false
    var feedbackView: UIView!
    
    private var hideControlsTimer: Timer?
    private var subscribers = Set<AnyCancellable>()
    private var subscriptions = Set<AnyCancellable>()
    
    //MARK: - Lifecycles
    override func viewDidLoad() {
        super.viewDidLoad()
        setupFeedbackView()
        setupAirPlayButton()
        videoData()
        setupVideoPlayer()
        setupSubscribers()
        self.setupGestureRecognizers()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        hideControlsTimer?.invalidate()
    }
    
    
    //MARK: - Functions
    private func setupVideoPlayer() {
        guard !videoURLs.isEmpty else { return }
        let currentVideo = videoURLs[currentPlayingIndex]
        
        VideoPlayerManager.shared.setVideoPlayer(with: currentVideo.url, title: currentVideo.title, view: self.videoPlayerView, autoPlay: self.isPlaying)
        activityIndicator.startAnimating()
    }
    
    func setupFeedbackView() {
        feedbackView = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        feedbackView.layer.backgroundColor = UIColor.white.withAlphaComponent(0.7).cgColor
        feedbackView.layer.cornerRadius = 50
        feedbackView.center = videoPlayerView.center
        feedbackView.isHidden = true // Initially hidden
        videoPlayerView.addSubview(feedbackView)
    }
    
    func setupGestureRecognizers() {
        // Setup for videoPlayerView
        setupGesturesForView(view: videoPlayerView)
        
        // Setup for videoControlsView
        setupGesturesForView(view: videoControlsView)
    }
    
    func setupGesturesForView(view: UIView) {
        // Double Tap Gesture
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTapGesture)
        
        // Single Tap Gesture
        let singleTapGesture = UITapGestureRecognizer(target: self, action: #selector(videoPlayerTapped))
        singleTapGesture.require(toFail: doubleTapGesture) // Only trigger single tap if double tap fails
        view.addGestureRecognizer(singleTapGesture)
    }
    
    
    func loadThumbnail(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else { return }
            
            DispatchQueue.main.async {
                self.thumbnailImgVw.image = UIImage(data: data)
            }
        }.resume()
    }
    
    
    private func setupSubscribers() {
        VideoPlayerManager.shared.playbackProgressPublisher.sink { [weak self] progress in
            self?.seekBar.value = progress
        }.store(in: &subscribers)
        
        VideoPlayerManager.shared.playbackDidFinishPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else {return}
                self.playPauseBtn.isSelected = false
            }.store(in: &subscribers)
        
        VideoPlayerManager.shared.isPlayingPublisher.sink { [weak self] isPlaying in
            self?.playPauseBtn.isSelected = isPlaying
            self?.isPlaying = isPlaying
        }.store(in: &subscribers)
        
        VideoPlayerManager.shared.currentTimePublisher.sink { [weak self] currentTime in
            let formattedTime = self?.formatTimeFor(seconds: currentTime)
            self?.currentTimeLbl.text = formattedTime
        }.store(in: &subscribers)
        
        VideoPlayerManager.shared.totalDurationPublisher.sink { [weak self] totalTime in
            DispatchQueue.main.async {
                self?.totalTimeLbl.text = totalTime
            }
        }.store(in: &subscribers)
        
        VideoPlayerManager.shared.loadingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                self?.videoControlButtonSV.isHidden = isLoading
                if isLoading {
                    self?.activityIndicator.startAnimating()
                } else {
                    self?.activityIndicator.stopAnimating()
                }
            }
            .store(in: &subscribers)
        
        VideoPlayerManager.shared.nextTrackPublisher
            .sink { [weak self] _ in
                self?.playNextTrack()
            }
            .store(in: &subscriptions)
        
        VideoPlayerManager.shared.previousTrackPublisher
            .sink { [weak self] _ in
                self?.playPreviousTrack()
            }
            .store(in: &subscriptions)
        
        VideoPlayerManager.shared.videoTitlePublisher
            .sink { [weak self] title in
                VideoPlayerManager.shared.configureNowPlayingInfo(withTitle: title)
            }
            .store(in: &subscriptions)
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
    
    private func resetControls() {
        self.currentTimeLbl.text = "-"
        self.totalTimeLbl.text = "-"
        self.seekBar.value = 0.0
        self.muteUnmuteBtn.isSelected = VideoPlayerManager.shared.isMuted
        self.playPauseBtn.isSelected = VideoPlayerManager.shared.isPlaying
        self.videoControlButtonSV.isHidden = true
    }
    
    
    func videoData() {
        let titles = ["Video 1", "Video 2", "video 3", "video 4", "video 5", "video 6", "video 7", "video 8",  "video 9"]
        let thumbNails =  [
            "https://storage.googleapis.com/gtv-videos-bucket/sample/images/ElephantsDream.jpg",
            "https://storage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerBlazes.jpg",
            "https://storage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerEscapes.jpg",
            "https://storage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerFun.jpg",
            "https://storage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerJoyrides.jpg",
            "https://storage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerMeltdowns.jpg",
            "https://storage.googleapis.com/gtv-videos-bucket/sample/images/BigBuckBunny.jpg",
            "https://storage.googleapis.com/gtv-videos-bucket/sample/images/SubaruOutbackOnStreetAndDirt.jpg",
            "https://storage.googleapis.com/gtv-videos-bucket/sample/images/TearsOfSteel.jpg"
        ]
        
        let videos = [
            "https://www.youtube.com/watch?v=sNpy-C-VxYY",
            "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
            "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4",
            "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4",
            "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4",
            "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4",
            "https://storage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
            "https://storage.googleapis.com/gtv-videos-bucket/sample/SubaruOutbackOnStreetAndDirt.mp4",
            "https://storage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4"
        ]
        
        // Ensure that all arrays have the same count
        guard titles.count == thumbNails.count, titles.count == videos.count else {
            fatalError("Titles, thumbnails, and videos arrays have different counts")
        }
        
        // Clear the videoURLs array if you're reinitializing data
        self.videoURLs.removeAll()
        
        // Iterate through one array and use the index to access elements in the other arrays
        for (index, title) in titles.enumerated() {
            let thumb = thumbNails[index]
            let video = videos[index]
            let videoObject = Video(title: title, url: video, thumb: thumb)
            self.videoURLs.append(videoObject)
        }
    }
    
    func showControls() {
        // Invalidate the timer to prevent it from hiding the controls while they are being interacted with
        hideControlsTimer?.invalidate()
        
        UIView.animate(withDuration: 0.5) {
            self.videoControlsView.alpha = 1.0
        }
        
        // Restart the timer to hide the controls after 10 seconds
        startHideControlsTimer()
    }
    
    @objc func hideControls() {
        UIView.animate(withDuration: 0.5) {
            self.videoControlsView.alpha = 0.0
        }
    }
    
    func startHideControlsTimer() {
        hideControlsTimer = Timer.scheduledTimer(timeInterval: 10, target: self, selector: #selector(self.hideControls), userInfo: nil, repeats: false)
    }
    
    //MARK: - IbActions
    @IBAction func onClickPlayPause(_ sender: Any) {
        if VideoPlayerManager.shared.isPlaying {
            VideoPlayerManager.shared.pause()
        } else {
            VideoPlayerManager.shared.play()
            // Start the timer to hide the controls when the video starts playing
            startHideControlsTimer()
        }
        self.playPauseBtn.isSelected = VideoPlayerManager.shared.isPlaying
    }
    
    @IBAction func onClickNext(_ sender: Any) {
        if currentPlayingIndex < videoURLs.count - 1 {
            currentPlayingIndex += 1
            setupVideoPlayer()
            self.resetControls()
        }
    }
    
    @IBAction func onClickPrevious(_ sender: Any) {
        if currentPlayingIndex > 0 {
            currentPlayingIndex -= 1
            setupVideoPlayer()
            self.resetControls()
        }
    }
    
    @IBAction func onClickMuteUnmute(_ sender: Any) {
        VideoPlayerManager.shared.toggleMute()
        muteUnmuteBtn.isSelected = VideoPlayerManager.shared.isMuted
    }
    
    @IBAction func seekBarValueChanged(_ sender: UISlider) {
        guard let player = VideoPlayerManager.shared.currentPlayer,
              let duration = player.currentItem?.duration else { return }
        let totalSeconds = CMTimeGetSeconds(duration)
        let value = Float64(seekBar.value) * totalSeconds
        let seekTime = CMTime(value: Int64(value), timescale: 1)
        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: { _ in
            // Optionally handle completion.
        })
    }
    
    func playNextTrack() {
        if currentPlayingIndex < videoURLs.count - 1 {
            currentPlayingIndex += 1
            let nextURL = videoURLs[currentPlayingIndex]
            VideoPlayerManager.shared.setVideoPlayer(with: nextURL.url, title: nextURL.title, view: videoPlayerView)
        }
    }

    func playPreviousTrack() {
        // Similar logic for playing the previous track
        if currentPlayingIndex > 0 {
            currentPlayingIndex -= 1
            let previousURL = videoURLs[currentPlayingIndex]
            VideoPlayerManager.shared.setVideoPlayer(with: previousURL.url, title: previousURL.title, view: videoPlayerView)
        }
    }
    
    @objc func videoPlayerTapped() {
        // Toggle visibility based on the current alpha value
        if videoControlsView.alpha == 0.0 {
            showControls()
        } else {
            hideControls()
        }
    }
    
    
    @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: gesture.view)
        let isForward = location.x > gesture.view!.bounds.midX // Assuming right half is forward
        
        // Show visual feedback
        showFeedbackAnimation(at: location, isForward: isForward)
        
        // Adjust the jump interval based on tap count
        let jumpInterval = 10 // For simplicity, jumping by 10 seconds for each double tap
        
        if isForward {
            VideoPlayerManager.shared.forward(seconds: jumpInterval)
        } else {
            VideoPlayerManager.shared.backward(seconds: jumpInterval)
        }
    }
    
    func showFeedbackAnimation(at location: CGPoint, isForward: Bool) {
        // Ensure feedbackView is setup (setupFeedbackView() should have been called in viewDidLoad)
        
        // Update the feedbackView's position and content based on the action (forward or backward)
        feedbackView.center = location
        // You can also change the feedbackView's content or appearance based on isForward
        
        // Make feedbackView visible and animate
        feedbackView.isHidden = false
        feedbackView.alpha = 0
        UIView.animate(withDuration: 0.3, animations: {
            self.feedbackView.alpha = 1
        }) { _ in
            UIView.animate(withDuration: 0.3, delay: 0.5, options: [], animations: {
                self.feedbackView.alpha = 0
            }, completion: { _ in
                self.feedbackView.isHidden = true
            })
        }
    }
    
    func setupAirPlayButton() {
        let routePickerView = AVRoutePickerView()
        routePickerView.translatesAutoresizingMaskIntoConstraints = false
        airPlayContainerView.addSubview(routePickerView)
        
        // Constraints to make the AVRoutePickerView fill its container
        NSLayoutConstraint.activate([
            routePickerView.topAnchor.constraint(equalTo: airPlayContainerView.topAnchor),
            routePickerView.bottomAnchor.constraint(equalTo: airPlayContainerView.bottomAnchor),
            routePickerView.leadingAnchor.constraint(equalTo: airPlayContainerView.leadingAnchor),
            routePickerView.trailingAnchor.constraint(equalTo: airPlayContainerView.trailingAnchor),
        ])
        
        // Customizing the AVRoutePickerView's appearance
        routePickerView.activeTintColor = .systemBlue // Active state tint
        routePickerView.tintColor = .gray // Default tint color
        // For a custom button style, set routePickerView.prioritizesVideoDevices = true or false based on your needs
    }
}

struct Video {
    let title: String
    let url: String
    let thumb: String
}
