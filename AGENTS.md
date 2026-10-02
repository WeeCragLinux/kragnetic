# AGENTS.md

Guidelines for AI agents working in this repository.

## Hard rules

1. **NEVER run builds.** Do not run `build-iso.sh`, `podman`/`docker` builds, `dcli`, `bootc`, or any other command that compiles, packages, or builds the OS image/ISO. The user tests and builds locally themselves. Read-only inspection (`ls`, `rg`, `cat`, `git status`, etc.) is fine.

2. **NEVER make changes before approval.** Do not edit, create, or delete files until you have presented a full plan (all intended changes, files touched, and reasoning) and the user has explicitly approved it. Only then implement.

## Working style

- Investigate and propose first; wait for a clear "go ahead" before touching anything.
- Keep plans concrete: list each file and the exact change.
- If a task seems to need a build to verify, stop and hand it back to the user instead.
