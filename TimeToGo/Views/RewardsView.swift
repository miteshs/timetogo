import SwiftUI
import SwiftData

/// The collectible "creatures" earned one per logged go, in order.
enum StickerBook {
    static let roster: [String] = [
        "🐣", "🐢", "🐙", "🦊", "🐬", "🦕", "🚀", "🌈", "🦄", "⭐️",
        "🐳", "🦖", "🦋", "🐝", "🌟", "🦉", "🐲", "🍄", "🪐", "🎈",
        "🦓", "🐧", "🦩", "🐌", "🐠", "🦜", "🌻", "🐞", "🦔", "🐨"
    ]

    /// One sticker earned per logged go, capped at the roster size.
    static func unlockedCount(lifetimeGos: Int) -> Int {
        max(0, min(lifetimeGos, roster.count))
    }

    /// The sticker a given go (0-based) earns, if any are left to collect.
    static func sticker(forGoIndex index: Int) -> String? {
        index >= 0 && index < roster.count ? roster[index] : nil
    }
}

struct RewardsView: View {
    @Query(sort: \GoEvent.timestamp, order: .reverse) private var events: [GoEvent]

    private var lifetimeGos: Int { events.filter { $0.kind == .went }.count }
    private var unlocked: Int { StickerBook.unlockedCount(lifetimeGos: lifetimeGos) }

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 14)]

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()
                if unlocked == 0 {
                    ContentUnavailableView(
                        "No stickers yet",
                        systemImage: "star",
                        description: Text("Tap “I went now” to earn your first sticker!")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            Text("\(unlocked) of \(StickerBook.roster.count) collected")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(StickerBook.roster.indices, id: \.self) { i in
                                    cell(index: i)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Stickers")
        }
    }

    private func cell(index: Int) -> some View {
        let earned = index < unlocked
        return Text(earned ? StickerBook.roster[index] : "❔")
            .font(.system(size: 38))
            .frame(width: 72, height: 72)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.15)))
            .opacity(earned ? 1 : 0.4)
            .grayscale(earned ? 0 : 1)
            .accessibilityLabel(earned ? "Sticker \(index + 1), collected" : "Sticker \(index + 1), locked")
    }
}

#Preview {
    RewardsView()
        .modelContainer(for: GoEvent.self, inMemory: true)
}
