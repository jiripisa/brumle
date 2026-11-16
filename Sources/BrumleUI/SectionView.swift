import SwiftUI
import BrumleCore

/// One group of controls (Reed, Stroke, Mouth, Breath, Master) on a glass
/// panel: its title, then its knobs and switches where `SectionLayout` puts
/// them.
struct SectionView: View {

    let section: ParameterSection
    let set: SoundSet
    let model: any InstrumentModel
    let editing: KnobEditing

    var body: some View {
        let layout = SectionLayout.of(section)
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title)
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(Artwork.silver)
                .padding(.leading, 4)
            Rectangle()
                .fill(Artwork.silver.opacity(0.18))
                .frame(height: 1)
            Grid(horizontalSpacing: 2, verticalSpacing: 4) {
                ForEach(layout.rows.indices, id: \.self) { index in
                    switch layout.rows[index] {
                    case .cells(let parameters):
                        GridRow {
                            ForEach(parameters) { control($0) }
                        }
                    case .wide(let parameter):
                        control(parameter)
                            .gridCellColumns(layout.columns)
                            .padding(.top, 2)
                    }
                }
            }
        }
        .padding(8)
        // Room to spare goes to every group alike; each is as tall as the tallest.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular.tint(Artwork.midnight.opacity(0.35)), in: .rect(cornerRadius: 16))
    }

    @ViewBuilder
    private func control(_ parameter: Parameter) -> some View {
        if parameter.isChoice {
            ChoiceView(parameter: parameter, set: set, model: model, editing: editing)
        } else {
            KnobView(parameter: parameter, set: set, model: model, editing: editing)
        }
    }
}

/// A switch: its name above a glass segmented control with every choice
/// (Stroke, Key Up, Curve, LFO Start), or a glass menu where the choices are
/// many (the LFO shapes). Velocity and the LFOs move no switch, so it steps
/// back while their amounts are being set.
struct ChoiceView: View {

    let parameter: Parameter
    let set: SoundSet
    let model: any InstrumentModel
    let editing: KnobEditing

    /// More choices than this make a menu.
    private static let segmentsAtMost = 4

    var body: some View {
        let choices = parameter.choices
        let chosen = Int(model.value(of: parameter, in: set).rounded())
        VStack(spacing: 4) {
            Text(parameter.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Artwork.bone)
                .lineLimit(1)
                .fixedSize()
            if choices.count > Self.segmentsAtMost {
                Menu {
                    ForEach(choices.indices, id: \.self) { index in
                        Toggle(choices[index], isOn: Binding(get: { index == chosen }, set: { _ in choose(index) }))
                    }
                } label: {
                    Text(choices.indices.contains(chosen) ? choices[chosen] : "—")
                        .font(.system(size: 12))
                }
                .menuStyle(.button)
                .buttonStyle(.glass)
                .frame(width: KnobView.width - 4)
                .accessibilityLabel(parameter.name)
            } else {
                GlassSegments(label: parameter.name, titles: choices, selected: chosen, action: choose)
            }
        }
        .opacity(editing.stepsBack(parameter) ? 0.3 : 1)
        .allowsHitTesting(!editing.stepsBack(parameter))
    }

    /// One click is one edit: a host records it as a gesture of its own.
    private func choose(_ index: Int) {
        model.beginEditing(parameter, in: set)
        model.setPosition(Double(parameter.normalised(Float(index))), of: parameter, in: set)
        model.endEditing(parameter, in: set)
    }
}

/// Choices side by side in a glass capsule; the chosen one lit in aurora.
/// Drawn here rather than left to the system's segmented picker, so that it
/// shows what is chosen in a window that is not in front (a plug-in's, in a
/// host).
struct GlassSegments: View {

    /// What the choice is, for VoiceOver ("Stroke", "Mode").
    let label: String
    let titles: [String]
    let selected: Int
    var fontSize: CGFloat = 12
    let action: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(titles.indices, id: \.self) { index in
                let on = index == selected
                Button { action(index) } label: {
                    Text(titles[index])
                        .font(.system(size: fontSize, weight: on ? .semibold : .regular))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(on ? Artwork.midnight : Artwork.silver)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(on ? Artwork.aurora : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .glassEffect(.regular.tint(Artwork.midnight.opacity(0.4)).interactive(), in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}
