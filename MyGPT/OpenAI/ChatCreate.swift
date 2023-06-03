import Alamofire
import Foundation

class ChatCreateRequest: OpenAIRequestProtocol {
    typealias ResponseType = ChatCreateResponse

    let model: String
    let maxTokens: Int
    let temperature: Double
    let messages: [MessageRequest]

    init(messages: [Message]) {
        self.model = "gpt-3.5-turbo"
        self.maxTokens = 128
        self.temperature = 0.8
        self.messages = messages.map { MessageRequest(role: $0.user == .me ? "user" : "assistant", content: $0.content) }
    }

    var parameters: Parameters? {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let jsonData = try! encoder.encode(_ChatCreateRequest(model: model, maxTokens: maxTokens, temperature: temperature, messages: messages))
        let jsonObject = try! JSONSerialization.jsonObject(with: jsonData, options: [])
        let params = jsonObject as! [String: Any]
        return params
    }

    var method: HTTPMethod {
        return .post
    }

    var path: String {
        return "/v1/chat/completions"
    }

    var allowsConstrainedNetworkAccess: Bool {
        return false
    }
}

struct _ChatCreateRequest: Codable, Equatable {
    let model: String
    let maxTokens: Int
    let temperature: Double
    let messages: [MessageRequest]
}

struct MessageRequest: Codable, Equatable {
    let role: String
    let content: String
}

struct ChatCreateResponse: Codable, Equatable {
    let id: String
    let object: String
    let created: Int
    let choices: [ChoiceResponse]
    let usage: UsageResponse
}

struct ChoiceResponse: Codable, Equatable {
    let index: Int
    let message: MessageResponse
    let finishReason: String
}

struct MessageResponse: Codable, Equatable {
    let role: String
    let content: String
}

struct UsageResponse: Codable, Equatable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
}
