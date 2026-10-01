import Foundation

/// The words of one dictation, assembled from what the speech-to-text service
/// sends back.
///
/// The service is followed as a sequence, never by timestamp. Measured against
/// the live endpoint, a chunk's drafts carry the chunk's `start` but the message
/// that closes it carries the whole utterance's — so anything keyed by `start`
/// keeps the abandoned draft ("Because the.") next to its finished version
/// ("Because the design team needs more time.") and the dictation ends with
/// stray, repeated fragments.
///
/// Interim text grows the chunk being spoken. A chunk final closes it. The
/// utterance final that follows a pause repeats every chunk since the previous
/// pause and adds nothing new.
struct DictationTranscript {

    enum Kind {
        case interim
        case chunkFinal
        case utteranceFinal
    }

    private var closed: [String] = []
    /// The chunk still being spoken.
    private var open = ""
    /// Everything closed since the last pause, joined — what the next utterance
    /// final will repeat.
    private var sincePause = ""

    var text: String {
        (open.isEmpty ? closed : closed + [open]).joined(separator: " ")
    }

    var isEmpty: Bool { closed.isEmpty && open.isEmpty }

    mutating func apply(_ raw: String, kind: Kind) {
        let words = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        switch kind {
        case .interim:
            // An empty draft is the server clearing its buffer between chunks;
            // it must never wipe words already heard.
            if !words.isEmpty { open = words }

        case .chunkFinal:
            close(words.isEmpty ? open : words)

        case .utteranceFinal:
            let repeated = sincePause
            sincePause = ""
            if !repeated.isEmpty {
                // A repeat of what is already closed. Only a chunk still open
                // (its own close never came) can gain words from it: whatever
                // follows everything already closed.
                guard !open.isEmpty else { return }
                let tail = words.hasPrefix(repeated)
                    ? String(words.dropFirst(repeated.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""
                close(tail.isEmpty ? open : tail)
                return
            }
            if !open.isEmpty {
                close(words.isEmpty ? open : words)
            } else if !words.isEmpty, !text.hasSuffix(words) {
                close(words)
            }
        }
    }

    /// The service handed over its own consolidated transcript; it replaces
    /// everything assembled so far.
    mutating func replaceAll(with consolidated: String) {
        let words = consolidated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        closed = [words]
        open = ""
        sincePause = ""
    }

    private mutating func close(_ words: String) {
        open = ""
        guard !words.isEmpty else { return }
        closed.append(words)
        sincePause = sincePause.isEmpty ? words : sincePause + " " + words
    }
}
