import Foundation

extension DateFormatter {
    static var shortTime: DateFormatter {
        let df = DateFormatter()
        df.timeStyle = .short
        return df
    }
}
