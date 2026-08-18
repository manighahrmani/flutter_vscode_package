# Flutter & VS Code Portable Package - Copilot Instructions

## Platform & Development Rules

- **Target Platform**: Only **Flutter Web** is supported (`edge` / `chrome`). Lab machines do not have C++ desktop build tools or Xcode.
- **SQLite Support**: On Flutter Web, SQLite operations run in-memory via `sqflite_common_ffi_web` (`databaseFactoryFfiWebNoWebWorker`). CRUD operations persist for the duration of the active web session. For permanent cloud storage across sessions, use Firebase.
- **VS Code Configuration**: All workspaces are trusted by default (`security.workspace.trust.enabled: false`) with auto-save enabled.
