import Combine
import Speech
import SwiftUI

let contextLimit = 10

struct Message: Identifiable {
    let id = UUID()
    let user: User
    let content: String
}

enum User {
    case me
    case assistant
}

class ViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var inputMessage: String = ""
    @Published var isInputing: Bool = false
    @Published var isRecording = false

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    var cancellable: AnyCancellable?

    func sendMessage() {
        messages.append(Message(user: .me, content: inputMessage))
        inputMessage = ""
        isInputing = false
        
        cancellable = OpenAIClient.publish(
            ChatCreateRequest(messages: Array(messages.suffix(contextLimit)))
        )
        .subscribe(on: DispatchQueue.global(qos: .background))
        .receive(on: DispatchQueue.main)
        .sink(receiveCompletion: { _ in
        }, receiveValue: { result in
            self.messages.append(Message(user: .assistant, content: result.choices.first!.message.content))
        })
    }

    func startRecording() {
        isRecording = true
        let audioSession = AVAudioSession.sharedInstance()
        try! audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try! audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { fatalError("Could not create request") }
        recognitionRequest.contextualStrings = ["ライツアパートメント", "ディーワイディーエックス"]
        recognitionRequest.shouldReportPartialResults = true

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            if let result = result {
                DispatchQueue.main.async {
                    print(result.bestTranscription.formattedString)
                    self?.inputMessage = result.bestTranscription.formattedString
                }
            } else if let error = error {
                print(error)
            }
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        try! audioEngine.start()
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()

        if let recognitionTask = recognitionTask, recognitionTask.state == .running {
            recognitionTask.finish()
        }

        isRecording = false
    }
}

struct ContentView: View {
    @ObservedObject var viewModel = ViewModel()

    var body: some View {
        VStack {
            ScrollView {
                ForEach(viewModel.messages) { message in
                    HStack {
                        if message.user == .me {
                            Spacer()
                            Text(message.content)
                                .font(.callout)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        } else {
                            HStack(alignment: .bottom) {
                                Image(systemName: "person.circle.fill")
                                    .frame(width: 25, height: 25)

                                Text(message.content)
                                    .font(.callout)
                                    .padding()
                                    .background(Color.gray)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .padding()

            VStack {
                HStack {
                    ZStack(alignment: .trailing) {
                        TextField("メッセージを入力", text: $viewModel.inputMessage, onEditingChanged: { editingChanged in
                            if editingChanged {
                                viewModel.isInputing = true
                            } else {
                                viewModel.isInputing = false
                            }
                        })
                            .textFieldStyle(PlainTextFieldStyle())
                            .frame(height: 40)
                            .padding(EdgeInsets(top: 0, leading: 15, bottom: 0, trailing: 15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.clear, lineWidth: 1)
                            )
                            .background(RoundedRectangle(cornerRadius: 20).fill(Color.gray.opacity(0.3)))

                        if !viewModel.isInputing {
                            Button(action: {
                                viewModel.startRecording()
                            }) {
                                Image(systemName: "waveform")
                                    .padding()
                            }
                        }
                    }

                    Button(action: {
                        viewModel.sendMessage()
                    }) {
                        Image(systemName: "arrow.up")
                            .frame(width: 40, height: 40)
                            .foregroundColor(Color.black)
                            .background(Color.blue)
                            .clipShape(Circle())
                    }
                }
                .padding()

                if viewModel.isRecording {
                    ZStack(alignment: .center) {
                        Circle()
                                .frame(width: 150,
                                       height: 150,
                                       alignment: .center)
                                .foregroundColor(.indigo.opacity(0.3))
                        
                        HStack {
                            Image(systemName: "stop.circle")
                            Text("録音停止").font(.callout)
                        }
                    }
                    .frame(
                        minWidth: 0,
                        maxWidth: .infinity,
                        minHeight: 200,
                        maxHeight: 200,
                        alignment: .center
                    )
                    .background(Color.blue)
                    .onTapGesture {
                        viewModel.stopRecording()
                    }
                }
            }
        }
    }
}
