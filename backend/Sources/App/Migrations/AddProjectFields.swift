import Fluent

struct AddProjectFields: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("todos")
            .field("status", .string, .required, .custom("DEFAULT 'todo'"))
            .update()
        try await database.schema("todos")
            .field("priority", .string, .required, .custom("DEFAULT 'none'"))
            .update()
        try await database.schema("todos")
            .field("due_date", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("todos")
            .deleteField("due_date")
            .update()
        try await database.schema("todos")
            .deleteField("priority")
            .update()
        try await database.schema("todos")
            .deleteField("status")
            .update()
    }
}
