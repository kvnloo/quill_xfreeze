import Foundation

/// Decides whether a model's "corrected" dictation can be trusted.
///
/// A correction keeps the speaker's words and changes how they are written. An
/// answer, a refusal or a rewrite does not, so the result is only used when it
/// still reads as the same sentence — otherwise the original goes in untouched.
enum PolishGuard {

    /// Models occasionally wrap the answer in quotes, a code fence or the tags
    /// the request was wrapped in.
    static func clean(_ text: String) -> String {
        var out = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.hasPrefix("```") {
            out = out.replacingOccurrences(of: "^```[a-zA-Z]*\\n?|```$", with: "",
                                           options: .regularExpression)
                     .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        out = out.replacingOccurrences(of: "</?dictation>", with: "", options: [.regularExpression, .caseInsensitive])
                 .trimmingCharacters(in: .whitespacesAndNewlines)
        if out.count > 1, out.hasPrefix("\""), out.hasSuffix("\"") {
            out = String(out.dropFirst().dropLast())
        }
        return out
    }

    /// Is this plausibly the same dictation, only tidied?
    ///
    /// Two things have to hold. Nearly every original word must survive — a
    /// rewrite fails that. And almost nothing may be added — an answer fails
    /// that: "what is the capital of france" → "The capital of France is Paris."
    /// keeps five of six words and passed the first test on its own.
    ///
    /// `vocabulary` is words the speaker has told us they use. Writing a
    /// misheard word the way they spell it ("cooper nettys" → "Kubernetes") adds
    /// a word that was never in the dictation, and that is the one addition a
    /// correction is allowed.
    static func resembles(original: String, candidate: String, vocabulary: Set<String> = []) -> Bool {
        guard !candidate.isEmpty else { return false }

        let ratio = Double(candidate.count) / Double(max(original.count, 1))
        guard ratio > 0.6, ratio < 1.8 else { return false }

        let originalWords = words(original)
        guard !originalWords.isEmpty else { return false }
        let candidateWords = words(candidate)

        let originalSet = Set(originalWords)
        let candidateSet = Set(candidateWords)

        let kept = originalWords.filter { candidateSet.contains($0) }.count
        let missing = originalWords.count - kept

        // A word the speaker's notes supply stands in for one the transcriber got
        // wrong, so each can account for one original word that is no longer
        // there — provided it is spelled something like what it replaced. Without
        // that, a notes word could be swapped in for any word at all.
        var seen = Set<String>()
        let newWords = candidateWords.filter { !originalSet.contains($0) && seen.insert($0).inserted }
        let supplied = newWords.filter { vocabulary.contains($0) }
        var explained = 0
        if !supplied.isEmpty, missing > 0 {
            let dropped = originalWords.filter { !candidateSet.contains($0) && !fillers.contains($0) }.joined()
            if !dropped.isEmpty, similarity(dropped, supplied.joined()) >= 0.4 {
                explained = min(missing, supplied.count)
            }
        }
        guard Double(kept + explained) / Double(originalWords.count) >= 0.7 else { return false }

        // Fixing grammar does not introduce vocabulary. A short sentence gets no
        // allowance at all: one new word in six is already a different sentence.
        let unexplained = newWords.count - explained
        let allowance = originalWords.count < 8 ? 0 : originalWords.count / 10
        return unexplained <= allowance
    }

    private static let fillers: Set<String> = ["um", "uh", "uhm", "er", "erm", "ah", "hmm", "mm"]

    /// 1 for identical strings, 0 for nothing in common: one minus the edit
    /// distance over the longer length. Loose on purpose — a mishearing can be
    /// several letters and a word boundary away ("coopernettys", "kubernetes").
    static func similarity(_ a: String, _ b: String) -> Double {
        let x = Array(a), y = Array(b)
        let longest = max(x.count, y.count)
        guard longest > 0 else { return 1 }
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        var previous = Array(0...y.count)
        for i in 1...x.count {
            var row = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                row[j] = min(previous[j] + 1, row[j - 1] + 1, previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            previous = row
        }
        return 1 - Double(previous[y.count]) / Double(longest)
    }

    static func words(_ text: String) -> [String] {
        // Apostrophes are removed rather than treated as separators. Adding one is
        // the single most common correction — arent → aren't, dont → don't,
        // well → we'll — and splitting on it made those look like a rewrite, so
        // the guard rejected exactly the fixes it should have allowed.
        text.lowercased()
            .replacingOccurrences(of: "['\u{2019}]", with: "", options: .regularExpression)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
