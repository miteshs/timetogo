import SwiftUI

/// Soft, accent-tinted gradient that the translucent glass UI floats on.
/// Shared by every screen so the look stays consistent.
struct GlassBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.28),
                Color(.systemBackground),
                Color.accentColor.opacity(0.10)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

#Preview {
    GlassBackground()
}
