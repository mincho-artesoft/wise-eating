import Foundation

extension NSRegularExpression {
    func matches(in string: String) -> [NSTextCheckingResult] {
        let range = NSRange(location: 0, length: string.utf16.count)
        return matches(in: string, options: [], range: range)
    }
}

extension NSTextCheckingResult {
    func groupValue(named name: String, in source: String) -> String? {
        let nsRange = self.range(withName: name)
        if nsRange.location != NSNotFound, let range = Range(nsRange, in: source) {
            return String(source[range])
        }
        return nil
    }
}
