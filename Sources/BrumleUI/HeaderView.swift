import SwiftUI
import BrumleCore

/// The top of the panel: the emblem and the wordmark, the Program menu (it
/// loads into the set the knobs show), the mode switch (Keyboard | Pads) and
/// the buttons LFO 1, LFO 2 and VEL, which turn the knobs into that source's
/// amounts. Room is left for the Preset menu and the MIDI button. `trailing`
/// comes last, on the right.
struct HeaderView<Trailing: View>: View {

    let model: any InstrumentModel
    @Binding var editing: KnobEditing
    let trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            wordmark
            separator
            programMenu
            Spacer(minLength: 16)
            GlassSegments(label: "Mode", titles: ["Keyboard", "Pads"], selected: model.mode.rawValue, fontSize: 13) { index in
                model.mode = PlayMode(rawValue: index) ?? .keyboard
            }
            .help("Keyboard: the keys play the keyboard's sound. Pads: notes 36–51 hit the sixteen pads")
            separator
            HStack(spacing: 8) {
                // One at a time: the knobs can be one thing.
                ForEach(0..<LFOs.count, id: \.self) { lfo in
                    sourceButton("LFO \(lfo + 1)", .amount(lfo: lfo),
                                 help: "Drag the knobs to set how far LFO \(lfo + 1) moves them")
                }
                sourceButton("VEL", .velocity, help: "Drag the knobs to set how far a softer hit moves them")
            }
            trailing
        }
        .frame(height: 48)
    }

    private var wordmark: some View {
        HStack(spacing: 10) {
            if let logo = Artwork.logo {
                Image(nsImage: logo).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(height: 40)
            }
            Text("Brumle")
                .font(.system(size: 34, weight: .semibold, design: .serif))
                .foregroundStyle(Artwork.silver)
        }
        .accessibilityElement(children: .combine)
    }

    private var separator: some View {
        Rectangle().fill(Artwork.silver.opacity(0.25)).frame(width: 1, height: 34)
    }

    /// The built-in programs, the one the shown set came from ticked.
    private var programMenu: some View {
        let set = model.shownSet
        let program = model.program(in: set)
        return VStack(alignment: .leading, spacing: 2) {
            Text("Program")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Artwork.bone)
                .padding(.leading, 6)
            Menu {
                ForEach(Programs.names.indices, id: \.self) { index in
                    Toggle(Programs.names[index], isOn: Binding(get: { program == index },
                                                                set: { _ in model.loadProgram(index, into: set) }))
                }
            } label: {
                // One width for every name, so that the header stands still.
                Text(Programs.names.indices.contains(program) ? Programs.names[program] : "—")
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .frame(width: 112, alignment: .leading)
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .fixedSize()
            .help(set == .keyboard ? "Load a built-in program into the keyboard's sound"
                                   : "Load a built-in program into the selected pad")
            .accessibilityLabel("Program")
        }
    }

    /// A button that turns the knobs into a source's amounts and back: its
    /// colour as a dot, the glass tinted with it while it is on.
    private func sourceButton(_ title: String, _ source: KnobEditing, help: String) -> some View {
        let on = editing == source
        return Button {
            editing = on ? .value : source
        } label: {
            HStack(spacing: 6) {
                Circle().fill(on ? Artwork.midnight.opacity(0.7) : source.colour).frame(width: 7, height: 7)
                Text(title)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(on ? Artwork.midnight : Artwork.silver)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Capsule())
            .glassEffect(on ? .regular.tint(source.colour).interactive() : .regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .help(on ? "Back to the knobs" : help)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
