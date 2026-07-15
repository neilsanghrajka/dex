import Foundation

enum BoardPresentationMode: String, CaseIterable, Codable, Identifiable {
    case fullScreen
    case compactIsland

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullScreen:
            "Full Screen"
        case .compactIsland:
            "Compact Island"
        }
    }
}
