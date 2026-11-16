import AppKit
import SwiftUI
import BrumleCore

/// The instrument's panel, the same in the app's window and in the plug-in's:
/// the header (`HeaderView`), an ornament band, the five groups of controls
/// (Reed, Stroke, Mouth, Breath, Master) side by side on glass, then `footer`
/// (the pads or the keyboard). The knobs show the set the model shows: the
/// keyboard's, or the selected pad's. With LFO 1, LFO 2 or VEL on in the
/// header, they set that source's amounts (`KnobView`).
///
/// The panel asks the model to catch up every 40 ms: a host moves parameters
/// without telling anyone, and pads are hit from MIDI.
/// The caller gives the panel its frame and `instrumentBackground()`.
public struct InstrumentPanel<Footer: View>: View {

    /// The panel's width; its groups are laid out for it. Its height follows
    /// from what is in it.
    public static var width: CGFloat { 1100 }

    private let model: any InstrumentModel
    private let footer: Footer

    /// What the knobs edit at the moment: their values, or a source's amounts.
    @State private var editing: KnobEditing

    /// `editing` is what the panel opens with, for a picture of that state; a
    /// window opens with the knobs as knobs.
    public init(model: any InstrumentModel,
                showing editing: KnobEditing = .value,
                @ViewBuilder footer: () -> Footer = { EmptyView() }) {
        self.model = model
        _editing = State(initialValue: editing)
        self.footer = footer()
    }

    public var body: some View {
        VStack(spacing: 10) {
            HeaderView(model: model, editing: $editing)
            OrnamentBand()
            // Spacing 0: glass closer than the container's spacing blends into one shape, and
            // the five groups are meant to stay apart.
            GlassEffectContainer(spacing: 0) {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(ParameterSection.all) { section in
                        SectionView(section: section, set: model.shownSet, model: model, editing: editing)
                    }
                }
                // Every group as tall as the tallest.
                .fixedSize(horizontal: false, vertical: true)
            }
            footer
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(width: Self.width)
        .task {
            while !Task.isCancelled {
                model.refresh()
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
    }
}

/// The engraved diamond band, repeated across the panel; nothing where the
/// artwork is missing.
private struct OrnamentBand: View {

    private static let height: CGFloat = 12

    /// The ornament's artwork at the band's height, ready to be tiled.
    @MainActor
    private static let image: NSImage? = {
        guard let ornament = Artwork.ornament, ornament.size.height > 0 else { return nil }
        let band = ornament.copy() as! NSImage
        band.size = NSSize(width: ornament.size.width * height / ornament.size.height, height: height)
        return band
    }()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .resizable(resizingMode: .tile)
                .frame(height: Self.height)
                .opacity(0.85)
                .accessibilityHidden(true)
        }
    }
}
