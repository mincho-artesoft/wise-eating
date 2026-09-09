import Foundation

protocol CancellableTask {
    func cancel()
}

extension Task: CancellableTask {}
