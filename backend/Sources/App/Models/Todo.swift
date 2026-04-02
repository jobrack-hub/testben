import Fluent
import Vapor

final class Todo: Model, Content, @unchecked Sendable {
    static let schema = "todos"

    @ID var id: UUID?
    @Field(key: "title")       var title: String
    @Field(key: "is_complete") var isComplete: Bool
    @Field(key: "time_spent")  var timeSpent: Int
    @Field(key: "status")      var status: String
    @Field(key: "priority")    var priority: String
    @OptionalField(key: "due_date") var dueDate: String?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        title: String,
        isComplete: Bool = false,
        timeSpent: Int = 0,
        status: String = "todo",
        priority: String = "none",
        dueDate: String? = nil
    ) {
        self.id = id
        self.title = title
        self.isComplete = isComplete
        self.timeSpent = timeSpent
        self.status = status
        self.priority = priority
        self.dueDate = dueDate
    }
}
