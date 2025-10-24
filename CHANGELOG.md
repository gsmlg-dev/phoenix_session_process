# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2024-10-24

### Added
- **Redux State Management**: New `Phoenix.SessionProcess.Redux` module for predictable state updates
  - Time-travel debugging with complete action history
  - Middleware support for logging, validation, and side effects
  - State persistence and replay capabilities
  - Reducer pattern for handling actions
  - Configurable action history size
- **Agent-Based State**: New `Phoenix.SessionProcess.State` module for simple key-value storage
  - Lightweight Agent-based state management
  - Simple get/put API for quick prototyping
  - Redux dispatch support for hybrid approaches
- **Enhanced Documentation**: Comprehensive guides and examples
  - State management comparison and usage patterns
  - Redux migration guide with step-by-step instructions
  - Benchmark documentation and performance tuning guide
  - Architecture documentation in CLAUDE.md
- **Developer Experience**: Improved debugging and monitoring
  - Action history tracking in Redux mode
  - State inspection tools
  - Middleware for custom debugging logic

### Changed
- Updated README.md with comprehensive state management section
- Enhanced MIGRATION_GUIDE.md with Redux patterns and examples
- Improved documentation structure and clarity

### Documentation
- Added detailed comparison of three state management approaches
- Included comprehensive examples for each approach
- Added performance benchmarking guide
- Enhanced architecture documentation

## [0.3.1] - 2024-09-30

### Fixed
- Bug fixes and stability improvements

## [0.3.0] - 2024-09-30

### Added
- `get_session_id/0` helper function within session processes
  - Access current session ID from within GenServer callbacks
  - Simplifies session-aware logic implementation

## [0.2.0] - 2024-02-05

### Added
- `list_sessions/0` function to retrieve all active session IDs
- `:process_link` macro for LiveView integration
  - Automatic LiveView process monitoring
  - `:session_expired` message sent when sessions terminate
  - Enhanced session lifecycle management

### Features
- Session process discovery and introspection
- LiveView-aware session management

## [0.1.0] - 2024-02-05

### Added
- Initial release of Phoenix.SessionProcess
- Core session process management with GenServer
- `Phoenix.SessionProcess.Supervisor` for managing session lifecycle
- `Phoenix.SessionProcess.ProcessSupervisor` for dynamic process creation
- `Phoenix.SessionProcess.Registry` for session lookup
- `Phoenix.SessionProcess.Cleanup` for TTL-based automatic cleanup
- `Phoenix.SessionProcess.SessionId` plug for session ID generation
- Basic telemetry events for monitoring
- Configuration options for session limits, TTL, and rate limiting
- Error handling with detailed error types
- `:process` macro for basic session processes
- Session validation and limit enforcement

### Features
- Session isolation with dedicated GenServer per session
- Automatic cleanup with configurable TTL
- High-performance registry-based lookups
- Comprehensive error handling
- Rate limiting and session limit enforcement
- Telemetry integration for monitoring

[0.4.0]: https://github.com/gsmlg-dev/phoenix_session_process/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/gsmlg-dev/phoenix_session_process/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/gsmlg-dev/phoenix_session_process/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/gsmlg-dev/phoenix_session_process/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/gsmlg-dev/phoenix_session_process/releases/tag/v0.1.0

