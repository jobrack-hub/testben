import Fluent
import Vapor

struct SubtaskController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        // Routes: /api/todos/:todoID/subtasks[/:subtaskID]
        let subs = routes.grouped("todos", ":todoID", "subtasks")
        subs.get(use: index)
        subs.post(use: create)
        subs.group(":subtaskID") { sub in
            sub.put(use: update)
            sub.delete(use: delete)
        }
    }

    struct SubtaskInput: Content {
        var title: String
        var isComplete: Bool?
    }

    private func validatedTitle(_ raw: String) throws -> String {
        let title = raw.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else {
            throw Abort(.unprocessableEntity, reason: "Title cannot be empty")
        }
        guard title.count <= 255 else {
            throw Abort(.unprocessableEntity, reason: "Title must be 255 characters or fewer")
        }
        return title
    }

    @Sendable
    func index(req: Request) async throws -> [Subtask] {
        guard let todoID = req.parameters.get("todoID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid todo ID")
        }
        return try await Subtask.query(on: req.db)
            .filter(\.$todoId == todoID)
            .sort(\.$createdAt, .ascending)
            .all()
    }

    @Sendable
    func create(req: Request) async throws -> Response {
        guard let todoID = req.parameters.get("todoID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid todo ID")
        }
        guard try await Todo.find(todoID, on: req.db) != nil else {
            throw Abort(.notFound, reason: "Todo not found")
        }
        let input = try req.content.decode(SubtaskInput.self)
        let title = try validatedTitle(input.title)
        let subtask = Subtask(todoId: todoID, title: title)
        try await subtask.save(on: req.db)
        return try await subtask.encodeResponse(status: .created, for: req)
    }

    @Sendable
    func update(req: Request) async throws -> Subtask {
        guard let subtask = try await Subtask.find(req.parameters.get("subtaskID"), on: req.db) else {
            throw Abort(.notFound)
        }
        let input = try req.content.decode(SubtaskInput.self)
        subtask.title = try validatedTitle(input.title)
        if let ic = input.isComplete {
            subtask.isComplete = ic
        }
        try await subtask.save(on: req.db)
        return subtask
    }

    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        guard let subtask = try await Subtask.find(req.parameters.get("subtaskID"), on: req.db) else {
            throw Abort(.notFound)
        }
        try await subtask.delete(on: req.db)
        return .noContent
    }
}
