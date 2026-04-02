import Fluent

struct AddTimeSpentToTodo: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("todos")
            .field("time_spent", .int, .required, .custom("DEFAULT 0"))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("todos")
            .deleteField("time_spent")
            .update()
    }
}
