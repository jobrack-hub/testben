import Fluent
import FluentSQLiteDriver
import Vapor

public func configure(_ app: Application) throws {
    // CORS — registered at .beginning so OPTIONS preflight is handled
    // before ErrorMiddleware can intercept it with a 404
    let corsConfig = CORSMiddleware.Configuration(
        allowedOrigin: .originBased, // allows both localhost:5173 and benjamin.test:5173
        allowedMethods: [.GET, .POST, .PUT, .DELETE, .OPTIONS, .PATCH],
        allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith],
        allowCredentials: false,
        cacheExpiration: 600
    )
    app.middleware.use(CORSMiddleware(configuration: corsConfig), at: .beginning)

    // Serve static files (SvelteKit build) from Public/ — no-op in dev (empty dir)
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    // SQLite path: override via DB_PATH env var in production (Fly volume: /data/db.sqlite)
    let dbPath = Environment.get("DB_PATH") ?? "db.sqlite"
    app.databases.use(.sqlite(.file(dbPath)), as: .sqlite)

    // Register and auto-run migrations on startup
    app.migrations.add(CreateTodo())
    app.migrations.add(AddTimeSpentToTodo())
    app.migrations.add(AddProjectFields())
    app.migrations.add(AddDescriptionToTodo())
    app.migrations.add(CreateSubtask())
    try app.autoMigrate().wait()

    try routes(app)
}
