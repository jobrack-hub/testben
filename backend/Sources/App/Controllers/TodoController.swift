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

    @Sendable
    func index(req: Request) async throws -> [Todo] {
        try await Todo.query(on: req.db).sort(\.$createdAt, .ascending).all()
    }

    @Sendable
    func create(req: Request) async throws -> Response {
        let todo = try req.content.decode(Todo.self)
        todo.id = nil
        todo.isComplete = false
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
        let updated = try req.content.decode(Todo.self)
        todo.title = updated.title
        todo.isComplete = updated.isComplete
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
