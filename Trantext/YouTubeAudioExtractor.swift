import Foundation
import AVFoundation
import WebKit

// YouTube 오디오 추출을 위한 클래스
class YouTubeAudioExtractor: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var videoID: String = ""
    private var audioPlayer: AVPlayer?
    private var audioCaptureTimer: Timer?
    private var captureSession: AVCaptureSession?
    private var transcriptionService: TranscriptionService?
    
    // 상태 콜백
    var onExtractionStarted: (() -> Void)?
    var onExtractionFailed: ((Error) -> Void)?
    var onAudioBufferCaptured: ((Data) -> Void)?
    
    init(transcriptionService: TranscriptionService) {
        super.init()
        self.transcriptionService = transcriptionService
        
        // 웹뷰 설정 - JavaScript 이벤트 캡처용
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsInlineMediaPlayback = true
        
        // 자바스크립트 인터페이스 추가
        let contentController = WKUserContentController()
        contentController.add(self, name: "audioHandler")
        configuration.userContentController = contentController
        
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView?.navigationDelegate = self
        self.webView?.isHidden = true  // 숨김 처리
    }
    
    // YouTube 비디오 URL에서 오디오 추출 시작
    func extractAudio(from youtubeURL: String) {
        guard let videoID = extractVideoID(from: youtubeURL) else {
            onExtractionFailed?(NSError(domain: "YouTubeExtractor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid YouTube URL"]))
            return
        }
        
        self.videoID = videoID
        
        // HTML 페이지 로드 - 오디오만 추출하는 커스텀 플레이어
        let html = createYouTubePlayerHTML(videoID: videoID)
        webView?.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
        
        onExtractionStarted?()
        
        // 시스템 오디오 캡처 세션 설정
        setupAudioCaptureSession()
    }
    
    // YouTube URL에서 비디오 ID 추출
    private func extractVideoID(from url: String) -> String? {
        // 정규식 패턴으로 YouTube 비디오 ID 추출
        let patterns = [
            "(?<=v=)[^&#]+",                 // youtube.com/watch?v=ID
            "(?<=youtu.be/)[^&#/]+",         // youtu.be/ID
            "(?<=embed/)[^&#/?]+"            // youtube.com/embed/ID
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) {
                if let range = Range(match.range, in: url) {
                    return String(url[range])
                }
            }
        }
        
        // 직접 비디오 ID가 입력된 경우
        if url.rangeOfCharacter(from: CharacterSet(charactersIn: "/?&=")) == nil && url.count == 11 {
            return url
        }
        
        return nil
    }
    
    // YouTube 플레이어 HTML 생성 - 오디오 이벤트 캡처 스크립트 포함
    private func createYouTubePlayerHTML(videoID: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body { margin: 0; background-color: black; overflow: hidden; }
                #player { width: 100%; height: 100%; }
            </style>
        </head>
        <body>
            <div id="player"></div>
            <script src="https://www.youtube.com/iframe_api"></script>
            <script>
                var player;
                function onYouTubeIframeAPIReady() {
                    player = new YT.Player('player', {
                        videoId: '\(videoID)',
                        playerVars: {
                            'playsinline': 1,
                            'autoplay': 1,
                            'controls': 0,
                            'showinfo': 0,
                            'rel': 0
                        },
                        events: {
                            'onReady': onPlayerReady,
                            'onStateChange': onPlayerStateChange
                        }
                    });
                }
                
                function onPlayerReady(event) {
                    event.target.playVideo();
                    // 오디오 추출 시작 알림
                    window.webkit.messageHandlers.audioHandler.postMessage({
                        'type': 'audioExtractorReady'
                    });
                }
                
                function onPlayerStateChange(event) {
                    if (event.data == YT.PlayerState.PLAYING) {
                        // 재생 시작 알림
                        window.webkit.messageHandlers.audioHandler.postMessage({
                            'type': 'audioPlaybackStarted',
                            'currentTime': player.getCurrentTime()
                        });
                        
                        // 5초마다 현재 재생 시간 전송
                        setInterval(function() {
                            window.webkit.messageHandlers.audioHandler.postMessage({
                                'type': 'audioPlaybackProgress',
                                'currentTime': player.getCurrentTime()
                            });
                        }, 5000);
                    }
                }
            </script>
        </body>
        </html>
        """
    }
    
    // 시스템 오디오 캡처 세션 설정
    private func setupAudioCaptureSession() {
        let session = AVCaptureSession()
        captureSession = session
        
        // 오디오 입력 설정 - 시스템 오디오를 캡처하려면 iOS 제한으로 인해 마이크 사용
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            onExtractionFailed?(NSError(domain: "YouTubeExtractor", code: 2, userInfo: [NSLocalizedDescriptionKey: "No audio capture device available"]))
            return
        }
        
        do {
            // 오디오 입력 생성
            let audioInput = try AVCaptureDeviceInput(device: audioDevice)
            if session.canAddInput(audioInput) {
                session.addInput(audioInput)
            }
            
            // 오디오 출력 설정
            let audioOutput = AVCaptureAudioDataOutput()
            audioOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.trantext.audioCaptureQueue"))
            
            if session.canAddOutput(audioOutput) {
                session.addOutput(audioOutput)
            }
            
            // 캡처 세션 시작
            session.startRunning()
            
            print("Audio capture session started")
        } catch {
            onExtractionFailed?(error)
            print("Failed to set up audio capture session: \(error.localizedDescription)")
        }
    }
    
    // 오디오 캡처 중지
    func stopAudioExtraction() {
        captureSession?.stopRunning()
        captureSession = nil
        audioCaptureTimer?.invalidate()
        audioCaptureTimer = nil
        webView?.loadHTMLString("", baseURL: nil)
        print("Audio extraction stopped")
    }
}

// WKScriptMessageHandler 구현
extension YouTubeAudioExtractor: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let type = dict["type"] as? String else {
            return
        }
        
        switch type {
        case "audioExtractorReady":
            print("YouTube player is ready for audio extraction")
            
        case "audioPlaybackStarted":
            if let currentTime = dict["currentTime"] as? Double {
                print("Audio playback started at \(currentTime) seconds")
            }
            
        case "audioPlaybackProgress":
            if let currentTime = dict["currentTime"] as? Double {
                print("Current playback time: \(currentTime) seconds")
            }
            
        default:
            break
        }
    }
}

// AVCaptureAudioDataOutputSampleBufferDelegate 구현
extension YouTubeAudioExtractor: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // 처음 10초 동안만 오디오 캡처
        guard let audioBuffer = createPCMBuffer(from: sampleBuffer) else {
            return
        }
        
        // PCM 버퍼를 데이터로 변환
        let pcmData = audioBufferToData(audioBuffer)
        
        // 캡처된 오디오 데이터를 처리 (Whisper API로 전송 등)
        DispatchQueue.main.async {
            self.onAudioBufferCaptured?(pcmData)
            
            // 직접 트랜스크립션 서비스로 전송
            self.transcriptionService?.transcribeAudioData(pcmData)
        }
    }
    
    // CMSampleBuffer에서 PCM 버퍼 생성
    private func createPCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }
        
        let audioFormat = AVAudioFormat(streamDescription: audioStreamBasicDescription)
        guard let format = audioFormat else { return nil }
        
        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        
        CMBlockBufferGetDataPointer(blockBuffer,
                                    atOffset: 0,
                                    lengthAtOffsetOut: &lengthAtOffset,
                                    totalLengthOut: &totalLength,
                                    dataPointerOut: &dataPointer)
        
        guard let data = dataPointer else { return nil }
        
        let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalLength) / format.streamDescription.pointee.mBytesPerFrame)
        guard let channels = pcmBuffer?.floatChannelData else { return nil }
        
        pcmBuffer?.frameLength = pcmBuffer!.frameCapacity
        
        // 데이터를 PCM 버퍼에 복사
        let channelCount = Int(format.channelCount)
        let frameLength = Int(pcmBuffer!.frameLength)
        
        if format.commonFormat == .pcmFormatFloat32 {
            let bytesPerFrame = format.streamDescription.pointee.mBytesPerFrame
            let bytesPerChannel = bytesPerFrame / UInt32(channelCount)
            
            for channel in 0..<channelCount {
                for frame in 0..<frameLength {
                    let offset = frame * Int(bytesPerFrame) + channel * Int(bytesPerChannel)
                    let sample = data.advanced(by: offset).withMemoryRebound(to: Float.self, capacity: 1) { $0.pointee }
                    channels[channel][frame] = sample
                }
            }
            
            return pcmBuffer
        }
        
        return nil
    }
    
    // PCM 버퍼를 Data 객체로 변환
    private func audioBufferToData(_ buffer: AVAudioPCMBuffer) -> Data {
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        var data = Data(capacity: frameLength * channelCount * MemoryLayout<Float>.size)
        
        if buffer.format.commonFormat == .pcmFormatFloat32 {
            for channel in 0..<channelCount {
                let channelData = buffer.floatChannelData?[channel]
                data.append(UnsafeBufferPointer(start: channelData, count: frameLength))
            }
        }
        
        return data
    }
} 