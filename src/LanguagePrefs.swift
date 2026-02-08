import Foundation

enum LanguagePrefs {
    private static let codeKey = "language.code.v1"

    static var code: String? {
        get { UserDefaults.standard.string(forKey: codeKey) }
        set { UserDefaults.standard.set(newValue, forKey: codeKey) }
    }
}
