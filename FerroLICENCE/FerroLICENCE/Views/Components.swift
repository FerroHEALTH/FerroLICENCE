import SwiftUI

/// A state in one sentence, as a native form row: a symbol in the state's
/// colour, the sentence, and at most one action on the trailing side. No
/// tinted background: the symbol carries the state, the system draws the row.
struct StatusRow<Action: View>: View {
    enum Kind {
        case warning, failure, success, info

        var symbol: String {
            switch self {
            case .warning: "exclamationmark.triangle.fill"
            case .failure: "xmark.circle.fill"
            case .success: "checkmark.circle.fill"
            case .info: "info.circle"
            }
        }

        var color: Color {
            switch self {
            case .warning: .orange
            case .failure: .red
            case .success: .green
            case .info: .secondary
            }
        }
    }

    let kind: Kind
    let text: LocalizedStringResource
    var symbol: String?
    @ViewBuilder var action: Action

    var body: some View {
        LabeledContent {
            // The button keeps its whole title; the sentence wraps instead.
            action.fixedSize()
        } label: {
            Label {
                Text(text).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: symbol ?? kind.symbol)
                    .foregroundStyle(kind.color)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension StatusRow where Action == EmptyView {
    init(_ kind: Kind, _ text: LocalizedStringResource, symbol: String? = nil) {
        self.init(kind: kind, text: text, symbol: symbol) { EmptyView() }
    }
}

/// The sheet's step track: every step named, the current one in the accent colour.
struct StepTrack: View {
    let steps: [LocalizedStringResource]
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(steps.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 6) {
                    Capsule()
                        .fill(i <= current ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                        .frame(height: 4)
                    Text(steps[i])
                        .font(.caption)
                        .fontWeight(i == current ? .semibold : .regular)
                        .foregroundStyle(i == current ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(current + 1) of \(steps.count): \(steps[current])"))
    }
}

/// A sheet's title line, with an optional symbol.
struct SheetTitle: View {
    let title: LocalizedStringResource
    var symbol: String?
    var color: Color = .accentColor
    var subtitle: LocalizedStringResource?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(title).font(.title3).bold()
            } icon: {
                if let symbol { Image(systemName: symbol).foregroundStyle(color) }
            }
            .labelStyle(.titleAndIcon)
            if let subtitle {
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// `#41 ↗`, opening the pull request on GitHub.
struct PullRequestLink: View {
    let number: Int
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 2) {
                Text(verbatim: "#\(number)")
                Image(systemName: "arrow.up.forward.app").imageScale(.small)
            }
        }
        .help(Text("Open pull request #\(number) on GitHub"))
        .accessibilityLabel(Text("Pull request \(number)"))
    }
}

/// The YubiKey 5C, drawn to scale, its light pulsing until it is touched.
/// With Reduce Motion on, the light stays lit.
struct YubiKeyDrawing: View {
    var blinking = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            // The USB-C plug.
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [Color(white: 0.86), Color(white: 0.62)], startPoint: .top, endPoint: .bottom))
                .frame(width: 30, height: 26)
                .overlay(alignment: .center) { RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.35)).frame(width: 20, height: 6) }
            // The body, with the gold touch contact and its light.
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 96, height: 52)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 0.95, green: 0.8, blue: 0.45), Color(red: 0.72, green: 0.55, blue: 0.22)],
                            center: .center, startRadius: 2, endRadius: 18)
                    )
                    .frame(width: 34, height: 34)
                    .offset(x: 14)
                Light(blinking: blinking && !reduceMotion)
                    .offset(x: 14)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .accessibilityElement()
        .accessibilityLabel(Text("YubiKey 5C"))
        .accessibilityValue(blinking ? Text("light blinking: touch it now") : Text(verbatim: ""))
    }

    struct Light: View {
        let blinking: Bool

        var body: some View {
            if blinking {
                Circle().frame(width: 12, height: 12)
                    .phaseAnimator([false, true]) { light, on in
                        light
                            .foregroundStyle(on ? Color(red: 0.55, green: 1, blue: 0.62) : Color(red: 0.24, green: 0.36, blue: 0.27))
                            .shadow(color: on ? .green : .clear, radius: on ? 6 : 0)
                    } animation: { _ in
                        .easeInOut(duration: 0.55)
                    }
            } else {
                Circle().fill(Color(red: 0.55, green: 1, blue: 0.62)).frame(width: 12, height: 12)
            }
        }
    }
}

/// A row of the steps list: done, running or still to come.
struct StepRow<Trailing: View>: View {
    enum State { case done, running, todo }

    let number: Int
    let text: LocalizedStringResource
    let state: State
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Group {
                switch state {
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).imageScale(.large)
                case .running: ProgressView().controlSize(.small)
                case .todo:
                    Text(number, format: .number)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .overlay(alignment: .center) { Circle().strokeBorder(.secondary.opacity(0.6), lineWidth: 1.5) }
                }
            }
            .frame(width: 22)
            Text(text)
                .fontWeight(state == .running ? .semibold : .regular)
                .foregroundStyle(state == .todo ? .secondary : .primary)
            trailing
            Spacer(minLength: 0)
        }
        .frame(minHeight: 24)
        .accessibilityElement(children: .combine)
    }
}

extension StepRow where Trailing == EmptyView {
    init(number: Int, text: LocalizedStringResource, state: State) {
        self.init(number: number, text: text, state: state) { EmptyView() }
    }
}
