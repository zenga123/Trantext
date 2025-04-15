# Trantext

Trantext is an iOS app that provides real-time translation subtitles for YouTube videos. It uses OpenAI's Whisper model for speech recognition and language translation capabilities to help users understand content in foreign languages.

## Features

- Play YouTube videos directly in the app
- Real-time speech recognition using OpenAI Whisper
- Translate subtitles between multiple languages
- Highlight current speech segment for better readability
- Customizable source and target languages
- Secure API key storage

## Technical Stack

- **Platform**: iOS
- **Language**: Swift
- **UI Framework**: SwiftUI
- **Web Content**: WKWebView with YouTube iframe integration
- **Speech Recognition**: OpenAI Whisper API
- **Translation**: OpenAI GPT API

## Setup

1. Clone the repository
2. Open the project in Xcode
3. Obtain an OpenAI API key from [OpenAI Platform](https://platform.openai.com)
4. Add your API key in the app settings
5. Build and run the application

## Usage

1. Enter a YouTube video URL or video ID
2. Press "Load" to start playing the video
3. The app will automatically transcribe and translate the speech
4. Real-time subtitles will appear below the video with the current segment highlighted
5. Adjust language settings in the app's settings (gear icon)

## Limitations

- YouTube audio extraction relies on playing the video and capturing audio output
- The accuracy of transcription depends on the Whisper model's capabilities
- Translation quality may vary based on language pair and content complexity
- Internet connection required for API calls

## Future Enhancements

- Support for more languages
- Offline mode with local models
- Custom subtitle styling
- Export/share subtitles
- Picture-in-picture support

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- OpenAI for providing the Whisper and GPT APIs
- YouTube for the video content 