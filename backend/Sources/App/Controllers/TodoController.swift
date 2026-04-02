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
        var timeSpent: Int?
        var status: String?
        var priority: String?
        var dueDate: String?
    }

    private static let validStatuses   = Set(["todo", "in_progress", "done"])
    private static let validPriorities = Set(["none", "low", "medium", "high", "urgent"])

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

    private func applyStatus(_ raw: String?, to todo: Todo) throws {
        guard let raw else { return }
        guard Self.validStatuses.contains(raw) else {
            throw Abort(.unprocessableEntity, reason: "Invalid status: \(raw)")
        }
        todo.status = raw
        todo.isComplete = (raw == "done")
    }

    private func applyPriority(_ raw: String?, to todo: Todo) throws {
        guard let raw else { return }
        guard Self.validPriorities.contains(raw) else {
            throw Abort(.unprocessableEntity, reason: "Invalid priority: \(raw)")
        }
        todo.priority = raw
    }

    @Sendable
    func index(req: Request) async throws -> [Todo] {
        try await Todo.query(on: req.db).sort(\.$createdAt, .ascending).all()
    }

    @Sendable
    func create(req: Request) async throws -> Response {
        let input = try req.content.decode(TodoInput.self)
        let title    = try validatedTitle(from: input)
        let status   = input.status   ?? "todo"
        let priority = input.priority ?? "none"
        guard Self.validStatuses.contains(status) else {
            throw Abort(.unprocessableEntity, reason: "Invalid status: \(status)")
        }
        guard Self.validPriorities.contains(priority) else {
            throw Abort(.unprocessableEntity, reason: "Invalid priority: \(priority)")
        }
        let todo = Todo(
            title: title,
            isComplete: status == "done",
            status: status,
            priority: priority,
            dueDate: input.dueDate?.isEmpty == false ? input.dueDate : nil
        )
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
        todo.title     = try validatedTitle(from: input)
        todo.timeSpent = max(0, input.timeSpent ?? todo.timeSpent)
        try applyStatus(input.status, to: todo)
        try applyPriority(input.priority, to: todo)
        if let dd = input.dueDate {
            todo.dueDate = dd.isEmpty ? nil : dd
        }
        // legacy isComplete passthrough (toggle compatibility)
        if input.status == nil, let ic = input.isComplete {
            todo.isComplete = ic
            todo.status = ic ? "done" : "todo"
        }
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
