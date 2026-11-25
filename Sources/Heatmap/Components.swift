import SwiftUI
import UIKit
import Shared

/// The dark rounded panel the screens are built from.
struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}

/// Round check button with a label.
struct CheckRow: View {
    let text: String
    let checked: Bool
    var detail: String? = nil
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(checked ? Palette.flame : Color.secondary)
                Text(text)
                    .strikethrough(checked)
                    .foregroundStyle(checked ? Color.secondary : Color.primary)
                Spacer(minLength: 0)
                if let detail {
                    Text(detail).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: checked)
    }
}

/// Converts stored minutes-after-midnight into a Date for DatePicker.
func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
    Binding(
        get: {
            Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: Date()) ?? Date()
        },
        set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
    )
}

func formatTime(_ minutes: Int) -> String {
    String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
}

// MARK: - Liquid Glass (iOS 26+), with the previous look as fallback

extension View {
    /// Glass behind a custom control, tinted and reacting to touch. Before iOS 26: a solid fill.
    @ViewBuilder
    func glassBackground<S: Shape>(_ tint: Color?, in shape: S, fallback: Color) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            self.background(fallback, in: shape)
        }
    }

    /// Glass button style on iOS 26, bordered before.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26, *) {
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass) }
        } else {
            if prominent { self.buttonStyle(.borderedProminent) } else { self.buttonStyle(.bordered) }
        }
    }

    /// Tab bar shrinks while scrolling down on iOS 26.
    @ViewBuilder
    func minimizingTabBar() -> some View {
        if #available(iOS 26, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}
