// Tidying the notes a speaker writes before they are stored and sent.
//   swiftc -o /tmp/quill-notes-test Sources/ContextNotes.swift tests/ContextNotesTest.swift && /tmp/quill-notes-test
// Or simply: tests/run.sh
import Foundation

@main
enum ContextNotesTest {
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

        expectEqual("plain lines are kept", ContextNotes.normalise("Kubernetes\nPostgres"), "Kubernetes\nPostgres")
        expectEqual("surrounding blank space is removed", ContextNotes.normalise("\n\n  Kubernetes  \n\n"), "Kubernetes")
        expectEqual("runs of blank lines become one", ContextNotes.normalise("a\n\n\n\n\nb"), "a\n\nb")
        expectEqual("windows line endings", ContextNotes.normalise("a\r\nb\r\n"), "a\nb")
        expectEqual("nothing at all", ContextNotes.normalise("   \n \n"), "")

        let long = String(repeating: "Kubernetes ", count: 400)
        let cut = ContextNotes.normalise(long)
        expectEqual("long notes are cut", String(cut.count <= ContextNotes.maxLength), "true")
        expectEqual("long notes are cut at a whole word", String(cut.hasSuffix("Kubernetes")), "true")

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: ContextNotes.key)
        expectEqual("starts empty", ContextNotes.text, "")
        ContextNotes.text = "  Okonkwo \n\n\n Bluebird "
        expectEqual("stored tidy", ContextNotes.text, "Okonkwo\n\nBluebird")
        ContextNotes.text = "   "
        expectEqual("clearing removes it", String(defaults.object(forKey: ContextNotes.key) == nil), "true")

        if failed > 0 {
            print("\n\(failed) failed")
            exit(1)
        }
        print("\nall passed")
    }
}
