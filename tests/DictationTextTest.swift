// How a dictation's words are assembled from the speech-to-text stream.
// The sequences below are replays of real messages captured from the service.
//   swiftc -o /tmp/quill-dictation-test Sources/DictationText.swift tests/DictationTextTest.swift && /tmp/quill-dictation-test
// Or simply: tests/run.sh
import Foundation

@main
enum DictationTextTest {
    static func main() {
        var failed = 0

        func expectEqual(_ name: String, _ got: String, _ want: String) {
            if got == want {
                print("ok   \(name)")
            } else {
                print("FAIL \(name)\n     got:  \(got.debugDescription)\n     want: \(want.debugDescription)")
                failed += 1
            }
        }

        typealias Step = (DictationTranscript.Kind, String)

        func run(_ steps: [Step]) -> String {
            var transcript = DictationTranscript()
            for (kind, text) in steps { transcript.apply(text, kind: kind) }
            return transcript.text
        }

        // Two sentences separated by long pauses: every chunk closes, then the
        // utterance final repeats it.
        expectEqual("a closed chunk repeated by the utterance final is not doubled", run([
            (.chunkFinal, "Please send the report to Maria by Friday afternoon."),
            (.utteranceFinal, "Please send the report to Maria by Friday afternoon."),
            (.interim, ""),
            (.chunkFinal, "Also remind her about the budget meeting next week."),
            (.utteranceFinal, "Also remind her about the budget meeting next week."),
            (.chunkFinal, "Thanks a lot."),
            (.utteranceFinal, "Thanks a lot."),
        ]), "Please send the report to Maria by Friday afternoon. Also remind her about the budget meeting next week. Thanks a lot.")

        // The bug that put "Because the. And honestly I would." on the end of a
        // dictation: drafts of a chunk were left behind when its close arrived
        // under a different start time. Here the drafts are interims.
        expectEqual("drafts are replaced by the chunk's close, not left behind", run([
            (.chunkFinal, "So I was thinking."),
            (.chunkFinal, "That we should move the launch to Tuesday."),
            (.interim, "Because the."),
            (.chunkFinal, "Because the design team needs more time."),
            (.interim, "And honestly I would."),
            (.chunkFinal, "And honestly I would rather ship something polished than something rushed."),
            (.chunkFinal, "What do you think about that?"),
            (.utteranceFinal, "So I was thinking. That we should move the launch to Tuesday. Because the design team needs more time. And honestly I would rather ship something polished than something rushed. What do you think about that?"),
        ]), "So I was thinking. That we should move the launch to Tuesday. Because the design team needs more time. And honestly I would rather ship something polished than something rushed. What do you think about that?")

        expectEqual("a draft grows in place", run([
            (.interim, "Hello"),
            (.interim, "Hello there"),
            (.interim, "Hello there my friend"),
        ]), "Hello there my friend")

        expectEqual("an empty draft never wipes words already heard", run([
            (.chunkFinal, "First sentence."),
            (.interim, ""),
            (.interim, "Second"),
            (.interim, ""),
        ]), "First sentence. Second")

        expectEqual("a stop mid-sentence keeps the unfinished words", run([
            (.chunkFinal, "Send it now."),
            (.interim, "and tell her"),
        ]), "Send it now. and tell her")

        expectEqual("a close with no text keeps the draft", run([
            (.interim, "Almost done"),
            (.chunkFinal, ""),
        ]), "Almost done")

        expectEqual("an utterance final alone becomes the text", run([
            (.utteranceFinal, "Just this."),
        ]), "Just this.")

        expectEqual("an utterance final closes an open chunk with its full words", run([
            (.interim, "Meet me at"),
            (.utteranceFinal, "Meet me at noon."),
        ]), "Meet me at noon.")

        expectEqual("only the tail of an utterance final is added to an open chunk", run([
            (.chunkFinal, "Hello there."),
            (.interim, "How are"),
            (.utteranceFinal, "Hello there. How are you?"),
        ]), "Hello there. How are you?")

        expectEqual("a second identical utterance final adds nothing", run([
            (.utteranceFinal, "Only once."),
            (.utteranceFinal, "Only once."),
        ]), "Only once.")

        expectEqual("saying a thing twice keeps both", run([
            (.chunkFinal, "No."),
            (.utteranceFinal, "No."),
            (.chunkFinal, "No."),
            (.utteranceFinal, "No."),
        ]), "No. No.")

        // The service's own consolidated transcript wins over what was assembled.
        var consolidated = DictationTranscript()
        consolidated.apply("rough draft", kind: .interim)
        consolidated.replaceAll(with: "The clean final text.")
        expectEqual("a consolidated transcript replaces everything", consolidated.text, "The clean final text.")

        var kept = DictationTranscript()
        kept.apply("Keep this.", kind: .chunkFinal)
        kept.replaceAll(with: "   ")
        expectEqual("an empty consolidated transcript keeps what was heard", kept.text, "Keep this.")

        var empty = DictationTranscript()
        expectEqual("nothing heard is empty", empty.text, "")
        empty.apply("", kind: .interim)
        expectEqual("an empty draft is still empty", empty.text, "")

        if failed > 0 {
            print("\n\(failed) failed")
            exit(1)
        }
        print("\nall passed")
    }
}
