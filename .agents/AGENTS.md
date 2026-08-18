# Flutter & VS Code Portable Package - Agent Steering Rules

## Module & Environment Constraints

1. **Web-Only Platform Constraint**:
   - University lab computers do NOT have Visual Studio C++ Build Tools (Windows) or Xcode (macOS).
   - Only **Flutter Web** (`edge` or `chrome`) is supported as the target platform for all module exercises, projects, and courseworks.
   - Do NOT attempt to build, run, or configure desktop (Windows/macOS/Linux) or mobile (Android/iOS) native builds on university computers.
   - All Flutter CLI commands must target Web: `flutter run -d edge` (or `flutter run -d chrome`).

2. **SQLite Database on Flutter Web**:
   - Web applications in browsers operate within a secure sandbox and cannot read or write physical SQLite `.db` files directly to local disk.
   - For coursework and laboratory sessions, SQLite is executed in WebAssembly using `sqflite_common_ffi_web` with `databaseFactoryFfiWebNoWebWorker`.
   - **Active Session CRUD**: All standard SQL operations (`CREATE TABLE`, `INSERT`, `SELECT`, `UPDATE`, `DELETE`, transactions) execute live in-memory during the web session so students can verify and grade functional database operations.
   - **Cloud Persistence**: For persistent, cross-device data storage in advanced coursework, students are directed to use cloud solutions such as Firebase.

3. **Workspace Trust & Extensions**:
   - Portable VS Code has Workspace Trust disabled (`security.workspace.trust.enabled: false`) to ensure all pre-installed extensions (Dart, Flutter, GitHub Copilot, ErrorLens, Material Icons, SQLite Viewer) activate immediately without prompting.
   - The workspace root is `$ScriptRoot\workspace`, containing `pubspec.yaml`, `lib/`, `web/`, and `.vscode/`.
