import Foundation

// WhisperSegment 모델
public struct WhisperSegment: Identifiable, Decodable, Encodable, Equatable {
    public let id: Int
    public let text: String
    public let start: Double
    public let end: Double
    
    public init(id: Int, text: String, start: Double, end: Double) {
        self.id = id
        self.text = text
        self.start = start
        self.end = end
    }
}

// 번역된 세그먼트 모델
public struct TranslatedSegment: Identifiable, Decodable, Encodable, Equatable {
    public let id: Int
    public let originalText: String
    public let translatedText: String
    public let start: Double
    public let end: Double
    
    public init(id: Int, originalText: String, translatedText: String, start: Double, end: Double) {
        self.id = id
        self.originalText = originalText
        self.translatedText = translatedText
        self.start = start
        self.end = end
    }
}

// Whisper API 응답 모델
public struct WhisperResponse: Decodable, Encodable {
    public let text: String
    public let segments: [WhisperSegment]
    
    public init(text: String, segments: [WhisperSegment]) {
        self.text = text
        self.segments = segments
    }
} 