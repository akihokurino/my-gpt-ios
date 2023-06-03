import Foundation

let defaultErrorMessage = "エラーが発生しました"

enum AppError: Error, Equatable {
    case plain(String)
    
    static func defaultError() -> AppError {
        return .plain(defaultErrorMessage)
    }
}
