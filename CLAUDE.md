# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is Phoenix.SessionProcess, an Elixir library that creates a process for each user session in Phoenix applications. All user requests go through their dedicated session process, providing session isolation and state management.

## Key Commands

### Development Commands
- `mix deps.get` - Install dependencies
- `mix test` - Run all tests
- `mix test test/path/to/specific_test.exs` - Run a specific test file
- `mix compile` - Compile the project
- `mix docs` - Generate documentation
- `mix hex.publish` - Publish to Hex.pm (requires authentication)

### Testing
The test suite uses ExUnit. Tests are located in the `test/` directory. The test helper starts the supervisor automatically.

## Architecture

### Core Components

1. **Phoenix.SessionProcess** (lib/phoenix/session_process.ex:1)
   - Main module providing the public API
   - Delegates to ProcessSupervisor for actual process management
   - Provides macros for creating session processes

2. **Phoenix.SessionProcess.Supervisor** (lib/phoenix/session_process/superviser.ex)
   - Top-level supervisor that manages the Registry and ProcessSupervisor
   - Must be added to the application's supervision tree

3. **Phoenix.SessionProcess.ProcessSupervisor** (lib/phoenix/session_process/process_superviser.ex)
   - DynamicSupervisor that manages individual session processes
   - Handles starting, terminating, and communicating with session processes

4. **Phoenix.SessionProcess.SessionId** (lib/phoenix/session_process/session_id.ex)
   - Plug that generates unique session IDs
   - Must be placed after `:fetch_session` plug

### Process Management Flow

1. Session ID generation via the SessionId plug
2. Process creation through `Phoenix.SessionProcess.start/1-3`
3. Processes are registered in `Phoenix.SessionProcess.Registry`
4. Communication via `call/2-3` and `cast/2`
5. Automatic cleanup when processes terminate

### Key Design Patterns

- Uses Registry for process lookup by session ID
- DynamicSupervisor for on-demand process creation
- Provides two macros: `:process` (basic) and `:process_link` (with LiveView monitoring)
- Session processes can monitor LiveView processes and notify them on termination

## Configuration

The library uses application configuration:
```elixir
config :phoenix_session_process, session_process: MySessionProcess
```

This sets the default module to use when starting session processes without specifying a module.

## Usage in Phoenix Applications

1. Add supervisor to application supervision tree
2. Add SessionId plug after fetch_session
3. Define custom session process modules using the provided macros
4. Start processes with session IDs
5. Communicate using call/cast operations