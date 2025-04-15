import Foundation
import AVFoundation
// Model 폴더의 타입 사용

// MARK: - TranscriptionServiceDelegate

protocol TranscriptionServiceDelegate: AnyObject {
    func transcriptionService(_ service: TranscriptionService, didReceiveTranscription transcription: WhisperResponse)
    func transcriptionService(_ service: TranscriptionService, didFailWithError error: Error)
}

class TranscriptionService {
    private let apiKey: String
    private var audioEngine: AVAudioEngine?
    private var recognitionTask: URLSessionDataTask?
    private var isRecording = false
    
    // Queue for storing audio chunks
    private var audioChunks: [Data] = []
    private let audioQueue = DispatchQueue(label: "com.trantext.audioQueue")
    
    // Queue for processing transcriptions
    private let transcriptionQueue = DispatchQueue(label: "com.trantext.transcriptionQueue")
    
    // Delegate for receiving transcription updates
    weak var delegate: TranscriptionServiceDelegate?
    
    // Model name for transcription
    private let modelName: String
    
    init(apiKey: String, modelName: String = "gpt-4o-transcribe") {
        self.apiKey = apiKey
        self.modelName = modelName
    }
    
    // 새 메서드: 오디오 데이터 직접 transcribe
    func transcribeAudioData(_ audioData: Data) {
        transcribeAudio(audioData)
    }
    
    // Start capturing audio from the specified source
    func startTranscription(from audioSource: AVAudioNode) {
        guard !isRecording else { return }
        
        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine
        
        let format = audioSource.outputFormat(forBus: 0)
        
        // Install tap on audio source
        audioSource.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            guard let self = self else { return }
            
            // Convert buffer to data
            let channelData = buffer.floatChannelData?[0]
            let data = Data(bytes: channelData!, count: Int(buffer.frameLength) * MemoryLayout<Float>.size)
            
            // Store audio chunk
            self.audioQueue.async {
                self.audioChunks.append(data)
                
                // If we've collected enough audio (e.g., 5 seconds worth), send for transcription
                if self.audioChunks.count >= 5 {
                    self.processAudioChunks()
                }
            }
        }
        
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            delegate?.transcriptionService(self, didFailWithError: error)
        }
    }
    
    // Stop transcription
    func stopTranscription() {
        guard isRecording else { return }
        
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false
        
        // Process any remaining audio chunks
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            self.processAudioChunks()
        }
    }
    
    // Process collected audio chunks
    private func processAudioChunks() {
        guard !audioChunks.isEmpty else { return }
        
        var chunksToProcess: [Data] = []
        
        audioQueue.sync {
            chunksToProcess = self.audioChunks
            self.audioChunks.removeAll()
        }
        
        // Combine chunks into a single audio file
        let combinedAudio = combineAudioChunks(chunksToProcess)
        
        // Send to Whisper API
        transcribeAudio(combinedAudio)
    }
    
    // Combine audio data chunks into a single WAV file
    private func combineAudioChunks(_ chunks: [Data]) -> Data {
        // In a real implementation, this would convert raw PCM data to a WAV file
        // For simplicity, we're just concatenating the chunks here
        let combinedData = NSMutableData()
        for chunk in chunks {
            combinedData.append(chunk)
        }
        return combinedData as Data
    }
    
    // Send audio data to OpenAI Whisper API
    private func transcribeAudio(_ audioData: Data) {
        // 오디오 데이터 WAV 형식으로 변환
        let wavData = convertToWAV(audioData)
        
        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(modelName)\r\n".data(using: .utf8)!)
        
        // Add language parameter (optional)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("ko\r\n".data(using: .utf8)!) // Korean language code
        
        // Add response_format parameter for timestamps
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("verbose_json\r\n".data(using: .utf8)!)
        
        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)
        
        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        print("Sending request to Whisper API...")
        
        recognitionTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("API Error: \(error.localizedDescription)")
                self.delegate?.transcriptionService(self, didFailWithError: error)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("HTTP Status: \(httpResponse.statusCode)")
            }
            
            guard let data = data else {
                let error = NSError(domain: "TranscriptionError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data received"])
                print("No data received from API")
                self.delegate?.transcriptionService(self, didFailWithError: error)
                return
            }
            
            // Print response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("API Response: \(responseString)")
            }
            
            do {
                let decoder = JSONDecoder()
                let transcription: WhisperResponse = try decoder.decode(WhisperResponse.self, from: data)
                print("Transcription successful with \(transcription.segments.count) segments!")
                self.delegate?.transcriptionService(self, didReceiveTranscription: transcription)
            } catch {
                print("JSON Decode Error: \(error)")
                self.delegate?.transcriptionService(self, didFailWithError: error)
            }
        }
        
        recognitionTask?.resume()
    }
    
    // PCM 데이터를 WAV 형식으로 변환
    private func convertToWAV(_ audioData: Data) -> Data {
        // WAV 헤더 생성 (간단한 형식)
        let fileSize = audioData.count + 44 - 8
        let sampleRate: UInt32 = 44100
        let bitDepth: UInt16 = 16
        let numChannels: UInt16 = 1
        let byteRate = sampleRate * UInt32(numChannels) * UInt32(bitDepth) / 8
        let blockAlign = numChannels * bitDepth / 8
        
        var header = Data()
        
        // RIFF 청크
        header.append("RIFF".data(using: .ascii)!)  // ChunkID
        header.append(UInt32(fileSize).littleEndianData)  // ChunkSize
        header.append("WAVE".data(using: .ascii)!)  // Format
        
        // fmt 청크
        header.append("fmt ".data(using: .ascii)!)  // Subchunk1ID
        header.append(UInt32(16).littleEndianData)  // Subchunk1Size (16 for PCM)
        header.append(UInt16(1).littleEndianData)   // AudioFormat (1 for PCM)
        header.append(numChannels.littleEndianData)  // NumChannels
        header.append(sampleRate.littleEndianData)  // SampleRate
        header.append(byteRate.littleEndianData)    // ByteRate (SampleRate * NumChannels * BitsPerSample/8)
        header.append(blockAlign.littleEndianData)  // BlockAlign (NumChannels * BitsPerSample/8)
        header.append(bitDepth.littleEndianData)    // BitsPerSample
        
        // data 청크
        header.append("data".data(using: .ascii)!)  // Subchunk2ID
        header.append(UInt32(audioData.count).littleEndianData)  // Subchunk2Size
        
        // 헤더와 오디오 데이터 결합
        var wavData = Data()
        wavData.append(header)
        wavData.append(audioData)
        
        return wavData
    }
}

// Extension for WAV header creation
extension UInt32 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}

extension UInt16 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt16>.size)
    }
} 