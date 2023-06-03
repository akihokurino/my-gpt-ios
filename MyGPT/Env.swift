import Foundation

enum Env {
    static let openAIApiKey = Bundle.main.object(forInfoDictionaryKey: "OpenAI ApiKey") as! String
}
