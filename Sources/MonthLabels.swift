import Foundation

/// Candidate week columns at each month boundary. Dates are Mondays in the grid,
/// including a partial opening week, and the year matters at December/January.
func heatmapMonthCandidates(firstMonday: Date, columns: Int, calendar: Calendar) -> [(column: Int, date: Date)] {
    var result: [(column: Int, date: Date)] = []
    var previous: DateComponents?
    for column in 0..<max(0, columns) {
        guard let date = calendar.date(byAdding: .day, value: column * 7, to: firstMonday) else { continue }
        let month = calendar.dateComponents([.year, .month], from: date)
        if month != previous { result.append((column, date)); previous = month }
    }
    return result
}

/// Choose non-overlapping labels, favoring the more recent month when a partial
/// opening month and the following month have too little space between them.
func heatmapVisibleMonthIndices(positions: [Double], widths: [Double], rightEdge: Double, gap: Double = 4) -> [Int] {
    guard positions.count == widths.count else { return [] }
    var chosen: [Int] = []
    var nextLeft = rightEdge + gap
    for index in positions.indices.reversed() {
        let left = positions[index], right = left + widths[index]
        guard widths[index] >= 0, right <= rightEdge, right + gap <= nextLeft else { continue }
        chosen.append(index)
        nextLeft = left
    }
    return chosen.reversed()
}
