import AppKit
import SwiftUI
import BrumleCore

/// What the knobs of the panel edit at the moment.
public enum KnobEditing: Equatable, Sendable {
    /// Their values.
    case value
    /// How far an LFO (0 for the first) moves them.
    case amount(lfo: Int)
    /// How far the velocity of a hit moves them.
    case velocity

    /// The amount a knob sets while this is on; nil for its value, and for a
    /// knob this source cannot move.
    func amount(of parameter: Parameter) -> Parameter? {
        switch self {
        case .value: nil
        case .amount(let lfo): LFOs.amount(of: parameter, lfo: lfo)
        case .velocity: Velocity.amount(of: parameter)
        }
    }

    /// Whether a control is out of play: an LFO's or the velocity's button is
    /// on and the control has no amount for it.
    func stepsBack(_ parameter: Parameter) -> Bool {
        self != .value && amount(of: parameter) == nil
    }

    /// The colour of the source whose amounts are being set.
    @MainActor var colour: Color {
        switch self {
        case .value: Artwork.silver
        case .amount(let lfo): Artwork.lfo(lfo)
        case .velocity: Artwork.vel
        }
    }
}

/// One parameter as a knob: its name, a value arc around the cap, the value
/// below. Drag up and down to turn it (Shift for fine steps), double-click to
/// go back to the program's value.
///
/// A knob an LFO or the velocity moves shows a thin arc in that source's
/// colour: the part of its travel the LFO sweeps, or the way a softer hit
/// moves it. While a source's button in the header is on, the knob sets that
/// source's amount instead of its own value: the same drag and double click,
/// the amount below. Knobs the source cannot move step back meanwhile.
public struct KnobView: View {

    private let parameter: Parameter
    private let set: SoundSet
    private let model: any InstrumentModel
    private let editing: KnobEditing

    /// The drag under way, as one edit; nil between drags.
    @State private var edit: KnobEdit?
    /// True while the mouse drags the knob; SwiftUI puts it back when a drag
    /// stops in any way, also one cancelled without `onEnded`.
    @GestureState private var dragging = false

    /// The room a knob takes in a section's grid.
    public static var width: CGFloat { 74 }

    private static let sweep = 270.0          // degrees of travel
    private static let cap: CGFloat = 44      // the cap's artwork; its disc is about 80 % of it
    private static let dial: CGFloat = 56     // the value arc's outer edge

    public init(parameter: Parameter, set: SoundSet, model: any InstrumentModel, editing: KnobEditing = .value) {
        self.parameter = parameter
        self.set = set
        self.model = model
        self.editing = editing
    }

    /// The amount this knob is setting right now, if a source's button is on
    /// and that source can move the knob.
    private var amount: Parameter? { editing.amount(of: parameter) }

    /// What a drag and a double click act on: the amount while one is being set, else the knob.
    private var edited: Parameter { amount ?? parameter }

    public var body: some View {
        let position = model.position(of: parameter, in: set)
        VStack(spacing: 0) {
            Text(parameter.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Artwork.bone)
                .lineLimit(1)
            ZStack {
                arc(from: 0, to: 1)
                    .stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .padding(1.5)
                arc(from: parameter.isBipolar ? min(0.5, position) : 0, to: parameter.isBipolar ? max(0.5, position) : position)
                    .stroke(Artwork.aurora.opacity(amount == nil ? 1 : 0.4), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .padding(1.5)
                modulationArcs(position: position)
                cap
                    .frame(width: Self.cap, height: Self.cap)
                // The pointer: a dark line on the cap, turning with the value.
                Capsule()
                    .fill(Artwork.midnight.opacity(0.85))
                    .frame(width: 2.5, height: 9)
                    .offset(y: -11)
                    .rotationEffect(.degrees(-Self.sweep / 2 + Self.sweep * position))
            }
            .frame(width: Self.dial, height: Self.dial)
            .contentShape(Circle())
            .gesture(drag)
            .onTapGesture(count: 2) { KnobEdit.reset(edited, in: set, model: model) }
            // However a drag stops (cancelled, the knob stepping back, the view going away),
            // the edit it began ends, in the set it began in.
            .onChange(of: dragging) { _, isDragging in
                if !isDragging { finishEdit() }
            }
            .onDisappear(perform: finishEdit)
            Text(valueText)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(amount == nil ? Artwork.silver : editing.colour)
                .lineLimit(1)
        }
        .frame(width: Self.width)
        .opacity(editing.stepsBack(parameter) ? 0.3 : 1)
        .allowsHitTesting(!editing.stepsBack(parameter))
        .accessibilityElement()
        .accessibilityLabel(amount?.name ?? parameter.name)
        .accessibilityValue(valueText)
    }

    /// Below the knob: its value, or the amount being set.
    private var valueText: String {
        if let amount { return LFOs.label(amount: model.value(of: amount, in: set)) }
        return model.label(of: parameter, in: set)
    }

    /// What the LFOs sweep and where a softer hit takes the knob: an arc each,
    /// inside the value arc, each source on a ring of its own.
    @ViewBuilder
    private func modulationArcs(position: Double) -> some View {
        ForEach(0..<LFOs.count, id: \.self) { lfo in
            if let moved = LFOs.amount(of: parameter, lfo: lfo), model.value(of: moved, in: set) != 0 {
                let range = LFOs.arc(position: position, amount: Double(model.value(of: moved, in: set)))
                modulationArc(range, colour: Artwork.lfo(lfo), ring: lfo, lit: editing == .amount(lfo: lfo))
            }
        }
        if let moved = Velocity.amount(of: parameter), model.value(of: moved, in: set) != 0 {
            let range = Velocity.arc(position: position, amount: Double(model.value(of: moved, in: set)))
            modulationArc(range, colour: Artwork.vel, ring: LFOs.count, lit: editing == .velocity)
        }
    }

    /// One source's arc on its ring: 0 just inside the value arc, then inwards.
    private func modulationArc(_ range: ClosedRange<Double>, colour: Color, ring: Int, lit: Bool) -> some View {
        arc(from: range.lowerBound, to: range.upperBound)
            .stroke(colour, style: StrokeStyle(lineWidth: lit ? 2 : 1.5, lineCap: .round))
            .padding(4.5 + 2.25 * CGFloat(ring))
    }

    @ViewBuilder
    private var cap: some View {
        if let image = Artwork.knob {
            Image(nsImage: image).resizable().interpolation(.high)
        } else {
            Circle().fill(Artwork.silver.opacity(0.75)).padding(Self.cap * 0.1)
        }
    }

    /// Part of the 270-degree ring, `from` and `to` being knob positions (0...1).
    private func arc(from: Double, to: Double) -> some Shape {
        // trim() runs clockwise from 3 o'clock; the ring starts at 7:30.
        Circle()
            .trim(from: from * Self.sweep / 360, to: max(from, to) * Self.sweep / 360)
            .rotation(.degrees(135))
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($dragging) { _, isDragging, _ in isDragging = true }
            .onChanged { value in
                if edit == nil {
                    edit = KnobEdit.begin(edited, in: set, isAmount: amount != nil, model: model)
                }
                edit?.move(to: value.translation.height, fine: NSEvent.modifierFlags.contains(.shift), model: model)
            }
            .onEnded { _ in finishEdit() }
    }

    private func finishEdit() {
        edit?.end(model: model)
        edit = nil
    }
}
