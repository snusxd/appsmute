import Foundation

struct Shortcut: Codable, Equatable, Identifiable {
    var id: UUID
    var carbonID: UInt32
    var keyCode: UInt32
    var modifiers: UInt32
}
