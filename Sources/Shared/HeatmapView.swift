import SwiftUI

/// Which days a heatmap shows: columns are weeks (Monday first), rows are weekdays.
public struct HeatmapGrid {
    public let start: Date      // Monday of the first column
    public let columns: Int
    public let firstDay: Date   // first day drawn
    public let lastDay: Date    // last day drawn

    public static func year(_ year: Int) -> HeatmapGrid {
        let cal = DayKey.calendar
        let jan1 = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        let dec31 = cal.date(from: DateComponents(year: year, month: 12, day: 31)) ?? Date()
        let start = DayKey.monday(of: jan1)
        let days = cal.dateComponents([.day], from: start, to: dec31).day ?? 364
        return HeatmapGrid(start: start, columns: days / 7 + 1, firstDay: jan1, lastDay: dec31)
    }

    public static func recent(weeks: Int, now: Date = Date()) -> HeatmapGrid {
        let cal = DayKey.calendar
        let today = cal.startOfDay(for: now)
        let start = cal.date(byAdding: .day, value: -(weeks - 1) * 7, to: DayKey.monday(of: today)) ?? today
        return HeatmapGrid(start: start, columns: weeks, firstDay: start, lastDay: today)
    }

    public func date(col: Int, row: Int) -> Date {
        DayKey.calendar.date(byAdding: .day, value: col * 7 + row, to: start) ?? start
    }

    public func contains(_ d: Date) -> Bool { d >= firstDay && d <= lastDay }
}

public struct HeatmapView: View {
    let grid: HeatmapGrid
    let color: Color
    let showLabels: Bool
    let maxLevel: Int
    let level: (String) -> Int
    let onTap: ((Date) -> Void)?

    /// Generic heatmap: `level` maps a day key to 0 (empty) ... `maxLevel`.
    public init(grid: HeatmapGrid, color: Color, showLabels: Bool, maxLevel: Int = 4,
                level: @escaping (String) -> Int, onTap: ((Date) -> Void)? = nil) {
        self.grid = grid
        self.color = color
        self.showLabels = showLabels
        self.maxLevel = max(1, maxLevel)
        self.level = level
        self.onTap = onTap
    }

    /// Heatmap of minutes logged for a habit.
    public init(habit: Habit, grid: HeatmapGrid, showLabels: Bool, onTap: ((Date) -> Void)? = nil) {
        let log = habit.log
        self.init(grid: grid, color: habit.color, showLabels: showLabels, maxLevel: 4,
                  level: { DayKey.level(log[$0]) }, onTap: onTap)
    }

    private var labelUnits: CGFloat { showLabels ? 3.2 : 0 }
    private var topUnits: CGFloat { showLabels ? 2.0 : 0 }
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    public var body: some View {
        let ratio = (CGFloat(grid.columns) + labelUnits) / (7 + topUnits)
        GeometryReader { geo in
            let canvas = Canvas { context, size in
                draw(context, size: size)
            }
            if let onTap {
                canvas
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        if let day = day(at: location, size: geo.size) { onTap(day) }
                    }
            } else {
                canvas
            }
        }
        .aspectRatio(ratio, contentMode: .fit)
    }

    private func unit(_ size: CGSize) -> CGFloat {
        size.width / (CGFloat(grid.columns) + labelUnits)
    }

    private func day(at p: CGPoint, size: CGSize) -> Date? {
        let u = unit(size)
        let col = Int(floor((p.x - labelUnits * u) / u))
        let row = Int(floor((p.y - topUnits * u) / u))
        guard col >= 0, col < grid.columns, row >= 0, row < 7 else { return nil }
        let d = grid.date(col: col, row: row)
        let today = DayKey.calendar.startOfDay(for: Date())
        guard grid.contains(d), d <= today else { return nil }
        return d
    }

    private func draw(_ ctx: GraphicsContext, size: CGSize) {
        let cal = DayKey.calendar
        let u = unit(size)
        let gap = max(1, u * 0.2)
        let cell = u - gap
        let x0 = labelUnits * u
        let y0 = topUnits * u
        let today = cal.startOfDay(for: Date())
        let todayKey = DayKey.key(today)
        let empty = Color.gray.opacity(0.22)

        for col in 0..<grid.columns {
            for row in 0..<7 {
                let d = grid.date(col: col, row: row)
                guard grid.contains(d) else { continue }
                let rect = CGRect(x: x0 + CGFloat(col) * u, y: y0 + CGFloat(row) * u, width: cell, height: cell)
                let path = Path(roundedRect: rect, cornerRadius: cell * 0.22)
                let key = DayKey.key(d)
                let lv = min(maxLevel, level(key))
                ctx.fill(path, with: .color(d > today ? Color.gray.opacity(0.1) : empty))
                if lv > 0 {
                    let opacity = 0.3 + 0.7 * Double(lv) / Double(maxLevel)
                    ctx.fill(path, with: .color(color.opacity(opacity)))
                }
                if key == todayKey {
                    ctx.stroke(path, with: .color(.primary), lineWidth: max(1, u * 0.14))
                }
            }

            // Month label above the column that contains the 1st of a month
            if showLabels {
                for row in 0..<7 {
                    let d = grid.date(col: col, row: row)
                    if grid.contains(d), cal.component(.day, from: d) == 1 {
                        let m = cal.component(.month, from: d) - 1
                        ctx.draw(
                            Text(Self.months[m]).font(.system(size: min(11, u * 1.5))).foregroundColor(.secondary),
                            at: CGPoint(x: x0 + CGFloat(col) * u, y: y0 - u),
                            anchor: .leading
                        )
                    }
                }
            }
        }

        if showLabels {
            for (i, name) in ["Mon", "Wed", "Fri"].enumerated() {
                ctx.draw(
                    Text(name).font(.system(size: min(10, u * 1.4))).foregroundColor(.secondary),
                    at: CGPoint(x: 0, y: y0 + CGFloat(i * 2) * u + cell / 2),
                    anchor: .leading
                )
            }
        }
    }
}
