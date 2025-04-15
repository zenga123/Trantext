import Foundation
import AVFoundation

class AudioCaptureManager: NSObject, AVAudioRecorderDelegate {
    private var audioRecorder: AVAudioRecorder?
    private var audioEngine: AVAudioEngine?
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private var isRecording = false
    
    // 녹음된 오디오 파일 URL
    private var recordingURL: URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDirectory.appendingPathComponent("recording.wav")
    }
    
    // 트랜스크립션 서비스
    private var transcriptionService: TranscriptionService?
    
    // 초기화
    init(transcriptionService: TranscriptionService) {
        super.init()
        self.transcriptionService = transcriptionService
        setupAudioSession()
    }
    
    // 오디오 세션 설정
    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
        } catch {
            print("Audio session setup failed: \(error.localizedDescription)")
        }
    }
    
    // 녹음 시작
    func startCapturing() {
        // 이미 녹음 중이면 중단
        if isRecording {
            return
        }
        
        // 기존 녹음 파일 삭제
        if FileManager.default.fileExists(atPath: recordingURL.path) {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        
        // 오디오 녹음 설정
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()
            isRecording = true
            
            // 10초마다 녹음을 처리하는 타이머 설정
            timer = Timer.scheduledTimer(timeInterval: 10.0, target: self, selector: #selector(processRecording), userInfo: nil, repeats: true)
            
        } catch {
            print("Recording failed: \(error.localizedDescription)")
        }
    }
    
    // 녹음 중지
    func stopCapturing() {
        if !isRecording {
            return
        }
        
        timer?.invalidate()
        timer = nil
        
        audioRecorder?.stop()
        isRecording = false
        
        // 마지막 녹음 처리
        processCurrentRecording()
    }
    
    // 현재 녹음 처리
    private func processCurrentRecording() {
        guard let audioRecorder = audioRecorder, 
              FileManager.default.fileExists(atPath: recordingURL.path) else {
            return
        }
        
        // 녹음 길이가 너무 짧으면 무시
        if audioRecorder.currentTime < 1.0 {
            return
        }
        
        // 녹음된 오디오 데이터 가져오기
        do {
            let audioData = try Data(contentsOf: recordingURL)
            
            // 처리를 위해 Whisper API로 전송
            transcriptionService?.transcribeAudioData(audioData)
            
        } catch {
            print("Failed to process audio: \(error.localizedDescription)")
        }
    }
    
    // 타이머에서 호출되는 녹음 처리 메서드
    @objc private func processRecording() {
        guard isRecording else { return }
        
        // 현재 녹음 중지
        audioRecorder?.stop()
        
        // 녹음 처리
        processCurrentRecording()
        
        // 새 녹음 시작
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        // 기존 녹음 파일 삭제 후 새로 시작
        if FileManager.default.fileExists(atPath: recordingURL.path) {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        
        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()
        } catch {
            print("Failed to restart recording: \(error.localizedDescription)")
            isRecording = false
        }
    }
    
    // AVAudioRecorderDelegate
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("Recording finished unsuccessfully")
            isRecording = false
        }
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            print("Recording error: \(error.localizedDescription)")
        }
        isRecording = false
    }
} 