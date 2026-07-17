import SwiftUI

struct UnreadBadgeView: View {
    let count: Int
    var accent: Color = .red

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(minWidth: 20, minHeight: 18)
                .background(Capsule().fill(accent))
        }
    }
}
