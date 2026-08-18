# Southsea Cinema Sync Rule

Whenever changes are made to the `southsea_cinema` public/template repository (located under `sandwich_shop/southsea_cinema/`), the agent must immediately mirror those changes to the `southsea_cinema_private` model solution repository (located under `sandwich_shop/southsea_cinema_private/`) to keep them in sync.
This applies to code files, configuration files, test suites, and documentation.

## Module Platform & Database Constraints

1. **Web-Only Platform Target**:
   - University lab computers do NOT have Visual Studio C++ Build Tools (Windows) or Xcode (macOS).
   - Only **Flutter Web** (`edge` or `chrome`) is supported as the target platform for all module exercises, projects, and courseworks.
   - Do NOT build, run, or configure desktop (Windows/macOS/Linux) or mobile native binaries for university lab environments.
   - All Flutter commands and launch configs must target Web: `flutter run -d edge` (or `flutter run -d chrome`).

2. **SQLite Database on Flutter Web**:
   - Web applications in browsers operate within a sandbox and cannot read/write physical SQLite `.db` files directly to local disk.
   - For laboratory exercises and coursework evaluation, SQLite is executed in WebAssembly using `sqflite_common_ffi_web` with `databaseFactoryFfiWebNoWebWorker`.
   - **Active Session CRUD**: All standard SQL operations (`CREATE TABLE`, `INSERT`, `SELECT`, `UPDATE`, `DELETE`, transactions) execute live in-memory during the web session so students can verify and grade functional database operations.
   - **Cloud Persistence**: For persistent, cross-device data storage in advanced coursework, students are directed to use cloud solutions such as Firebase.

## Response Style & Brevity

- Keep replies to the absolute minimum.
- Do not ramble, over-explain, or provide lengthy detailed outputs unless explicitly requested.
- State findings, actions, and solutions directly and concisely.

## Strict Formatting & Emoji Prohibition

- NEVER use emojis anywhere for visual decoration, fun, or flair.
- No emojis in agent responses, READMEs, source code, commit messages, comments, UI text, logs, or documentation.
- Only plain text, Markdown, and standard alphanumeric characters are permitted.
