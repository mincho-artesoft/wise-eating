import SwiftUI

struct InfiniteWheelPicker: View {
    let values: [Int]
    @Binding var selection: Int
    var labelForValue: (Int) -> String = { "\($0)" }
    
    private let repeatCount = 3
    
    private var data: [Int] {
        Array(repeating: values, count: repeatCount).flatMap { $0 }
    }
    
    @State private var internalIndex: Int = 0
    
    var body: some View {
        Picker("", selection: $internalIndex) {
            ForEach(data.indices, id: \.self) { index in
                Text(labelForValue(data[index]))
                    .tag(index)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .onAppear {
            // Позиционираме се в средния блок за текущия selection
            if let baseIndex = values.firstIndex(of: selection) {
                let middleBlock = repeatCount / 2
                internalIndex = middleBlock * values.count + baseIndex
            }
        }
        .onChange(of: internalIndex) { newIndex in
            // Обновяваме външния selection
            let value = data[newIndex]
            if value != selection {
                selection = value
            }
            
            // Държим индекса около средата, за да не стигаме до края
            let middleBlock = repeatCount / 2
            let middleIndex = middleBlock * values.count + (newIndex % values.count)
            
            if abs(middleIndex - newIndex) > values.count {
                internalIndex = middleIndex
            }
        }
    }
}
