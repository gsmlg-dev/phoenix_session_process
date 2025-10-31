# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-10-31

### Breaking Changes

- **Renamed `@prefix` to `@action_prefix` in reducer modules**
  - All reducer modules must now use `@action_prefix` instead of `@prefix`
  - The `@action_prefix` can be `nil` or `""` to create catch-all reducers that handle all actions
  - Migration: Simply rename `@prefix` to `@action_prefix` in your reducer modules
  - Example:
    ```elixir
    # Before (v0.x)
    defmodule MyReducer do
      use Phoenix.SessionProcess, :reducer
      @name :my_reducer
      @prefix "my"  # Old name
    end

    # After (v1.0.0)
    defmodule MyReducer do
      use Phoenix.SessionProcess, :reducer
      @name :my_reducer
      @action_prefix "my"  # New name
    end
    ```

- **Changed `dispatch/3` and `dispatch_async/3` return values**
  - Both functions now return `:ok` instead of `{:ok, new_state}`
  - All dispatches are now async (fire-and-forget) by default
  - Use `get_state/1-2` to retrieve state after dispatch
  - Migration:
    ```elixir
    # Before (v0.x)
    {:ok, new_state} = SessionProcess.dispatch(session_id, :increment)
    IO.inspect(new_state)

    # After (v1.0.0)
    :ok = SessionProcess.dispatch(session_id, :increment)
    new_state = SessionProcess.get_state(session_id)
    IO.inspect(new_state)
    ```

- **Removed deprecated `Phoenix.SessionProcess.Redux` module**
  - The old struct-based Redux API has been removed
  - Use the Redux Store API (built into SessionProcess) instead
  - See migration guide: `REDUX_TO_SESSIONPROCESS_MIGRATION.md`

### Added

- **`dispatch_async/3` function for explicit async dispatch**
  - Same behavior as `dispatch/3` but with clearer naming for async operations
  - Makes code intent more explicit when dispatching async actions
  - Example: `:ok = SessionProcess.dispatch_async(session_id, :increment)`

### Changed

- **Improved action routing with `@action_prefix`**
  - More consistent naming aligns with action routing semantics
  - Catch-all reducers now explicitly use `nil` or `""` for `@action_prefix`
  - Better documentation and examples for action routing

### Migration Guide

1. **Rename `@prefix` to `@action_prefix` in all reducer modules**
   - Search your codebase for `@prefix` in reducer modules
   - Replace with `@action_prefix`
   - No logic changes required

2. **Update dispatch call sites to handle `:ok` return value**
   - Replace `{:ok, state} = dispatch(...)` with `:ok = dispatch(...)`
   - Add `get_state(session_id)` calls where you need the updated state
   - Consider: Do you actually need the state? Many dispatches are fire-and-forget

3. **Remove uses of deprecated Redux module**
   - If using `Phoenix.SessionProcess.Redux` struct-based API
   - Migrate to Redux Store API (SessionProcess IS the store)
   - See `REDUX_TO_SESSIONPROCESS_MIGRATION.md` for detailed migration

### Notes

- All changes are breaking but migrations are straightforward
- Most codebases will only need to rename `@prefix` to `@action_prefix`
- Dispatch return value change makes async nature more explicit
- v0.9.x will be the last version supporting deprecated APIs

## [0.6.0] - 2025-10-29

### Added
- **Redux Store API**: SessionProcess now IS the Redux store - no separate Redux struct needed
  - `Phoenix.SessionProcess.dispatch/3` - Dispatch actions synchronously or asynchronously
  - `Phoenix.SessionProcess.subscribe/4` - Subscribe to state changes with optional selectors
  - `Phoenix.SessionProcess.unsubscribe/2` - Remove subscriptions
  - `Phoenix.SessionProcess.register_reducer/3` - Register named reducers
  - `Phoenix.SessionProcess.register_selector/3` - Register named selectors
  - `Phoenix.SessionProcess.get_state/2` - Get state with optional selector
  - `Phoenix.SessionProcess.select/2` - Apply registered selector to current state
  - `user_init/1` callback for defining initial Redux state
- **Enhanced LiveView Integration**: New helpers for Redux Store API
  - `Phoenix.SessionProcess.LiveView.mount_store/4` - Mount with direct SessionProcess subscriptions
  - `Phoenix.SessionProcess.LiveView.unmount_store/1` - Clean up subscriptions (optional, automatic cleanup via monitoring)
  - `Phoenix.SessionProcess.LiveView.dispatch_store/3` - Dispatch actions with sync/async options
- **Selector-Based Subscriptions**: Only receive updates when selected state changes
  - Efficient fine-grained state updates
  - Memoized selector support
  - Automatic equality checking to prevent unnecessary notifications
- **Process Monitoring**: Automatic subscription cleanup when LiveView processes terminate
- **Comprehensive Documentation**: Migration guides and examples
  - `MIGRATION_GUIDE.md` - Quick migration guide with 2-step process
  - `REDUX_TO_SESSIONPROCESS_MIGRATION.md` - Detailed migration guide
  - `examples/liveview_redux_store_example.ex` - Complete working example (400+ lines)
  - Updated CLAUDE.md with comprehensive Redux Store API documentation

### Changed
- **70% Less Boilerplate**: Simplified API eliminates manual Redux struct management
- **Simpler Architecture**: SessionProcess handles Redux infrastructure internally
- **Better Performance**: Selector-based updates reduce unnecessary state notifications
- **Improved DX**: Clearer code intent with less nesting and fewer concepts

### Deprecated
- `Phoenix.SessionProcess.Redux` module - Use Redux Store API instead
  - `Redux.init_state/2` - Use `user_init/1` callback
  - `Redux.dispatch/3` - Use `SessionProcess.dispatch/3`
  - `Redux.subscribe/3` - Use `SessionProcess.subscribe/4`
  - `Redux.get_state/1` - Use `SessionProcess.get_state/2`
- `Phoenix.SessionProcess.LiveView` old API - Use new Redux Store API
  - `mount_session/4` - Use `mount_store/4`
  - `unmount_session/1` - Use `unmount_store/1`
- **Migration Timeline**: Deprecated APIs will be removed in v1.0.0 (supported through v0.9.x)

### Migration
- All old code continues to work with deprecation warnings
- See `MIGRATION_GUIDE.md` for quick 2-step migration
- See `REDUX_TO_SESSIONPROCESS_MIGRATION.md` for detailed examples
- No breaking changes - 100% backward compatible

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

[0.6.0]: https://github.com/gsmlg-dev/phoenix_session_process/compare/v0.4.0...v0.6.0
[0.4.0]: https://github.com/gsmlg-dev/phoenix_session_process/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/gsmlg-dev/phoenix_session_process/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/gsmlg-dev/phoenix_session_process/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/gsmlg-dev/phoenix_session_process/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/gsmlg-dev/phoenix_session_process/releases/tag/v0.1.0

