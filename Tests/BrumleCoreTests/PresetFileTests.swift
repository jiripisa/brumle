import Foundation
import Testing
@testable import BrumleCore

/// A preset or kit file written by another version, or damaged: read as far as it can be, never a crash.
@Suite("Preset files")
struct PresetFileTests {

    private func library() -> PresetLibrary { PresetLibraryTests.library() }

    private func write(_ text: String, as name: String, in library: PresetLibrary, extension ext: String = "brumle") throws {
        try FileManager.default.createDirectory(at: library.folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: library.folder.appendingPathComponent("\(name).\(ext)"))
    }

    private func remove(_ library: PresetLibrary) {
        try? FileManager.default.removeItem(at: library.folder.deletingLastPathComponent())
    }

    @Test("A file with fields missing takes the defaults, and a field of a later version is ignored")
    func tolerant() throws {
        let library = library()
        defer { remove(library) }
        try write(#"{"values":{"vowel":50}}"#, as: "No program", in: library)
        try write(#"{"program":3}"#, as: "No values", in: library)
        try write("{}", as: "Empty", in: library)
        try write(#"{"program":2,"values":{"vowel":50,"from-the-future":1},"preset":"Old name","midi":[1,2],"colour":"aurora"}"#,
                  as: "Future", in: library)

        #expect(try library.load("No program") == SetState(program: 0, values: ["vowel": 50]))
        #expect(try library.load("No values") == SetState(program: 3, values: [:]))
        #expect(try library.load("Empty") == SetState(program: 0, values: [:]))
        let future = try library.load("Future")
        #expect(future.program == 2 && future.values["vowel"] == 50 && future.preset == "Old name")
    }

    @Test("A file that is not JSON, or has a field of the wrong type, is an error, not a crash")
    func damaged() throws {
        let library = library()
        defer { remove(library) }
        try write("not a preset", as: "Broken", in: library)
        try write("", as: "Blank", in: library)
        try write(#"{"program":"two"}"#, as: "Wrong type", in: library)
        try write(#"{"values":{"vowel":"loud"}}"#, as: "Wrong value", in: library)
        try write("[1,2,3]", as: "Array", in: library)
        for name in ["Broken", "Blank", "Wrong type", "Wrong value", "Array"] {
            #expect(throws: PresetError.unreadable(name)) { try library.load(name) }
        }
        #expect(library.names().count == 5)
    }

    @Test("Errors read as sentences for the menu")
    func messages() {
        #expect(PresetError.noName.errorDescription == "A name is needed.")
        #expect(PresetError.missing("X").errorDescription?.contains("“X”") == true)
        #expect(PresetError.unreadable("X").errorDescription?.contains("damaged") == true)
    }
}
