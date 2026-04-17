# CTerm

CTerm is a native macOS terminal app built around AI coding workflows. It puts multi-project navigation, Git worktrees, agent presets, split terminals, and project-level automation into one AppKit window. The goal is not to be a general-purpose terminal emulator. The goal is to be a durable workspace for long-running coding sessions, parallel tasks, and fast context switching.

## What CTerm is trying to fix

AI-assisted development usually gets spread across too many places:

- agents running in terminal tabs
- project switching in Finder or an editor
- manual worktree creation and cleanup
- copied startup commands for each tool
- repeated setup every time a task changes

CTerm compresses those steps into one flow: choose a project, create a workspace, launch an agent, split panes, inspect status, and run project scripts without leaving the main window.

## Highlights

### 1. A terminal workspace designed for AI coding

The preset bar at the top can launch common agents directly instead of forcing you to retype long commands. Presets carry a name, command, description, provider, and whether they should appear in the main window. That makes tools like Claude, Codex, Gemini, and Aider feel like part of the product instead of loose shell aliases.

### 2. Git worktree-first workspace flow

Creating a workspace produces an isolated Git worktree and binds it to a branch, working directory, and agent session. This is a better fit for parallel task execution than constantly reusing one checkout and cleaning it up by hand.

### 3. Multi-tab and split-pane terminals

CTerm supports terminal tabs, horizontal and vertical splits, focus switching, and pane resizing. It is meant for real task decomposition, for example:

- one pane running an agent
- one pane watching tests or logs
- one pane for manual fixes or verification

### 4. Ghostty-backed terminal rendering

The terminal surface is backed by Ghostty instead of a hand-rolled text grid. That gives the app more modern terminal behavior and input handling while keeping a native AppKit shell around it.

### 5. Project-level automation

Projects can define `.cterm/config.json` with `setup`, `teardown`, and `run` scripts. CTerm executes them at the right points in the workspace lifecycle and injects:

- `CTERM_ROOT_PATH`
- `CTERM_WORKSPACE_NAME`
- `CTERM_WORKSPACE_PATH`

That makes project bootstrap and cleanup part of the workflow instead of tribal knowledge.

### 6. Global and project-specific agent presets

In addition to global presets, a repository can provide its own `.cterm/presets.json`. This lets each project define the most useful agent entry points for its own workflow while still preserving the user's global tools.

### 7. Sidebars built for actual development work

The main window is not just a terminal. It also includes project navigation, workspace management, file browsing, changes, and port-related views. The intent is to reduce how often you need to leave the terminal just to recover context.

### 8. Usage, provider, and performance visibility

The app surfaces token usage, provider status, and performance snapshots. In long-running agent sessions, those are operational signals rather than decoration.

### 9. Settings that support long-term use

The settings window covers:

- agent preset editing
- top-bar visibility for presets
- terminal font, size, theme, and cursor style
- general path and behavior settings
- shortcut inspection and reset

This is meant to make CTerm usable as a daily workstation, not just a demo shell.

## Typical workflow

A natural way to use CTerm looks like this:

1. Add a local project
2. Create a dedicated workspace for a task
3. Launch an agent from a preset
4. Split panes when you need parallel observation and verification
5. Let project scripts handle setup, run, or teardown steps
6. Stay in the same window while checking files, changes, and terminal state

It is a strong fit when you:

- run multiple agent-driven tasks in parallel
- rely heavily on temporary branches and worktrees
- want stable, named entry points for AI tooling
- prefer project context and terminal state to live in one native window

## Product direction

CTerm is not trying to be a terminal that does everything. It is closer to a macOS workbench for AI-assisted coding:

- the terminal is central
- projects and workspaces are first-class concepts
- agents are part of the core flow
- Git worktrees are a base unit, not an extra feature

If your day-to-day work already depends on agents, parallel task execution, and project-specific automation, this direction is likely a better fit than a traditional terminal-first setup.
