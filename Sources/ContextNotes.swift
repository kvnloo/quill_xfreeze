import Foundation

/// What the speaker has told Quill about the words they use: names, products,
/// jargon, a line about what they work on.
///
/// Written by the user and nothing else — nothing is read off the screen or out
/// of other apps to build it. It is used only by grammar cleanup, to spell a word
/// the way the speaker does when the transcriber has misheard it.
enum ContextNotes {

    static let key = "contextNotes"
    /// Sent with every cleanup request, so it is kept short enough not to slow
    /// one down.
    static let maxLength = 2000

    static var text: String {
        get { UserDefaults.standard.string(forKey: key) ?? "" }
        set {
            let tidy = normalise(newValue)
            if tidy.isEmpty {
                UserDefaults.standard.removeObject(forKey: key)
            } else {
                UserDefaults.standard.set(tidy, forKey: key)
            }
        }
    }

    static var isEmpty: Bool { text.isEmpty }

    /// Trailing spaces and runs of blank lines removed, and cut at the last whole
    /// line or word within the limit rather than mid-word.
    static func normalise(_ raw: String) -> String {
        let lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var kept: [String] = []
        for line in lines {
            if line.isEmpty, kept.last?.isEmpty ?? true { continue }
            kept.append(line)
        }
        var text = kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        if text.count > maxLength {
            var cut = String(text.prefix(maxLength))
            if let boundary = cut.lastIndex(where: { $0.isWhitespace }) {
                cut = String(cut[..<boundary])
            }
            text = cut.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}
