# sdkman.el Requirements

## Summary

`sdkman.el` is a standalone Emacs package that makes SDKMAN project environments first-class inside Emacs. It should read `.sdkmanrc` directly, apply project SDK candidates to Emacs buffer/process environments, provide a Magit-like command surface, and integrate with `lsp-java` so Java language servers use the project JDK.

The package should not depend on shell auto-env behavior. Emacs must be able to launch as a GUI app, visit a project with `.sdkmanrc`, and get the same SDK selection a terminal shell would get after `sdk env`.

## Goals

- Provide package `sdkman.el` and feature `sdkman`.
- Support generic SDKMAN candidates from `.sdkmanrc`, not only Java.
- Apply SDKMAN project environments buffer-locally and predictably.
- Provide `sdkman-mode` and `global-sdkman-mode` for automatic activation.
- Provide a `transient`-based command UI similar in spirit to Magit.
- Integrate with `lsp-java` by configuring the JVM used to launch JDT LS and the Java runtime advertised to JDT LS.
- Prefer project-local `.sdkmanrc` changes over global SDKMAN mutation.

## Non-Goals for V1

- Reimplement SDKMAN candidate discovery from remote APIs. Use the installed `sdk` command for remote/list/install operations.
- Infer Java language level from SDKMAN alone. Maven, Gradle, and Eclipse project metadata remain the source of language/compliance level.
- Automatically restart existing LSP workspaces when SDKMAN state changes. Provide explicit restart commands instead.
- Require `exec-path-from-shell` or shell startup files for core project environment behavior.

## SDKMAN Discovery

- Detect the SDKMAN root from `SDKMAN_DIR`; otherwise default to `~/.sdkman`.
- Treat candidates as installed when `~/.sdkman/candidates/<sdk>/<candidate>` exists.
- Treat `~/.sdkman/candidates/<sdk>/current` as the current candidate for that SDK when present.
- Find project config with nearest ancestor `.sdkmanrc` from the current buffer file or explicit directory.
- Parse `.sdkmanrc` lines as `sdk=candidate`, ignoring blank lines and comments beginning with `#`.
- Preserve unknown SDK keys generically. Special behavior is layered only where needed, such as Java.

## Environment Application

- Provide `sdkman-apply-buffer-env` to apply the nearest `.sdkmanrc` to the current buffer.
- Make environment changes buffer-local:
  - copy and update `process-environment`
  - prepend each resolved candidate `bin` directory to `exec-path`
  - prepend each resolved candidate `bin` directory to `PATH`
- Known SDK-specific variables:
  - `java` sets `JAVA_HOME`
  - additional SDK-specific env vars may be added later through a customizable mapping.
- Missing candidates should not silently fall back. Report a clear warning with SDK name, candidate name, and expected path.
- Reapplying should be idempotent and should avoid accumulating duplicate PATH/exec-path entries.

## Modes

- `sdkman-mode` applies the project SDKMAN environment to the current buffer.
- `global-sdkman-mode` enables automatic activation for file-backed buffers.
- Activation should run before tools that spawn subprocesses, especially LSP startup hooks.
- Provide hooks:
  - `sdkman-before-apply-hook`
  - `sdkman-after-apply-hook`
- Provide user options:
  - `sdkman-root`
  - `sdkman-auto-apply`
  - `sdkman-known-env-vars`
  - `sdkman-warn-on-missing-candidate`

## lsp-java Integration

- Provide optional integration loaded with `with-eval-after-load` or explicit user hook.
- Provide `sdkman-lsp-java-apply`.
- When `.sdkmanrc` contains `java=<candidate>`:
  - resolve `<java-home>` from SDKMAN candidates
  - set buffer-local `lsp-java-java-path` to `<java-home>/bin/java`
  - set buffer-local `lsp-java-configuration-runtimes` to a vector with a default runtime entry
  - derive runtime name as `JavaSE-N` from the candidate version, for example `26-tem` -> `JavaSE-26`
- The package must document that Java language level still comes from Maven/Gradle/Eclipse metadata, not from `JAVA_HOME` alone.
- Existing LSP workspaces should not be restarted implicitly. Provide a command that applies SDKMAN state and then calls the appropriate LSP restart when available.

## Transient UI

- Provide main entry command `sdkman`.
- Use `transient` as the command surface.
- Show current status:
  - SDKMAN root
  - nearest `.sdkmanrc`
  - parsed project SDK entries
  - installed/current candidate for each SDK
  - missing project candidates
  - active buffer-local Java/LSP settings when relevant
- Provide actions:
  - list installed candidates by SDK
  - show project environment
  - open nearest `.sdkmanrc`
  - create `.sdkmanrc` for current project
  - switch project SDK by editing `.sdkmanrc`
  - run `sdk list`
  - run `sdk install`
  - run `sdk uninstall`
  - run `sdk default`
  - run `sdk current`
  - run `sdk upgrade`
  - run `sdk selfupdate`
- Project switching should update only `.sdkmanrc` by default.
- Global SDKMAN mutations such as install, uninstall, default, upgrade, and selfupdate require explicit confirmation.
- SDKMAN CLI commands should run asynchronously and display output in a dedicated process buffer.

## Public API

- `sdkman-root`
- `sdkman-find-sdkmanrc`
- `sdkman-read-sdkmanrc`
- `sdkman-candidate-home`
- `sdkman-installed-candidates`
- `sdkman-current-candidate`
- `sdkman-apply-buffer-env`
- `sdkman-lsp-java-apply`
- `sdkman-mode`
- `global-sdkman-mode`
- `sdkman`

## Error Handling

- Missing SDKMAN root: report a user-facing error for explicit commands and a warning for automatic activation.
- Missing candidate directory: warn and leave that SDK unapplied.
- Malformed `.sdkmanrc`: report line number and offending text.
- Missing `sdk` executable: local candidate/env functionality should still work; CLI actions should report the missing executable.
- CLI command failures should show exit status and process buffer.

## Tests

Use ERT. Tests should create temporary SDKMAN roots and project directories.

Required test areas:

- `.sdkmanrc` parser handles comments, blank lines, multiple SDKs, malformed lines, and whitespace.
- Candidate resolution handles installed candidates, missing candidates, and `current` symlinks.
- Buffer env application sets `process-environment`, `PATH`, and `exec-path` without duplicates.
- Java integration sets `JAVA_HOME`, `lsp-java-java-path`, and `lsp-java-configuration-runtimes`.
- Runtime-name derivation maps `26-tem` to `JavaSE-26` and `21.0.11-tem` to `JavaSE-21`.
- Transient command functions can be tested at the command/helper layer without requiring an interactive UI.

## Manual Acceptance Scenarios

- GUI Emacs opens a project with `.sdkmanrc` containing `java=26-tem`; JDT LS launches with `<sdkman>/candidates/java/26-tem/bin/java`.
- A project with `maven=<version>` causes Emacs subprocesses in that buffer to find that Maven before global PATH entries.
- `M-x sdkman` shows project status and installed/current candidates.
- Switching project Java through the UI updates `.sdkmanrc`, reapplies the buffer environment, and offers an explicit LSP restart.
- Global SDKMAN operations prompt before changing SDKMAN global state.
