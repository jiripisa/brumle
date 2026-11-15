import AppKit
import SwiftUI
import BrumleCore

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text(BrumleCore.greeting(appName: "Brumle"))
                .font(.title)
            Text("A playable synthesized jaw harp: twang, moving overtones, breath and rhythm, as an Audio Unit and a standalone app.")
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(minWidth: 640, minHeight: 400)
    }
}
