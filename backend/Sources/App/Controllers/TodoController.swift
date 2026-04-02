import Fluent
import Vapor

struct TodoController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let todos = routes.grouped("todos")
        todos.get(use: index)
        todos.post(use: create)
        todos.group(":todoID") { todo in
            todo.get(use: show)
            todo.put(use: update)
            todo.delete(use: delete)
        }
    }

    struct TodoInput: Content {
        var title: String
        var isComplete: Bool?
    }

    private func validatedTitle(from input: TodoInput) throws -> String {
        let title = input.title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else {
            throw Abort(.unprocessableEntity, reason: "Title cannot be empty")
        }
        guard title.count <= 255 else {
            throw Abort(.unprocessableEntity, reason: "Title must be 255 characters or fewer")
        }
        return title
    }

    @Sendable
    func index(req: Request) async throws -> [Todo] {
        try await Todo.query(on: req.db).sort(\.$createdAt, .ascending).all()
    }

    @Sendable
    func create(req: Request) async throws -> Response {
        let input = try req.content.decode(TodoInput.self)
        let title = try validatedTitle(from: input)
        let todo = Todo(title: title)
        try await todo.save(on: req.db)
        return try await todo.encodeResponse(status: .created, for: req)
    }

    @Sendable
    func show(req: Request) async throws -> Todo {
        guard let todo = try await Todo.find(req.parameters.get("todoID"), on: req.db) else {
            throw Abort(.notFound)
        }
        return todo
    }

    @Sendable
    func update(req: Request) async throws -> Todo {
        guard let todo = try await Todo.find(req.parameters.get("todoID"), on: req.db) else {
            throw Abort(.notFound)
        }
        let input = try req.content.decode(TodoInput.self)
        let title = try validatedTitle(from: input)
        todo.title = title
        todo.isComplete = input.isComplete ?? todo.isComplete
        try await todo.save(on: req.db)
        return todo
    }

    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        guard let todo = try await Todo.find(req.parameters.get("todoID"), on: req.db) else {
            throw Abort(.notFound)
        }
        try await todo.delete(on: req.db)
        return .noContent
    }
}
