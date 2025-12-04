import Foundation

actor GlobalTaskManager {
    static let shared = GlobalTaskManager()
    private var tasks: [CancellableTask] = []

    private init() {}

    /// Добавя нова задача към мениджъра.
    /// Задачата трябва да бъде от тип, който може да бъде прекратен.
    func addTask<Success, Failure>(_ task: Task<Success, Failure>) {
        tasks.append(task)
    }

    /// Прекратява всички активни задачи и изчиства списъка.
    func cancelAllTasks() {
        print("Опит за прекратяване на \(tasks.count) задачи.")
        tasks.forEach { task in
            task.cancel()
        }
        tasks.removeAll()
        print("Всички задачи са прекратени и списъкът е изчистен.")
    }
}


