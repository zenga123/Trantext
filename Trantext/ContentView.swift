//
//  ContentView.swift
//  Trantext
//
//  Created by musung on 2025/04/14.
//

import SwiftUI
import WebKit
import AVFoundation

// Coordinator 클래스를 추가하여 TranscriptionServiceDelegate 처리
class TranscriptionCoordinator: NSObject, TranscriptionServiceDelegate {
    var contentView: ContentView
    
    init(contentView: ContentView) {
        self.contentView = contentView
    }
    
    func transcriptionService(_ service: TranscriptionService, didReceiveTranscription transcription: WhisperResponse) {
        contentView.translationService.translateSegments(
            transcription.segments,
            from: contentView.sourceLanguage,
            to: contentView.targetLanguage
        ) { result in
            DispatchQueue.main.async {
                self.contentView.isTranscribing = false
                
                switch result {
                case .success(let translatedSegments):
                    // 기존 자막에 새 자막 추가
                    self.contentView.subtitles = translatedSegments
                    self.contentView.showingSubtitles = true
                    self.contentView.currentSegmentIndex = 0
                    self.contentView.currentWordIndex = 0
                    print("자막 데이터 로드 성공: \(translatedSegments.count) 개의 세그먼트")
                    
                case .failure(let error):
                    self.contentView.errorMessage = "Translation error: \(error.localizedDescription)"
                    print("번역 오류: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func transcriptionService(_ service: TranscriptionService, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.contentView.isTranscribing = false
            self.contentView.errorMessage = "Transcription error: \(error.localizedDescription)"
            print("변환 오류: \(error.localizedDescription)")
        }
    }
}

struct ContentView: View {
    @State private var youtubeURL: String = ""
    @State var subtitles: [TranslatedSegment] = []
    @State var currentSegmentIndex: Int = 0
    @State var currentWordIndex: Int = 0
    @State var isTranscribing: Bool = false
    @State var errorMessage: String? = nil
    @State private var showingSettings: Bool = false
    @State private var coordinator: TranscriptionCoordinator?
    @State var showingSubtitles: Bool = false
    @State private var currentPlaybackTime: Double = 0.0
    
    // API keys from settings
    var openAIApiKey: String {
        guard let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] else {
            fatalError("OPENAI_API_KEY 환경 변수가 설정되지 않았습니다.")
        }
        return key
    }
    @AppStorage("whisper_model") var whisperModel: String = "gpt-4o-transcribe"
    @AppStorage("source_language") var sourceLanguage: String = "Korean"
    @AppStorage("target_language") var targetLanguage: String = "English"
    
    // Services
    var transcriptionService: TranscriptionService {
        let service = TranscriptionService(apiKey: openAIApiKey, modelName: whisperModel)
        service.delegate = coordinator
        return service
    }
    
    var translationService: TranslationService {
        TranslationService(apiKey: openAIApiKey)
    }
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // 영상 영역 (전체 화면 스타일)
                    ZStack {
                        Color.black.edgesIgnoringSafeArea(.all)
                        
                        if youtubeURL.isEmpty {
                            Text("YouTube URL을 입력하세요")
                                .foregroundColor(.white)
                        } else {
                            YouTubePlayerViewEnhanced(videoURL: youtubeURL) { time in
                                updateCurrentSegmentAndWord(time: time)
                            }
                            .onAppear {
                                print("YouTube player appears with URL: \(youtubeURL)")
                            }
                        }
                    }
                    .frame(height: geometry.size.height * 0.4)
                    .background(Color.black)
                    .border(Color.gray.opacity(0.3), width: 1)
                    
                    // 하단 영역: 자막 또는 입력
                    VStack {
                        if !showingSubtitles {
                            // 입력 화면
                            inputView
                                .padding(.top, 10)
                        } else {
                            // 자막 영역 
                            ZStack(alignment: .bottomTrailing) {
                                // 자막 목록
                                subtitleListView
                                    .background(Color.black)
                                
                                // 새 영상 버튼 (오른쪽 하단에 고정)
                                Button(action: {
                                    showingSubtitles = false
                                }) {
                                    Text("새 영상")
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .frame(width: 120, height: 40)
                                        .background(Color.blue)
                                        .cornerRadius(20)
                                }
                                .padding(.bottom, 20)
                                .padding(.trailing, 20)
                            }
                        }
                    }
                    .frame(height: geometry.size.height * 0.6)
                }
                .background(Color.black.edgesIgnoringSafeArea(.all))
            }
            .background(Color.black)
            .navigationTitle("Trantext")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button(action: {
                showingSettings = true
            }) {
                Image(systemName: "gear")
                    .foregroundColor(.white)
            })
            .sheet(isPresented: $showingSettings) {
                SettingsView(isPresented: $showingSettings)
            }
        }
        .onAppear {
            setupServices()
            print("ContentView appeared")
        }
    }
    
    // 자막 리스트 뷰 (스크롤 가능한 자막 목록)
    var subtitleListView: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: false) { // 스크롤바 숨김
                LazyVStack(alignment: .leading, spacing: 16) { // 세그먼트 간 간격 증가
                    // 현재 자막 위에 충분한 여백 추가 (화면 중앙에 위치하도록)
                    Spacer().frame(height: UIScreen.main.bounds.height * 0.35)
                    
                    ForEach(0..<subtitles.count, id: \.self) { index in
                        let segment = subtitles[index]
                        let isCurrent = index == currentSegmentIndex
                        
                        VStack(alignment: .leading, spacing: 6) {
                            // 한국어 원문
                            let words = segment.originalText.components(separatedBy: " ")
                            highlightableText(words: words, highlightedIndex: isCurrent ? currentWordIndex : -1) // 현재 세그먼트일 때만 하이라이트 인덱스 전달
                                .font(isCurrent ? .system(size: 20, weight: .semibold) : .system(size: 16, weight: .regular))
                                .foregroundColor(isCurrent ? .white : .gray.opacity(0.6))
                                .padding(.horizontal, isCurrent ? 12 : 8)
                                .padding(.vertical, isCurrent ? 10 : 4)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            // 영어 번역 (현재 세그먼트 또는 약간 흐리게)
                            Text(segment.translatedText)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(isCurrent ? .white.opacity(0.85) : .gray.opacity(0.5))
                                .padding(.horizontal, isCurrent ? 12 : 8)
                                .padding(.bottom, isCurrent ? 8 : 4)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineLimit(nil)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.vertical, isCurrent ? 12 : 6)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isCurrent ? Color(UIColor.darkGray).opacity(0.5) : Color.clear)
                        )
                        .opacity(isCurrent ? 1.0 : 0.7) // 비활성 세그먼트 투명도 조절
                        .scaleEffect(isCurrent ? 1.0 : 0.95) // 비활성 세그먼트 약간 작게
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isCurrent)
                        .id("segment-\(index)")
                    }
                    
                    // 현재 자막 아래 충분한 여백 추가 (화면 중앙에 위치하도록)
                    Spacer().frame(height: UIScreen.main.bounds.height * 0.35)
                }
                .padding(.bottom, 80) // 하단 버튼 영역 확보
            }
            .onAppear {
                print("Subtitle view appeared with \(subtitles.count) segments")
                // 최초 로드 시 현재 세그먼트로 스크롤
                if !subtitles.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo("segment-\(currentSegmentIndex)", anchor: .center)
                            print("Scrolled to segment \(currentSegmentIndex)")
                        }
                    }
                }
            }
            .onChange(of: currentSegmentIndex) { newIndex in
                // 현재 세그먼트가 변경되면 스크롤 위치 조정
                if !subtitles.isEmpty {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        scrollProxy.scrollTo("segment-\(newIndex)", anchor: .center)
                        print("Segment changed to \(newIndex)")
                    }
                }
            }
            // 단어 인덱스가 변경될 때도 현재 세그먼트가 중앙에 오도록 처리
            .onChange(of: currentWordIndex) { _ in
                if !subtitles.isEmpty {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        scrollProxy.scrollTo("segment-\(currentSegmentIndex)", anchor: .center)
                    }
                }
            }
        }
    }
    
    // 자막 표시 뷰 (별도 영역 표시용 - 더 이상 사용하지 않음)
    var subtitleView: some View {
        VStack(spacing: 15) {
            if !subtitles.isEmpty && currentSegmentIndex < subtitles.count {
                let currentSegment = subtitles[currentSegmentIndex]
                
                // 원본 텍스트 - 단어별 하이라이트
                WordHighlightView(
                    text: currentSegment.originalText,
                    currentWordIndex: currentWordIndex
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(Color.black)
                
                // 번역 텍스트
                Text(currentSegment.translatedText)
                    .font(.system(size: 22))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .multilineTextAlignment(.center)
                
                // 디버깅 정보
                Text("세그먼트 \(currentSegmentIndex+1)/\(subtitles.count) • 시간: \(formatTime(currentSegment.start)) - \(formatTime(currentSegment.end))")
                    .font(.caption)
                    .foregroundColor(.gray.opacity(0.7))
            } else {
                Text("자막 데이터가 없습니다")
                    .foregroundColor(.white)
                    .padding(.top, 30)
            }
            
            Spacer()
        }
    }
    
    // 입력 및 설정 뷰
    var inputView: some View {
        VStack(spacing: 20) {
            // URL 입력
            TextField("Enter YouTube URL", text: $youtubeURL)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding(.horizontal)
            
            Button(action: {
                Task {
                    do {
                        // 상태 초기화
                        self.isTranscribing = true
                        self.showingSubtitles = false
                        self.errorMessage = nil
                        
                        // URL 검증
                        guard validateYouTubeURL(youtubeURL) else {
                            throw NSError(domain: "TranscriptError", code: 400, 
                                        userInfo: [NSLocalizedDescriptionKey: "유효한 YouTube URL이 아닙니다."])
                        }
                        
                        // 서버 연결 확인
                        try await checkServerConnection()
                        
                        // Whisper API 호출
                        print("자막 생성 시작: \(youtubeURL)")
                        let response = try await callWhisperApi(youtubeURL: youtubeURL)
                        
                        // 응답 처리
                        if response.segments.isEmpty && response.text.isEmpty {
                            throw NSError(domain: "TranscriptError", code: 400, 
                                         userInfo: [NSLocalizedDescriptionKey: "자막을 추출할 수 없습니다. 다른 영상을 시도해보세요."])
                        }
                        
                        // 자막 처리
                        processWhisperResponse(response)
                    } catch {
                        DispatchQueue.main.async {
                            self.isTranscribing = false
                            self.errorMessage = "Error: \(error.localizedDescription)"
                            print("자막 처리 오류: \(error.localizedDescription)")
                        }
                    }
                }
            }) {
                Text("자막 생성")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isTranscribing ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .disabled(isTranscribing || youtubeURL.isEmpty)
            .padding(.horizontal)
            
            // 상태 표시
            if isTranscribing {
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .foregroundColor(.white)
                    Text("자막 처리 중...")
                        .foregroundColor(.white)
                        .padding(.leading, 8)
                }
                .padding(.vertical, 8)
            }
            
            // 오류 메시지
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            }
            
            Spacer()
        }
        .padding(.top, 10)
    }
    
    private func setupServices() {
        // Initialize coordinator with self reference
        coordinator = TranscriptionCoordinator(contentView: self)
    }
    
    private func loadVideoAndTranscribe() {
        guard !youtubeURL.isEmpty else {
            errorMessage = "Please enter a YouTube URL"
            return
        }
        
        isTranscribing = true
        showingSubtitles = false
        
        // 백엔드 서버에 요청 보내기
        let serverURL = "http://127.0.0.1:5001/transcribe"
        let parameters: [String: Any] = ["youtube_url": youtubeURL]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: parameters) else {
            errorMessage = "Failed to prepare request"
            isTranscribing = false
            return
        }
        
        var request = URLRequest(url: URL(string: serverURL)!)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.isTranscribing = false
                    self.errorMessage = "Error: \(error.localizedDescription)"
                    print("네트워크 오류: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    self.isTranscribing = false
                    self.errorMessage = "No data received from server"
                    print("서버로부터 데이터를 받지 못함")
                    return
                }
                
                do {
                    // 서버 응답 로그 출력
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("Server response: \(jsonString)")
                    }
                    
                    // WhisperResponse로 디코딩
                    let decoder = JSONDecoder()
                    if let whisperResponse = try? decoder.decode(WhisperResponse.self, from: data) {
                        self.processWhisperResponse(whisperResponse)
                    } else {
                        // 단순 텍스트 응답 케이스
                        if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            if let text = jsonObject["text"] as? String {
                                let segment = WhisperSegment(id: 0, text: text, start: 0.0, end: 10.0)
                                let response = WhisperResponse(text: text, segments: [segment])
                                self.processWhisperResponse(response)
                            } else if let error = jsonObject["error"] as? String {
                                self.errorMessage = "Server error: \(error)"
                                self.isTranscribing = false
                                print("서버 오류: \(error)")
                            }
                        }
                    }
                } catch {
                    self.errorMessage = "Failed to parse response: \(error.localizedDescription)"
                    self.isTranscribing = false
                    print("응답 파싱 오류: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
    
    // YouTube URL 유효성 검사
    private func validateYouTubeURL(_ url: String) -> Bool {
        // 너무 짧은 URL은 유효하지 않음
        if url.count < 10 {
            return false
        }
        
        // YouTube URL 형식 검사
        let pattern = "(https?://)?(www\\.)?(youtube\\.com/watch\\?v=|youtu\\.be/)[\\w\\-]+"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: url.utf16.count)
        return regex?.firstMatch(in: url, range: range) != nil
    }
    
    // 서버 연결 확인
    private func checkServerConnection() async throws {
        guard let url = URL(string: "http://127.0.0.1:5001/health") else {
            print("Error: Invalid health check URL")
            throw NSError(domain: "ConnectionError", code: 400, userInfo: [NSLocalizedDescriptionKey: "잘못된 서버 URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15 // 타임아웃 시간을 15초로 늘림
        
        print("서버 연결 확인 시작: \(url.absoluteString)")
        
        do {
            print("URLSession 요청 전송 시도...")
            let (data, response) = try await URLSession.shared.data(for: request)
            print("URLSession 응답 수신 완료.")
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("Error: 유효하지 않은 HTTP 응답")
                throw NSError(domain: "ConnectionError", code: 500, userInfo: [NSLocalizedDescriptionKey: "서버 응답이 유효하지 않습니다."])
            }
            
            print("서버 상태 코드: \(httpResponse.statusCode)")
            if let responseBody = String(data: data, encoding: .utf8) {
                print("서버 응답 내용: \(responseBody)")
            }
            
            if httpResponse.statusCode == 200 {
                print("서버 연결 확인 성공")
                return
            } else {
                print("Error: 서버 상태 코드 \(httpResponse.statusCode)")
                throw NSError(domain: "ConnectionError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "서버 상태 코드: \(httpResponse.statusCode)"])
            }
        } catch let error as NSError where error.domain == NSURLErrorDomain && error.code == NSURLErrorTimedOut {
            print("Error: 요청 시간 초과 (Timeout) - \(error.localizedDescription)")
            throw NSError(domain: "ConnectionError", code: error.code, userInfo: [NSLocalizedDescriptionKey: "서버 연결 시간 초과. 네트워크 또는 방화벽 설정을 확인하세요."])
        } catch {
            print("Error: 서버 연결 중 알 수 없는 오류 발생 - \(error.localizedDescription)")
            throw NSError(domain: "ConnectionError", code: 503, userInfo: [NSLocalizedDescriptionKey: "서버에 연결할 수 없습니다: \(error.localizedDescription)"])
        }
    }
    
    // Whisper API를 호출하여 YouTube URL에서 자막을 가져옵니다.
    func callWhisperApi(youtubeURL: String) async throws -> WhisperResponse {
        guard !youtubeURL.isEmpty else {
            print("YouTube URL이 비어있습니다.")
            throw NSError(domain: "TranscriptError", code: 400, userInfo: [NSLocalizedDescriptionKey: "YouTube URL이 비어있습니다."])
        }
        
        print("Whisper API 호출 시작: \(youtubeURL)")
        
        // API 요청 URL 구성
        guard let url = URL(string: "http://127.0.0.1:5001/transcribe") else {
            let error = NSError(domain: "TranscriptError", code: 400, userInfo: [NSLocalizedDescriptionKey: "잘못된 API URL"])
            print("잘못된 API URL")
            throw error
        }
        
        // 요청 본문 구성
        let requestBody: [String: String] = ["youtube_url": youtubeURL]
        
        guard let jsonData = try? JSONEncoder().encode(requestBody) else {
            let error = NSError(domain: "TranscriptError", code: 400, userInfo: [NSLocalizedDescriptionKey: "JSON 인코딩 실패"])
            print("JSON 인코딩 실패")
            throw error
        }
        
        // API 요청 구성
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120 // 타임아웃 시간 늘림 (2분)
        
        print("서버에 요청 전송: \(requestBody)")
        
        // API 요청 전송 및 응답 처리
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            let error = NSError(domain: "TranscriptError", code: 500, userInfo: [NSLocalizedDescriptionKey: "HTTP 응답이 아닙니다."])
            print("HTTP 응답이 아닙니다.")
            throw error
        }
        
        print("Whisper API 응답 코드: \(httpResponse.statusCode)")
        
        // 응답 전체 로깅 (디버깅용)
        if let jsonString = String(data: data, encoding: .utf8) {
            print("JSON 응답 전체: \(jsonString)")
        }
        
        if httpResponse.statusCode == 200 {
            // 다양한 응답 형식 처리 시도
            do {
                // 일반적인 WhisperResponse로 디코딩 시도
                do {
                    let decoder = JSONDecoder()
                    let whisperResponse = try decoder.decode(WhisperResponse.self, from: data)
                    print("정상 형식 응답 디코딩 성공: \(whisperResponse.segments.count) 세그먼트")
                    return whisperResponse
                } catch {
                    print("표준 형식 디코딩 실패: \(error.localizedDescription), 대체 형식 시도")
                    
                    // JSON을 딕셔너리로 파싱
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        
                        // OpenAI API 기본 형식 (text 필드만 있는 경우) 처리
                        if let text = json["text"] as? String {
                            print("텍스트만 포함된 응답 처리: \(text.prefix(30))...")
                            
                            // 텍스트를 단일 세그먼트로 변환
                            let segment = WhisperSegment(id: 0, text: text, start: 0.0, end: 30.0)
                            let response = WhisperResponse(text: text, segments: [segment])
                            return response
                        }
                        
                        // 오류 메시지가 포함된 경우
                        if let errorMsg = json["error"] as? String {
                            print("서버 오류 응답: \(errorMsg)")
                            throw NSError(domain: "TranscriptError", code: 400, userInfo: [NSLocalizedDescriptionKey: "서버 오류: \(errorMsg)"])
                        }
                    }
                    
                    // 모든 시도 실패 시 오류 발생
                    throw NSError(domain: "TranscriptError", code: 400, userInfo: [NSLocalizedDescriptionKey: "응답 형식이 예상과 다릅니다: \(error.localizedDescription)"])
                }
            } catch {
                print("모든 디코딩 시도 실패: \(error.localizedDescription)")
                throw error
            }
        } else {
            // 서버 오류 응답 처리
            let errorMessage: String
            if let errorData = try? JSONDecoder().decode([String: String].self, from: data),
               let message = errorData["error"] {
                errorMessage = message
            } else if let errorText = String(data: data, encoding: .utf8) {
                errorMessage = errorText
            } else {
                errorMessage = "상태 코드 \(httpResponse.statusCode)"
            }
            
            print("Whisper API 요청 실패: \(errorMessage)")
            throw NSError(domain: "TranscriptError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "서버 오류: \(errorMessage)"])
        }
    }
    
    // Whisper API 응답을 처리하여 자막을 설정합니다.
    func processWhisperResponse(_ response: WhisperResponse?) {
        guard let response = response else {
            DispatchQueue.main.async {
                self.isTranscribing = false
                self.errorMessage = "응답이 없습니다."
                print("응답이 없어 처리할 수 없습니다.")
            }
            return
        }
        
        // 상태 업데이트
        DispatchQueue.main.async {
            // 기존 자막 데이터 초기화
            self.subtitles.removeAll()
            self.currentSegmentIndex = 0
            self.currentWordIndex = 0
            self.showingSubtitles = true // 자막 표시 화면으로 전환
        }
        
        print("Whisper 응답 처리 시작: \(response.segments.count) 세그먼트")
        
        // 세그먼트 처리를 위한 비동기 작업
        Task {
            // 빈 자막인 경우 빠르게 처리
            if response.segments.isEmpty {
                // 전체 텍스트를 하나의 세그먼트로 처리
                if !response.text.isEmpty {
                    let translatedSegment = await translateSingleSegment(
                        id: 0,
                        text: response.text,
                        start: 0.0,
                        end: 30.0
                    )
                    
                    DispatchQueue.main.async {
                        self.subtitles = [translatedSegment]
                        self.isTranscribing = false
                        print("단일 세그먼트로 처리 완료: \(response.text)")
                    }
                    return
                } else {
                    DispatchQueue.main.async {
                        self.isTranscribing = false
                        self.errorMessage = "변환된 자막이 없습니다."
                        print("빈 자막 데이터")
                    }
                    return
                }
            }
            
            // 세그먼트 정상 처리
            var translatedSegments: [TranslatedSegment] = []
            var processedCount = 0
            
            // 모든 세그먼트 병렬 처리
            await withTaskGroup(of: TranslatedSegment?.self) { group in
                // 각 세그먼트에 대한 작업 추가
                for segment in response.segments {
                    group.addTask {
                        return await self.translateSingleSegment(
                            id: segment.id,
                            text: segment.text,
                            start: segment.start,
                            end: segment.end
                        )
                    }
                }
                
                // 결과 수집
                for await translatedSegment in group {
                    if let segment = translatedSegment {
                        translatedSegments.append(segment)
                        processedCount += 1
                        
                        // 진행 상황 정기 업데이트
                        if processedCount % 5 == 0 || processedCount == response.segments.count {
                            let sortedSegments = translatedSegments.sorted { $0.start < $1.start }
                            DispatchQueue.main.async {
                                self.subtitles = sortedSegments
                                print("자막 업데이트: \(sortedSegments.count)/\(response.segments.count) 세그먼트 처리됨")
                            }
                        }
                    }
                }
            }
            
            // 최종 정렬 및 업데이트
            let finalSegments = translatedSegments.sorted { $0.start < $1.start }
            
            DispatchQueue.main.async {
                self.isTranscribing = false
                if finalSegments.isEmpty {
                    self.errorMessage = "처리된 자막이 없습니다."
                    self.showingSubtitles = false
                } else {
                    self.subtitles = finalSegments
                    self.errorMessage = nil
                    print("자막 처리 완료: 총 \(finalSegments.count) 세그먼트")
                }
            }
        }
    }
    
    // 단일 세그먼트 번역 처리
    private func translateSingleSegment(id: Int, text: String, start: Double, end: Double) async -> TranslatedSegment {
        let originalText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var translatedText = "번역 중..."
        
        if originalText.isEmpty {
            return TranslatedSegment(
                id: id,
                originalText: "(빈 텍스트)",
                translatedText: "(빈 텍스트)",
                start: start,
                end: end
            )
        }
        
        // 번역 서비스 직접 호출
        do {
            let request = TranslationRequest(
                text: originalText,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage
            )
            
            let result = try await translationService.translate(request)
            translatedText = result.translatedText
            print("번역 성공: '\(originalText.prefix(20))...' -> '\(translatedText.prefix(20))...'")
        } catch {
            translatedText = "번역 실패: \(error.localizedDescription)"
            print("번역 오류: \(error.localizedDescription)")
        }
        
        return TranslatedSegment(
            id: id,
            originalText: originalText,
            translatedText: translatedText,
            start: start,
            end: end
        )
    }
    
    // 비디오 시간에 따라 현재 세그먼트와 단어 업데이트
    private func updateCurrentSegmentAndWord(time: Double) {
        guard !subtitles.isEmpty else { return }
        
        // 너무 작은 시간 변화는 무시 (노이즈 제거) - 더 작은 변화도 감지하도록 임계값 낮춤
        if abs(time - currentPlaybackTime) < 0.05 {
            return
        }
        
        self.currentPlaybackTime = time
        
        // 1. 현재 재생 시간에 맞는 세그먼트 찾기
        for (index, segment) in subtitles.enumerated() {
            if time >= segment.start && time <= segment.end {
                // 세그먼트 변경 시 확실하게 갱신
                if currentSegmentIndex != index {
                    currentSegmentIndex = index
                    currentWordIndex = 0
                    print("세그먼트 변경: \(index)")
                }
                
                // 2. 세그먼트 내에서 단어의 상대적 위치 계산 (개선된 로직)
                let segmentDuration = segment.end - segment.start
                if segmentDuration > 0 {
                    let relativePosition = (time - segment.start) / segmentDuration
                    
                    let words = segment.originalText.components(separatedBy: " ")
                    if !words.isEmpty {
                        // 더 세밀한 단어 인덱스 계산
                        // 비선형 매핑을 적용하여 초반에는 천천히, 중간에는 적당히, 후반에는 빠르게 진행하도록 조정
                        // 이는 일반적인 말하기 패턴에 더 가깝게 매핑됨
                        var adjustedPosition = relativePosition
                        
                        // easeInOut 효과 적용 (부드러운 가속 및 감속)
                        if relativePosition < 0.5 {
                            adjustedPosition = 0.5 * pow(2 * relativePosition, 2)
                        } else {
                            adjustedPosition = 0.5 * (1 - pow(-2 * relativePosition + 2, 2) + 1)
                        }
                        
                        let wordIndex = min(Int(adjustedPosition * Double(words.count)), words.count - 1)
                        
                        // 단어 인덱스가 변경된 경우에만 갱신 (연속 업데이트 방지)
                        if currentWordIndex != wordIndex {
                            currentWordIndex = wordIndex
                            // 디버깅을 위한 로그 추가
                            if wordIndex < words.count {
                                print("단어 변경: \(words[wordIndex]) (인덱스: \(wordIndex)/\(words.count-1), 시간: \(String(format: "%.2f", time))/\(String(format: "%.2f", segment.end)))")
                            }
                        }
                    }
                }
                
                return
            }
        }
        
        // 현재 시간이 어떤 세그먼트에도 속하지 않으면 가장 가까운 세그먼트 찾기
        if time < subtitles.first?.start ?? 0 {
            if currentSegmentIndex != 0 {
                currentSegmentIndex = 0
                currentWordIndex = 0
            }
        } else if time > subtitles.last?.end ?? 0 {
            let lastIndex = subtitles.count - 1
            if currentSegmentIndex != lastIndex {
                currentSegmentIndex = lastIndex
                currentWordIndex = (subtitles.last?.originalText.components(separatedBy: " ").count ?? 1) - 1
            }
        }
    }
    
    // 시간(초)를 00:00 형식으로 변환하는 함수
    private func formatTime(_ timeInSeconds: Double) -> String {
        let minutes = Int(timeInSeconds) / 60
        let seconds = Int(timeInSeconds) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// 단어별 하이라이트를 위한 뷰
struct WordHighlightView: View {
    let text: String
    let currentWordIndex: Int
    
    var body: some View {
        let words = text.components(separatedBy: " ")
        
        VStack(alignment: .center, spacing: 8) {
            // 한 줄에 너무 많은 단어가 들어가지 않도록 VStack으로 감싼 HStack 사용
            Text(words.enumerated().map { index, word in
                if index == currentWordIndex {
                    return "[\(word)]"
                } else {
                    return word
                }
            }.joined(separator: " "))
            .font(.system(size: 28, weight: .bold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .padding(.horizontal)
            
            // 현재 단어만 별도로 하이라이트
            if currentWordIndex < words.count {
                Text(words[currentWordIndex])
                    .font(.system(size: 36, weight: .black))
                    .foregroundColor(.green)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.green.opacity(0.3))
                    )
                    .transition(.scale.combined(with: .opacity))
                    .id("highlight-\(currentWordIndex)")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// YouTube 플레이어 WebView 래퍼 (확장 버전)
struct YouTubePlayerViewEnhanced: UIViewRepresentable {
    let videoURL: String
    var timeUpdateHandler: (Double) -> Void
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptEnabled = true
        configuration.allowsAirPlayForMediaPlayback = true
        
        // 비디오 재생 최적화 설정
        let preferences = WKPreferences()
        preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences = preferences
        
        // 웹뷰 프로세스풀 설정
        configuration.processPool = WKProcessPool()
        
        // 미디어 재생 설정
        if #available(iOS 14.0, *) {
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.backgroundColor = .black
        webView.isOpaque = true
        webView.scrollView.bounces = false
        
        // 사용자 인터페이스 스타일 설정
        if #available(iOS 13.0, *) {
            webView.overrideUserInterfaceStyle = .dark
        }
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        guard !videoURL.isEmpty else { return }
        
        let videoId = extractVideoID(from: videoURL)
        guard !videoId.isEmpty else { 
            print("Invalid YouTube URL or ID: \(videoURL)")
            return 
        }
        
        // 이미 로드된 비디오 ID 확인
        let currentVideoId = context.coordinator.currentVideoId
        
        // 이미 같은 비디오가 로드되어 있다면 재로드하지 않음
        if currentVideoId == videoId && webView.isLoading == false && webView.url != nil {
            print("Video already loaded: \(videoId)")
            return
        }
        
        // 새 비디오 ID 저장
        context.coordinator.currentVideoId = videoId
        
        // 기존 로드 취소
        webView.stopLoading()
        
        print("Loading YouTube video ID: \(videoId)")
        
        let embedHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body { width: 100%; height: 100%; background-color: #000; overflow: hidden; }
                .container { position: relative; width: 100%; height: 100%; overflow: hidden; display: flex; justify-content: center; align-items: center; }
                #player { width: 100%; height: 100%; }
            </style>
        </head>
        <body>
            <div class="container">
                <div id="player"></div>
            </div>
            
            <script>
                // YouTube API 스크립트를 한 번만 로드하도록 함수로 분리
                var tag = document.createElement('script');
                tag.src = "https://www.youtube.com/iframe_api";
                var firstScriptTag = document.getElementsByTagName('script')[0];
                firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);
                
                var player;
                var timeUpdateInterval = null;
                var lastTime = 0;
                var isInitialized = false;
                
                function onYouTubeIframeAPIReady() {
                    console.log('YouTube API ready, creating player for: \(videoId)');
                    try {
                        player = new YT.Player('player', {
                            videoId: '\(videoId)',
                            playerVars: {
                                'playsinline': 1,
                                'autoplay': 1,
                                'controls': 1,
                                'rel': 0,
                                'fs': 0,
                                'modestbranding': 1,
                                'origin': 'https://www.youtube.com'
                            },
                            events: {
                                'onReady': onPlayerReady,
                                'onStateChange': onPlayerStateChange,
                                'onError': onPlayerError
                            }
                        });
                    } catch (e) {
                        console.error('Error creating player:', e);
                    }
                }
                
                function onPlayerReady(event) {
                    console.log('Player ready');
                    event.target.playVideo();
                    startTimeUpdates();
                }
                
                function startTimeUpdates() {
                    // 이전 인터벌 제거 후 새로 설정
                    if (timeUpdateInterval) {
                        clearInterval(timeUpdateInterval);
                    }
                    
                    if (!isInitialized) {
                        isInitialized = true;
                        // 200ms마다 시간 업데이트 (단어 동기화 정확도 향상)
                        timeUpdateInterval = setInterval(function() {
                            if (!player || typeof player.getCurrentTime !== 'function') return;
                            
                            try {
                                // 재생 중인 상태에서만 시간 업데이트
                                if (player.getPlayerState() === YT.PlayerState.PLAYING) {
                                    var currentTime = player.getCurrentTime();
                                    // 이전 시간과 현재 시간의 차이가 너무 크면 갱신하지 않음
                                    if (Math.abs(currentTime - lastTime) < 5) {
                                        window.webkit.messageHandlers.timeHandler.postMessage(currentTime);
                                    }
                                    lastTime = currentTime;
                                }
                            } catch (e) {
                                console.error('Error in time update:', e);
                            }
                        }, 200);
                    }
                }
                
                function onPlayerStateChange(event) {
                    console.log('Player state changed: ' + event.data);
                }
                
                function onPlayerError(event) {
                    console.error('Player error: ' + event.data);
                }
                
                // 페이지 언로드 시 정리
                window.onbeforeunload = function() {
                    if (timeUpdateInterval) {
                        clearInterval(timeUpdateInterval);
                    }
                };
            </script>
        </body>
        </html>
        """
        
        webView.loadHTMLString(embedHTML, baseURL: URL(string: "https://www.youtube.com"))
        
        // 타임 핸들러 등록
        let contentController = webView.configuration.userContentController
        contentController.removeAllUserScripts()
        contentController.removeAllScriptMessageHandlers()
        contentController.add(context.coordinator, name: "timeHandler")
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: YouTubePlayerViewEnhanced
        private var lastUpdateTime: Double = 0
        private var lastReportedVideoTime: Double = 0
        var currentVideoId: String = ""
        
        init(_ parent: YouTubePlayerViewEnhanced) {
            self.parent = parent
            super.init()
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "timeHandler" {
                if let time = message.body as? Double {
                    // 더 높은 빈도(짧은 간격)로 업데이트하여 동기화 정확도 향상
                    // 마지막 업데이트와 현재 시간 차이가 0.1초 이상일 때 업데이트
                    let currentTime = Date().timeIntervalSince1970
                    
                    // 비디오 시간 변화가 의미 있는 경우에만 업데이트 
                    // (정확한 동기화를 위해 작은 변화도 감지)
                    if currentTime - lastUpdateTime > 0.1 || abs(time - lastReportedVideoTime) > 0.1 {
                        lastUpdateTime = currentTime
                        lastReportedVideoTime = time
                        
                        DispatchQueue.main.async {
                            self.parent.timeUpdateHandler(time)
                        }
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("WebView finished loading")
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("WebView failed loading with error: \(error.localizedDescription)")
        }
    }
    
    // YouTube 비디오 ID 추출
    private func extractVideoID(from url: String) -> String {
        let pattern = "(?:youtube\\.com\\/watch\\?v=|youtu\\.be\\/)([\\w-]+)"
        let regex = try? NSRegularExpression(pattern: pattern)
        if let match = regex?.firstMatch(in: url, range: NSRange(location: 0, length: url.utf16.count)) {
            if let range = Range(match.range(at: 1), in: url) {
                return String(url[range])
            }
        }
        return ""
    }
}

// TranslationRequest 모델
struct TranslationRequest {
    let text: String
    let sourceLanguage: String
    let targetLanguage: String
}

// TranslationResult 모델
struct TranslationResult {
    let originalText: String
    let translatedText: String
    let sourceLanguage: String
    let targetLanguage: String
}

// TranslationService 확장 (실제 구현)
extension TranslationService {
    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        // 서버 API URL
        guard let url = URL(string: "http://127.0.0.1:5001/translate") else {
            throw NSError(domain: "TranslationError", code: 400, userInfo: [NSLocalizedDescriptionKey: "잘못된 번역 API URL"])
        }
        
        // 요청 본문 구성
        let requestBody: [String: String] = [
            "text": request.text,
            "target_lang": request.targetLanguage
        ]
        
        guard let jsonData = try? JSONEncoder().encode(requestBody) else {
            throw NSError(domain: "TranslationError", code: 400, userInfo: [NSLocalizedDescriptionKey: "JSON 인코딩 실패"])
        }
        
        // API 요청 구성
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = jsonData
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 30 // 30초 타임아웃
        
        print("번역 요청 전송: \(request.text.prefix(30))... → \(request.targetLanguage)")
        
        // API 요청 전송 및 응답 처리
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "TranslationError", code: 500, userInfo: [NSLocalizedDescriptionKey: "HTTP 응답이 아닙니다."])
        }
        
        print("번역 API 응답 코드: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode == 200 {
            // 응답 로깅
            if let jsonString = String(data: data, encoding: .utf8) {
                print("번역 응답: \(jsonString)")
            }
            
            // JSON 응답 디코딩
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let translatedText = json["translated_text"] as? String {
                
                return TranslationResult(
                    originalText: request.text,
                    translatedText: translatedText,
                    sourceLanguage: request.sourceLanguage,
                    targetLanguage: request.targetLanguage
                )
            } else {
                throw NSError(domain: "TranslationError", code: 400, userInfo: [NSLocalizedDescriptionKey: "번역 응답 디코딩 실패"])
            }
        } else {
            // 에러 응답 처리
            let errorMessage: String
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? String {
                errorMessage = error
            } else if let errorText = String(data: data, encoding: .utf8) {
                errorMessage = errorText
            } else {
                errorMessage = "상태 코드 \(httpResponse.statusCode)"
            }
            
            print("번역 API 요청 실패: \(errorMessage)")
            throw NSError(domain: "TranslationError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "번역 서버 오류: \(errorMessage)"])
        }
    }
}

// 단어 배열을 받아 하이라이트된 Text 뷰를 생성하는 헬퍼 함수
@ViewBuilder
private func highlightableText(words: [String], highlightedIndex: Int) -> some View {
    // HStack 사용하여 단어를 가로로 배치
    HStack(alignment: .center, spacing: 4) {
        ForEach(Array(words.enumerated()), id: \.0) { index, word in
            Text(word)
                .font(.system(size: 18, weight: index == highlightedIndex ? .bold : .regular))
                .foregroundColor(.white.opacity(index == highlightedIndex ? 1.0 : 0.9))
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.green, lineWidth: 2)
                        .opacity(index == highlightedIndex ? 1.0 : 0.0)
                )
                .fixedSize()
                // ID를 추가해 각 단어에 독립적인 애니메이션 적용
                .id("word-\(index)-\(highlightedIndex)")
                // 애니메이션 추가 (글자가 커지고 작아지는 효과)
                .scaleEffect(index == highlightedIndex ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: highlightedIndex)
        }
    }
    .fixedSize(horizontal: false, vertical: true) // 자동 줄바꿈 허용
    .multilineTextAlignment(.leading)
}

#Preview {
    ContentView()
}
