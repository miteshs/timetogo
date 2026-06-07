import SwiftUI

/// A lightweight emoji confetti burst — no assets, no dependencies.
/// Bump `trigger` (e.g. an Int counter) to fire a new burst.
struct ConfettiView: View {
    var trigger: Int

    private let emojis = ["🎉", "🎊", "⭐️", "✨", "🌟", "💫", "🥳", "🌈"]

    private struct Piece: Identifiable {
        let id = UUID()
        let emoji: String
        let x: CGFloat          // 0...1 of width
        let rotation: Double
        let scale: CGFloat
        let delay: Double
        let duration: Double
    }

    @State private var pieces: [Piece] = []
    @State private var fallen = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { piece in
                    Text(piece.emoji)
                        .font(.system(size: 30))
                        .scaleEffect(piece.scale)
                        .rotationEffect(.degrees(fallen ? piece.rotation : 0))
                        .position(
                            x: piece.x * geo.size.width,
                            y: fallen ? geo.size.height + 60 : -60
                        )
                        .opacity(fallen ? 0 : 1)
                        .animation(.easeIn(duration: piece.duration).delay(piece.delay), value: fallen)
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { burst() }
    }

    private func burst() {
        fallen = false
        pieces = (0..<26).map { _ in
            Piece(
                emoji: emojis.randomElement()!,
                x: .random(in: 0.05...0.95),
                rotation: .random(in: -360...360),
                scale: .random(in: 0.7...1.4),
                delay: .random(in: 0...0.25),
                duration: .random(in: 1.1...1.9)
            )
        }
        DispatchQueue.main.async { fallen = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { pieces = [] }
    }
}
