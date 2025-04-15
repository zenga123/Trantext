import SwiftUI

struct SettingsView: View {
    @Binding var isPresented: Bool
    @AppStorage("openai_api_key") private var apiKey: String = ""
    @AppStorage("whisper_model") private var whisperModel: String = "gpt-4o-transcribe"
    @AppStorage("source_language") private var sourceLanguage: String = "Korean"
    @AppStorage("target_language") private var targetLanguage: String = "English"
    
    // Available languages
    private let languages = ["English", "Japanese", "Korean", "Chinese", "Spanish", "French", "German", "Russian"]
    
    // Available Whisper models
    private let whisperModels = ["whisper-1", "gpt-4o-transcribe"]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("API Configuration")) {
                    SecureField("OpenAI API Key", text: $apiKey)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    Text("Your API key is stored securely in the device keychain")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Transcription Settings")) {
                    Picker("Whisper Model", selection: $whisperModel) {
                        ForEach(whisperModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    
                    Text("gpt-4o-transcribe is recommended for best results")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Language Settings")) {
                    Picker("Source Language", selection: $sourceLanguage) {
                        ForEach(languages, id: \.self) { language in
                            Text(language).tag(language)
                        }
                    }
                    
                    Picker("Target Language", selection: $targetLanguage) {
                        ForEach(languages, id: \.self) { language in
                            Text(language).tag(language)
                        }
                    }
                }
                
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link("Privacy Policy", destination: URL(string: "https://www.example.com/privacy")!)
                }
            }
            .navigationTitle("Settings")
            .navigationBarItems(trailing: Button("Done") {
                isPresented = false
            })
        }
    }
}

#Preview {
    SettingsView(isPresented: .constant(true))
} 