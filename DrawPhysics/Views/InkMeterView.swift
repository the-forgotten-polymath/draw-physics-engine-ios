import SwiftUI

struct InkMeterView: View {
    let remaining: Double
    let total: Double
    
    private var fraction: Double {
        guard total > 0 else { return 0 }
        return max(0, min(1, remaining / total))
    }
    
    private var color: Color {
        if fraction > 0.5 { return .green }
        if fraction > 0.2 { return .yellow }
        return .red
    }
    
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.3))
                
                RoundedRectangle(cornerRadius: 8)
                    .fill(color)
                    .frame(width: proxy.size.width * CGFloat(fraction))
            }
        }
        .frame(height: 16)
        .animation(.linear, value: fraction)
    }
}

#Preview {
    VStack(spacing: 20) {
        InkMeterView(remaining: 800, total: 1000)
        InkMeterView(remaining: 300, total: 1000)
        InkMeterView(remaining: 100, total: 1000)
    }
    .padding()
}
