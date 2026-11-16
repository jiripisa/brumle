import SwiftUI
import BrumleCore

/// Beside the pads: the khomus, "Pads", which pad is selected, and its pitch
/// and mute group. The pitch and the group belong to the pad, not to its
/// knobs.
struct PadInspectorView: View {

    let model: any InstrumentModel

    var body: some View {
        let pad = model.selectedPad
        VStack(spacing: 6) {
            KhomusView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            OrnamentBand()
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Pads")
                    .font(.system(size: 26, weight: .semibold, design: .serif))
                    .foregroundStyle(Artwork.silver)
                Text("Selected: \(PadLabel.title(pad, name: model.padName(pad)))")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(Artwork.bone)
                    .lineLimit(1)
            }
            HStack(spacing: 18) {
                labelled("Pitch") { pitchMenu(pad) }
                labelled("Group") { groupMenu(pad) }
            }
        }
        .padding(10)
        .glassEffect(.regular.tint(Artwork.midnight.opacity(0.35)), in: .rect(cornerRadius: 16))
    }

    private func labelled(_ title: String, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Artwork.bone)
            control()
        }
    }

    /// Every note, an octave to a submenu, the pad's own ticked.
    private func pitchMenu(_ pad: Int) -> some View {
        let note = model.padNote(pad)
        return Menu {
            ForEach(Notes.octaves, id: \.lowerBound) { octave in
                Menu("\(Notes.name(octave.lowerBound)) – \(Notes.name(octave.upperBound))") {
                    ForEach(Array(octave), id: \.self) { candidate in
                        Toggle(Notes.name(candidate), isOn: Binding(get: { candidate == note },
                                                                     set: { _ in model.setPadNote(candidate, pad: pad) }))
                    }
                }
            }
        } label: {
            Text(Notes.name(note))
                .font(.system(size: 13).monospacedDigit())
                .frame(width: 40, alignment: .leading)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .fixedSize()
        .help("The pad's pitch")
        .accessibilityLabel("Pitch")
    }

    /// Off, or one of the sixteen mute groups: a hit silences the pads of its group.
    private func groupMenu(_ pad: Int) -> some View {
        let group = model.padGroup(pad)
        return Menu {
            Toggle("Off", isOn: Binding(get: { group == nil }, set: { _ in model.setPadGroup(nil, pad: pad) }))
            Divider()
            ForEach(1...16, id: \.self) { candidate in
                Toggle("\(candidate)", isOn: Binding(get: { candidate == group },
                                                    set: { _ in model.setPadGroup(candidate, pad: pad) }))
            }
        } label: {
            Text(group.map(String.init) ?? "Off")
                .font(.system(size: 13).monospacedDigit())
                .frame(width: 30, alignment: .leading)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .fixedSize()
        .help("Off: a hit silences only this pad's previous hit. A group: a hit silences every pad of the group")
        .accessibilityLabel("Group")
    }
}
