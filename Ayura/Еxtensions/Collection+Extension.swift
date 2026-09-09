extension Collection {
    func chunks(ofCount count: Int) -> [SubSequence] {
        guard count > 0 else { return [self[self.startIndex..<self.endIndex]] }
        var result: [SubSequence] = []
        var i = startIndex
        while i < endIndex {
            let j = index(i, offsetBy: count, limitedBy: endIndex) ?? endIndex
            result.append(self[i..<j])
            i = j
        }
        return result
    }
}
