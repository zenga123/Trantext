import SwiftUI
import WebKit

struct YouTubePlayerView: UIViewRepresentable {
    let videoURL: String
    var shouldMute: Bool = false
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.isScrollEnabled = false
        
        // JavaScript 이벤트 수신 설정
        let contentController = WKUserContentController()
        webView.configuration.userContentController = contentController
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard !videoURL.isEmpty else { return }
        
        // Extract YouTube video ID if full URL is provided
        var videoId = videoURL
        if videoURL.contains("youtube.com") || videoURL.contains("youtu.be") {
            if let queryItems = URLComponents(string: videoURL)?.queryItems {
                for item in queryItems where item.name == "v" {
                    videoId = item.value ?? ""
                    break
                }
            } else if videoURL.contains("youtu.be/") {
                videoId = videoURL.components(separatedBy: "youtu.be/").last ?? ""
            }
        }
        
        // 비디오 ID만 추출
        if videoId.contains("?") {
            videoId = String(videoId.split(separator: "?")[0])
        }
        if videoId.contains("&") {
            videoId = String(videoId.split(separator: "&")[0])
        }
        
        // Load YouTube player HTML - 오디오 추출을 위한 최적화 옵션 추가
        let htmlString = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body { margin: 0; background-color: black; }
                .container { position: relative; padding-bottom: 56.25%; height: 0; overflow: hidden; }
                iframe { position: absolute; top: 0; left: 0; width: 100%; height: 100%; }
            </style>
        </head>
        <body>
            <div class="container">
                <iframe width="100%" height="100%" 
                    src="https://www.youtube.com/embed/\(videoId)?playsinline=1&autoplay=1\(shouldMute ? "&mute=1" : "")" 
                    frameborder="0" allowfullscreen
                    allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                ></iframe>
            </div>
            <script>
                // JavaScript 명령을 보내기 위한 인터페이스
                window.addEventListener('message', function(event) {
                    // iOS 앱에서 메시지 수신
                    if (event.data && event.data.command) {
                        switch(event.data.command) {
                            case 'getCurrentTime':
                                // 현재 재생 시간 반환
                                try {
                                    var player = document.querySelector('iframe');
                                    var time = player.contentWindow.document.querySelector('video').currentTime;
                                    window.webkit.messageHandlers.youtubePlayer.postMessage({
                                        'type': 'timeUpdate',
                                        'currentTime': time
                                    });
                                } catch(err) {
                                    console.error('Error getting current time:', err);
                                }
                                break;
                        }
                    }
                });
            </script>
        </body>
        </html>
        """
        
        uiView.loadHTMLString(htmlString, baseURL: URL(string: "https://www.youtube.com"))
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: YouTubePlayerView
        
        init(_ parent: YouTubePlayerView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("YouTube player loaded successfully")
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("YouTube player failed to load: \(error.localizedDescription)")
        }
    }
} 