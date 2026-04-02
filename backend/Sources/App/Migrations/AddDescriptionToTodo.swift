import Fluent

struct AddDescriptionToTodo: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("todos")
            .field("description", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("todos")
            .deleteField("description")
            .update()
    }
}
