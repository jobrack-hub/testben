import Fluent

struct AddProjectFields: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("todos")
            .field("status",   .string, .required, .custom("DEFAULT 'todo'"))
            .field("priority", .string, .required, .custom("DEFAULT 'none'"))
            .field("due_date", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("todos")
            .deleteField("status")
            .deleteField("priority")
            .deleteField("due_date")
            .update()
    }
}
