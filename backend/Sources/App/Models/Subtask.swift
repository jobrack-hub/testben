import Fluent
import Vapor

final class Subtask: Model, Content, @unchecked Sendable {
    static let schema = "subtasks"

    @ID var id: UUID?
    @Field(key: "todo_id")      var todoId: UUID
    @Field(key: "title")        var title: String
    @Field(key: "is_complete")  var isComplete: Bool
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(id: UUID? = nil, todoId: UUID, title: String, isComplete: Bool = false) {
        self.id = id
        self.todoId = todoId
        self.title = title
        self.isComplete = isComplete
    }
}
