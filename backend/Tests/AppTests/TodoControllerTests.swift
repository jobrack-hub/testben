@testable import App
import XCTVapor
import FluentSQLiteDriver

final class TodoControllerTests: XCTestCase {

    var app: Application!

    override func setUp() async throws {
        app = try await Application.make(.testing)
        app.databases.use(.sqlite(.memory), as: .sqlite, isDefault: true)
        app.migrations.add(CreateTodo())
        try await app.autoMigrate()
        let api = app.grouped("api")
        try api.register(collection: TodoController())
    }

    override func tearDown() async throws {
        try await app.autoRevert()
        try await app.asyncShutdown()
    }

    // MARK: - List

    func testListEmpty() async throws {
        try await app.test(.GET, "api/todos") { res async in
            XCTAssertEqual(res.status, .ok)
            let todos = try res.content.decode([Todo].self)
            XCTAssertTrue(todos.isEmpty)
        }
    }

    // MARK: - Create

    func testCreateTodo() async throws {
        try await app.test(.POST, "api/todos", beforeRequest: { req in
            try req.content.encode(["title": "Buy groceries"])
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .created)
            let todo = try res.content.decode(Todo.self)
            XCTAssertEqual(todo.title, "Buy groceries")
            XCTAssertFalse(todo.isComplete)
        })
    }

    func testCreateTrimsWhitespace() async throws {
        try await app.test(.POST, "api/todos", beforeRequest: { req in
            try req.content.encode(["title": "  trimmed  "])
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .created)
            let todo = try res.content.decode(Todo.self)
            XCTAssertEqual(todo.title, "trimmed")
        })
    }

    func testCreateEmptyTitleReturns422() async throws {
        try await app.test(.POST, "api/todos", beforeRequest: { req in
            try req.content.encode(["title": ""])
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .unprocessableEntity)
        })
    }

    func testCreateWhitespaceTitleReturns422() async throws {
        try await app.test(.POST, "api/todos", beforeRequest: { req in
            try req.content.encode(["title": "   "])
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .unprocessableEntity)
        })
    }

    func testCreateTitleTooLongReturns422() async throws {
        let longTitle = String(repeating: "x", count: 256)
        try await app.test(.POST, "api/todos", beforeRequest: { req in
            try req.content.encode(["title": longTitle])
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .unprocessableEntity)
        })
    }

    // MARK: - Show

    func testShowNotFound() async throws {
        try await app.test(.GET, "api/todos/\(UUID())") { res async in
            XCTAssertEqual(res.status, .notFound)
        }
    }

    // MARK: - Delete

    func testDeleteTodo() async throws {
        let todo = Todo(title: "To delete")
        try await todo.save(on: app.db)
        let id = try todo.requireID()

        try await app.test(.DELETE, "api/todos/\(id)") { res async in
            XCTAssertEqual(res.status, .noContent)
        }

        let found = try await Todo.find(id, on: app.db)
        XCTAssertNil(found)
    }

    func testDeleteNotFound() async throws {
        try await app.test(.DELETE, "api/todos/\(UUID())") { res async in
            XCTAssertEqual(res.status, .notFound)
        }
    }
}
