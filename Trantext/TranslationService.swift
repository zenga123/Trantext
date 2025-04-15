import Foundation
// Model 폴더의 타입 사용

class TranslationService {
    private let apiKey: String
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    // Translate text from source language to target language
    func translateText(_ text: String, from sourceLanguage: String, to targetLanguage: String, completion: @escaping (Result<String, Error>) -> Void) {
        // Using OpenAI Translation API (we could switch to Google Translate or other services)
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let systemPrompt = "You are a professional translator. Translate the following text from \(sourceLanguage) to \(targetLanguage). Preserve the meaning and tone of the original text. Only respond with the translated text, nothing else."
        
        let requestBody: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.3
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = jsonData
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let data = data else {
                    completion(.failure(NSError(domain: "TranslationError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let choices = json["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let message = firstChoice["message"] as? [String: Any],
                       let content = message["content"] as? String {
                        completion(.success(content))
                    } else {
                        throw NSError(domain: "TranslationError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
                    }
                } catch {
                    completion(.failure(error))
                }
            }
            
            task.resume()
        } catch {
            completion(.failure(error))
        }
    }
    
    // Batch translate multiple segments
    func translateSegments(_ segments: [WhisperSegment], from sourceLanguage: String, to targetLanguage: String, completion: @escaping (Result<[TranslatedSegment], Error>) -> Void) {
        let dispatchGroup = DispatchGroup()
        var translatedSegments: [TranslatedSegment] = []
        var translationError: Error?
        
        for segment in segments {
            dispatchGroup.enter()
            
            translateText(segment.text, from: sourceLanguage, to: targetLanguage) { result in
                switch result {
                case .success(let translatedText):
                    let translatedSegment = TranslatedSegment(
                        id: segment.id,
                        originalText: segment.text,
                        translatedText: translatedText,
                        start: segment.start,
                        end: segment.end
                    )
                    translatedSegments.append(translatedSegment)
                    
                case .failure(let error):
                    translationError = error
                }
                
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            if let error = translationError {
                completion(.failure(error))
            } else {
                // Sort segments by id to maintain original order
                let sortedSegments = translatedSegments.sorted { $0.id < $1.id }
                completion(.success(sortedSegments))
            }
        }
    }
} 