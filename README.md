# sdkman.el

Apply `.sdkmanrc` in Emacs

> **Unofficial integration.** `sdkman.el` is an unofficial Emacs package, not part of
> the SDKMAN! project. SDKMAN! lives at <https://sdkman.io>.

`sdkman.el` reads `.sdkmanrc` directly and applies the project's SDK
candidates to Emacs buffer-local environments, so subprocesses and
language servers see the project's SDK selection without depending on
shell auto-env behavior. GUI Emacs launched from the Dock or a Wayland
session gets the same SDK selection a terminal shell would get after
`sdk env`.

> **Status:** V1 in progress. Discovery, environment, mode, and
> `lsp-java` layers are implemented and tested. The transient command
> UI, the asynchronous `sdk` CLI wrapper, and an expanded out-of-the-box
> home-env-var list are still to come — see [Roadmap](#roadmap).

## What works today

**Every SDKMAN candidate** named in `.sdkmanrc` is resolved under
`SDKMAN_DIR` (default `~/.sdkman`), and its `bin/` directory is prepended
to buffer-local `exec-path` and `PATH`. Subprocesses spawned from that
buffer (`M-x shell`, `M-x compile`, language servers, etc.) see the
project's selected `java`, `mvn`, `gradle`, `scala`, `kotlin`, `sbt`,
`ant`, `groovy`, `jbang`, `spark`, `activemq`, or any other SDKMAN
candidate before the system version.

**Home environment variables** (`JAVA_HOME` / `MAVEN_HOME` /
`GRADLE_HOME`) are set buffer-locally for the three candidates listed in
`sdkman-known-env-vars`. Other candidates do not get a `<NAME>_HOME` set
automatically yet — add your own mapping via that defcustom if you need
one before the expanded defaults ship (see [Roadmap](#roadmap)):

```elisp
(setq sdkman-known-env-vars
      (append sdkman-known-env-vars
              '(("scala"     . "SCALA_HOME")
                ("kotlin"    . "KOTLIN_HOME")
                ("groovy"    . "GROOVY_HOME")
                ("ant"       . "ANT_HOME"))))
```

**Java + JDT LS** gets an extra layer. When `.sdkmanrc` contains
`java=<candidate>` and `lsp-java` is installed, `sdkman-lsp-java-apply`
points `lsp-java-java-path` at the project JDK's `bin/java` and seeds
`lsp-java-configuration-runtimes` with a `JavaSE-N` runtime derived
from the candidate version. JDT LS launches with the project JDK.

## Install

The package is not on MELPA yet. Clone the repo and load it locally.

With `use-package` and a path:

```elisp
(use-package sdkman
  :load-path "/path/to/sdkman.el/"
  :init
  (global-sdkman-mode 1))
```

With `straight.el`:

```elisp
(use-package sdkman
  :straight (sdkman :type git :host github :repo "systemhalted/sdkman.el")
  :init
  (global-sdkman-mode 1))
```

The package depends only on Emacs 27.1+. `lsp-java` is optional — used
only when present.

## Usage

Drop a `.sdkmanrc` in a project (or any ancestor directory):

```ini
# SDKMAN-managed SDKs for this project
java=26-tem
maven=3.9.15
```

Visit any file under that directory. `global-sdkman-mode` applies the
project SDK selection buffer-locally as described in
[What works today](#what-works-today).

The Java language level still comes from Maven/Gradle/Eclipse project
metadata (e.g. `maven.compiler.release`), not from `JAVA_HOME` alone.

### Public API

| Symbol                          | Kind     | Purpose                                                       |
| ------------------------------- | -------- | ------------------------------------------------------------- |
| `sdkman-mode`                   | minor    | Apply project SDKMAN env to the current buffer.               |
| `global-sdkman-mode`            | global   | Activate `sdkman-mode` in file buffers with a `.sdkmanrc`.    |
| `sdkman-apply-buffer-env`       | function | Apply the project env once, without enabling the mode.        |
| `sdkman-lsp-java-apply`         | function | Apply `lsp-java`-specific settings for the project Java.      |
| `sdkman-find-sdkmanrc`          | function | Locate the nearest `.sdkmanrc`.                               |
| `sdkman-read-sdkmanrc`          | function | Parse a `.sdkmanrc` into an alist.                            |
| `sdkman-candidate-home`         | function | Resolve an installed candidate's home directory.              |
| `sdkman-installed-candidates`   | function | List installed candidates for an SDK.                         |
| `sdkman-current-candidate`      | function | Read the SDKMAN `current` symlink for an SDK.                 |
| `sdkman-lsp-java-excluded-file-p` | function | Predicate: file is inside an `lsp-java` generated directory. |

### Customization

- `sdkman-root` — override SDKMAN root (defaults to `SDKMAN_DIR` or `~/.sdkman`).
- `sdkman-known-env-vars` — alist mapping SDK names to home env vars.
- `sdkman-auto-apply` — whether `global-sdkman-mode` activates per buffer.
- `sdkman-warn-on-missing-candidate` — warn when `.sdkmanrc` names an uninstalled candidate.
- `sdkman-lsp-java-excluded-directories` — directories where `lsp-deferred` should be skipped.
- `sdkman-before-apply-hook`, `sdkman-after-apply-hook` — run around buffer application.

## Test

```sh
emacs --batch -Q -L . -l test/sdkman-test.el -f ert-run-tests-batch-and-exit
```

24 tests cover the parser, candidate resolution, environment application
(including PATH/exec-path dedupe and missing-candidate warnings), the
`lsp-java` integration, runtime-name derivation, and the exclusion
predicate.

## Roadmap

Planned for upcoming releases. See
[`docs/v1-plan.md`](docs/v1-plan.md) for the phased implementation plan,
and [`docs/requirements.md`](docs/requirements.md) for the V1 spec.

- **Expanded `sdkman-known-env-vars` defaults.** Out-of-the-box
  `<NAME>_HOME` for the common JVM-ecosystem SDKs: `ant`, `groovy`,
  `scala`, `kotlin`, `sbt`, `spark`, `hadoop`, `micronaut`,
  `springboot`, `quarkus`, `jbang`, `mvnd`, `leiningen`, `activemq`.
- **Transient command UI (`M-x sdkman`).** A Magit-style menu showing
  SDKMAN root, the nearest `.sdkmanrc`, parsed entries, and
  installed/current candidates; with actions to switch project SDKs,
  open or create `.sdkmanrc`, and drive the SDKMAN CLI.
- **Asynchronous `sdk` CLI wrapper.** `sdk list` / `install` /
  `uninstall` / `default` / `current` / `upgrade` / `selfupdate`
  driven from inside Emacs into a dedicated process buffer, with
  confirmation prompts on global-mutating operations.
- **Explicit LSP-restart command.** Apply SDKMAN state and then call
  the appropriate LSP restart, instead of leaving the user to
  remember.

## Non-goals (for V1)

- Reimplement SDKMAN candidate discovery from remote APIs. The
  installed `sdk` command remains the source of truth for remote,
  list, install, and uninstall operations.
- Infer Java language level from SDKMAN. Project metadata
  (Maven/Gradle/Eclipse) is the source of language and compliance
  level.
- Automatically restart existing LSP workspaces when SDKMAN state
  changes. Explicit user action is required.

## License

GPL-3.0-or-later. See [`LICENSE`](LICENSE).
