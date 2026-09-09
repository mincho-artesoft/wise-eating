import SwiftUI

public struct OnChangeDebouncedModifier<Value: Equatable>: ViewModifier {
    @State private var lastValue: Value
    @State private var pendingWorkItem: DispatchWorkItem?

    let newValue: Value
    let delay: TimeInterval
    let action: (Value) -> Void

    public init(of value: Value, debounce delay: TimeInterval, action: @escaping (Value) -> Void) {
        self._lastValue = State(initialValue: value)
        self.newValue = value
        self.delay = delay
        self.action = action
    }

    public func body(content: Content) -> some View {
        content
            .onChange(of: newValue) { _, new in
                pendingWorkItem?.cancel()
                let work = DispatchWorkItem { action(new) }
                pendingWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
                lastValue = new
            }
    }
}

