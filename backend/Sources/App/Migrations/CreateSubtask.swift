import Fluent

struct CreateSubtask: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("subtasks")
            .id()
            .field("todo_id",     .uuid,     .required)
            .field("title",       .string,   .required)
            .field("is_complete", .bool,     .required, .custom("DEFAULT 0"))
            .field("created_at",  .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("subtasks").delete()
    }
}
