import SwiftUI

/// Node visual identity: deep blue base, cyan for what matters, cold white for text.
enum Node {
    static let navy = Color(red: 0 / 255, green: 44 / 255, blue: 68 / 255)          // #002C44
    static let cyan = Color(red: 4 / 255, green: 203 / 255, blue: 201 / 255)        // #04CBC9
    static let ice = Color(red: 239 / 255, green: 255 / 255, blue: 255 / 255)       // #EFFFFF
    static let deep = Color(red: 0 / 255, green: 27 / 255, blue: 43 / 255)
    static let abyss = Color(red: 0 / 255, green: 14 / 255, blue: 23 / 255)
    static let ink = ice.opacity(0.92)
    static let muted = ice.opacity(0.52)
    static let faint = ice.opacity(0.28)
    static let surface = ice.opacity(0.045)
    static let raised = ice.opacity(0.075)
    static let hairline = ice.opacity(0.09)
    static let background = LinearGradient(colors: [navy, deep, abyss], startPoint: .top, endPoint: .bottom)
}

/// The brand's support graphic: right-angled data paths that branch and end in nodes.
struct CircuitPattern: View {
    var color: Color = Node.cyan
    var seed: UInt64 = 7
    var body: some View {
        Canvas { context, size in
            var random = SplitMix(seed: seed)
            let step: CGFloat = 22
            let columns = Int(size.width / step) + 1, rows = Int(size.height / step) + 1
            for _ in 0..<9 {
                var point = CGPoint(x: CGFloat(random.next(columns)) * step, y: CGFloat(random.next(rows)) * step)
                var path = Path(); path.move(to: point)
                context.fill(Path(ellipseIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)), with: .color(color))
                var horizontal = random.next(2) == 0
                for _ in 0..<(2 + random.next(3)) {
                    let length = CGFloat(1 + random.next(4)) * step * (random.next(2) == 0 ? 1 : -1)
                    point = horizontal ? CGPoint(x: point.x + length, y: point.y) : CGPoint(x: point.x, y: point.y + length)
                    path.addLine(to: point)
                    horizontal.toggle()
                }
                context.stroke(path, with: .color(color.opacity(0.75)), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                let end = CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)
                context.fill(Path(ellipseIn: end), with: .color(Node.abyss))
                context.stroke(Path(ellipseIn: end), with: .color(color), lineWidth: 1.2)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Section label in the brand's editorial style: a node, a rule, then the title.
struct NodeRule: View {
    let title: String
    var busy = false
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(Node.cyan).frame(width: 5, height: 5)
            Text(title).font(.system(size: 9.5, weight: .semibold)).tracking(1.6).foregroundStyle(Node.muted)
            Rectangle().fill(Node.hairline).frame(height: 0.7)
            if busy { ProgressView().controlSize(.mini) }
        }.padding(.horizontal, 2)
    }
}

/// Deterministic generator so the pattern looks the same on every render.
struct SplitMix {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next(_ bound: Int) -> Int {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Int((z ^ (z >> 31)) % UInt64(max(1, bound)))
    }
}

/// Main action: solid cyan with dark text.
struct NodePrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Node.abyss)
            .padding(.horizontal, 14).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Node.cyan.opacity(configuration.isPressed ? 0.8 : 1)))
            .opacity(enabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Secondary action: quiet surface with a hairline.
struct NodeSecondaryButton: ButtonStyle {
    var tint: Color = Node.ink
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11.5, weight: .medium)).foregroundStyle(tint)
            .padding(.horizontal, 12).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Node.ice.opacity(configuration.isPressed ? 0.12 : 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Node.hairline, lineWidth: 0.7))
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

extension View {
    /// Text field on a quiet surface; apply to a `.plain` TextField.
    func nodeField() -> some View {
        textFieldStyle(.plain).padding(.horizontal, 10).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Node.ice.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Node.hairline, lineWidth: 0.7))
    }
}

/// Segmented choice in brand colors.
struct NodeSegmented<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.label).font(.system(size: 11, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Node.abyss : Node.muted)
                        .frame(maxWidth: .infinity).frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Node.cyan : .clear))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            }
        }.padding(3)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Node.surface))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Node.hairline, lineWidth: 0.7))
            .animation(.easeOut(duration: 0.15), value: selection)
    }
}
