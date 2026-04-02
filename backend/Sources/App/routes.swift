import Vapor

func routes(_ app: Application) throws {
    let api = app.grouped("api")
    api.get("health") { req async in ["status": "ok"] }
    try api.register(collection: TodoController())
    try api.register(collection: SubtaskController())

    // SPA fallback — serves index.html for root and any unmatched path
    // FileMiddleware handles /_app/* static assets; these handle HTML routing
    let indexHandler: @Sendable (Request) -> Response = { req in
        let path = req.application.directory.publicDirectory + "index.html"
        return req.fileio.streamFile(at: path)
    }
    app.get(use: indexHandler)       // matches /
    app.get("**", use: indexHandler) // matches everything else
}
