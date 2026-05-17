# sdkman.el — V1 completion plan

This document plans the remaining V1 work described in
[`requirements.md`](requirements.md). The shipped 0.1.0 release already
covers SDKMAN discovery, buffer-local environment application,
`sdkman-mode` / `global-sdkman-mode`, and `lsp-java` integration. What
remains is primarily the transient command UI, the asynchronous `sdk`
CLI wrapper, project-local `.sdkmanrc` editing, and the residual
error-handling and test gaps.

The work is broken into six phases that each leave the package in a
shippable state.

## Conventions

- Every phase ends with the full quality gate green:
  `emacs --batch -Q -L . -l test/sdkman-test.el -f ert-run-tests-batch-and-exit`,
  `batch-byte-compile`, `checkdoc-file`, `package-lint-batch-and-exit`.
- New defcustoms must have docstrings checkdoc accepts.
- The README "Roadmap" section is updated at the end of every phase to
  reflect what is now done.
- No phase introduces a hard dependency on `lsp-java` or `transient`
  beyond what `Package-Requires` declares.

Critical files (all phases):

- `sdkman.el`
- `test/sdkman-test.el`
- `README.md`
- `docs/requirements.md` (reference only)

---

## Phase 0 — Foundation

Small, self-contained pieces that unblock later phases and close gaps
already exposed in 0.1.0.

### Tasks

1. **Expand `sdkman-known-env-vars` defaults.** Add the conventional
   `<NAME>_HOME` entries the roadmap promises: `ant`, `groovy`, `scala`,
   `kotlin`, `sbt`, `spark`, `hadoop`, `micronaut`, `springboot`,
   `quarkus`, `jbang`, `mvnd`, `leiningen`, `activemq`. Defcustom in
   `sdkman.el`. Update the README "Home environment variables"
   paragraph to reflect the expanded list.
2. **Missing-SDKMAN-root error path.** Add `sdkman--ensure-root` helper
   that returns the root or signals (`user-error` for "explicit"
   callers, `display-warning` for "implicit" / hook callers). Wire it
   into `sdkman-apply-buffer-env` (implicit) and the future `sdkman`
   entry command (explicit). Spec: requirements.md §Error Handling.
3. **`sdk` shell-function runner.** `sdk` is a bash function, not a
   binary, so the runner must spawn
   `bash -lc "source $SDKMAN_DIR/bin/sdkman-init.sh && sdk …"`. Add
   `sdkman--init-script` (returns absolute path or nil) and
   `sdkman--run-sdk-async (subcommand args &key buffer sentinel)`.
   No UI yet — pure helper. Spec: requirements.md §Transient UI ("run
   asynchronously and display output in a dedicated process buffer").
4. **Missing-`sdk` / missing-init-script error path.** When
   `sdkman--init-script` returns nil, CLI actions must `user-error`
   with the expected path. Local candidate/env functionality is
   unaffected. Spec: requirements.md §Error Handling.
5. **Tests.** Whitespace edge cases in the parser (closes the §Tests
   gap), `sdkman--ensure-root` behavior in both modes,
   `sdkman--init-script` resolution under a fake root,
   `sdkman--run-sdk-async` writes output to its target buffer when
   given a stub `bash` (use `process-environment` to point `PATH` at a
   tempdir with a script named `bash` for the test).

### Exit criteria

- All defcustoms documented; README updated; quality gate green.
- No new public commands yet — the package looks unchanged to users
  except for the wider env-var defaults.

---

## Phase 1 — Transient skeleton + read-only status

Stand up `M-x sdkman` with a status view and the read-only actions that
need no subprocess plumbing. After this phase the package has its first
user-facing entry point.

### Tasks

1. **Add `transient` to `Package-Requires`.** Bump version to `0.2.0`.
   Declare `transient` requirement in the header (`((emacs "27.1")
   (transient "0.4.0"))`).
2. **Status helper.** `sdkman--status-lines` returns a list of
   formatted strings: SDKMAN root, nearest `.sdkmanrc` (or "(none)"),
   parsed entries, installed/current candidate per SDK in the file,
   missing project candidates, active buffer-local `JAVA_HOME` /
   `lsp-java-java-path` when relevant. Pure function; testable.
   Spec: requirements.md §Transient UI.
3. **`sdkman` transient entry.**
   ```elisp
   ;;;###autoload (autoload 'sdkman "sdkman" nil t)
   (transient-define-prefix sdkman ()
     "SDKMAN project menu.")
   ```
   Status section uses `:description` derived from
   `sdkman--status-lines` so the menu reflects the current buffer.
4. **Read-only actions (no shell).**
   - `o` — `sdkman-open-sdkmanrc`: `find-file` the nearest `.sdkmanrc`,
     `user-error` if none.
   - `e` — `sdkman-show-env`: render the alist returned by
     `sdkman-apply-buffer-env` in a `*sdkman env*` help-style buffer.
   - `i` — `sdkman-show-installed`: prompt for an SDK (completion from
     `directory-files` under `candidates/`), display
     `sdkman-installed-candidates` for it in a buffer.
5. **Tests for transient helpers.** `sdkman--status-lines` against fake
   roots covering: no `.sdkmanrc`, one entry, multiple entries, missing
   candidate row, current-symlink row. No interactive transient tests.
   Spec: requirements.md §Tests ("Transient command functions can be
   tested at the command/helper layer without requiring an interactive
   UI").
6. **README.** Add a "Transient menu" subsection documenting `M-x
   sdkman` and the three read-only actions. Move "Transient command
   UI" off the roadmap.

### Exit criteria

- `M-x sdkman` opens; status accurate; three actions work; quality
  gate green.

---

## Phase 2 — Read-only `sdk` CLI passthrough

Wire the runner from Phase 0 into the transient for the two commands
that don't mutate global state: `sdk list` and `sdk current`.

### Tasks

1. **Process-buffer mode.** `sdkman-process-mode`, derived from
   `compilation-mode` so error navigation and `q` work out of the box.
   Output buffer named `*sdkman: <subcommand>*`, reused across runs of
   the same subcommand.
2. **`sdkman-sdk-list`.** Prompt for an SDK (with completion); run
   `sdk list <sdk>` async; display in the process buffer;
   `pop-to-buffer` on completion.
3. **`sdkman-sdk-current`.** Run `sdk current` async; display.
4. **Transient bindings.** `L` → `sdkman-sdk-list`, `C` →
   `sdkman-sdk-current`.
5. **Failure path.** Sentinel: on non-zero exit, message exit status
   and leave the process buffer visible. Spec: requirements.md
   §Error Handling.
6. **Tests.** Sentinel/exit-handling test using the stub `bash` trick
   from Phase 0; assert process buffer content and the user-facing
   message. No real `sdk` invocation in tests.

### Exit criteria

- Both actions launch real `sdk` commands when SDKMAN is installed.
- Process buffer comprehensible (header line shows command, exit
  status surfaces on failure).
- Quality gate green.

---

## Phase 3 — Project-local SDK switching

Edit `.sdkmanrc` from inside Emacs without touching global SDKMAN
state. This is the "switch project Java through the UI" acceptance
scenario.

### Tasks

1. **Writer.** `sdkman--write-sdkmanrc (entries file)` writes an
   ordered alist back to a file, preserving newline-at-eof.
   Idempotent.
2. **Create.** `sdkman-create-sdkmanrc`: prompts for project root
   (default = `(project-root)` or `default-directory`), writes a
   commented stub, opens the file. Refuses to overwrite an existing
   one (`user-error`).
3. **Switch.** `sdkman-switch-sdk`:
   - read existing entries (or start empty),
   - prompt for SDK (completion from installed SDKs),
   - prompt for candidate (completion from
     `sdkman-installed-candidates` for that SDK + `"<remove>"`
     choice),
   - rewrite `.sdkmanrc`,
   - re-run `sdkman-mode` on every buffer whose `default-directory`
     is under the project root, so the new env applies immediately.
4. **Transient bindings.** `n` → `sdkman-create-sdkmanrc`, `s` →
   `sdkman-switch-sdk`.
5. **Tests.** Writer round-trips the parser output. Switching adds an
   SDK to an empty file, replaces an existing entry, removes an
   entry, and triggers re-application in a temp buffer pointed at the
   project.
6. **README.** Move ".sdkmanrc create/edit commands" off the roadmap.

### Exit criteria

- Editing a project's SDK no longer requires opening the file by hand.
- Buffers in the project see the new env without `revert-buffer`.

---

## Phase 4 — Explicit LSP restart

Project switching today doesn't touch JDT LS. The spec says we don't
restart implicitly, but should offer an explicit command
(requirements.md §lsp-java Integration, §Manual Acceptance Scenarios).

### Tasks

1. **`sdkman-restart-lsp`.** Apply `sdkman-mode` to the current
   buffer, then call `lsp-workspace-restart` on every LSP workspace
   rooted at or under `default-directory`. No-op (with `message`)
   when `lsp-mode` isn't loaded.
2. **Switch-and-restart variant.** Extend `sdkman-switch-sdk` so that
   after the rewrite + reapply step it offers (via `y-or-n-p`) to
   call `sdkman-restart-lsp`. Default: no.
3. **Transient binding.** `R` → `sdkman-restart-lsp`.
4. **Tests.** Stub `lsp-workspace-restart` via `cl-letf`; assert it
   is called once per applicable workspace. Test the no-`lsp-mode`
   path.

### Exit criteria

- A user can switch the project JDK and pick up the new JDT LS launch
  command from a single transient flow.

---

## Phase 5 — Global SDKMAN mutations with confirmation

The remaining `sdk` subcommands change global SDKMAN state; each must
be gated on `yes-or-no-p` per spec (requirements.md §Transient UI,
§Manual Acceptance Scenarios).

### Tasks

1. **Confirmation helper.** `sdkman--confirm-mutation (verb args)`
   builds the prompt (e.g., "Run `sdk install java 26-tem`? This
   modifies global SDKMAN state.") and returns t/nil from
   `yes-or-no-p`. One place, so all five actions look the same.
2. **`sdkman-sdk-install`.** Prompt for SDK, then candidate
   (free-text; `sdk` validates server-side). Confirm. Async run;
   surface failures.
3. **`sdkman-sdk-uninstall`.** Prompt for SDK; candidate via
   completion from `sdkman-installed-candidates`. Confirm. Async run.
4. **`sdkman-sdk-default`.** Prompt for SDK; candidate via
   completion. Confirm. Async run.
5. **`sdkman-sdk-upgrade`.** Optional SDK (default: all). Confirm.
   Async run.
6. **`sdkman-sdk-selfupdate`.** No args. Confirm. Async run.
7. **Transient bindings.** Section "SDKMAN CLI (global)": `I`
   install, `U` uninstall, `D` default, `g` upgrade, `S` selfupdate.
8. **Tests.** Confirmation gate (`cl-letf` `yes-or-no-p` → nil;
   assert no process spawned). Process-spawn paths under stub bash.
   Failure path (`exit 1`) surfaces in the buffer.
9. **README.** Move "Async `sdk` CLI wrapper" off the roadmap.

### Exit criteria

- All transient actions named in requirements.md §Transient UI are
  bound and confirmation-gated where the spec demands.

---

## Phase 6 — Publish polish

Optional; not in `requirements.md` but the natural completion point
for shipping V1. Either skip, do partially, or revisit after Phase 5
depending on whether MELPA is a goal.

### Tasks

1. **GitHub Actions workflow.** Matrix on Emacs 27.1, 28.2, 29.4, 30
   snapshot. Steps: install Emacs, run quality gate (tests +
   byte-compile + checkdoc + package-lint).
2. **CHANGELOG.md.** Backfill from git log; document the per-phase
   surface changes.
3. **MELPA recipe** (separate `melpa/recipes/sdkman`). Open PR
   upstream only after a tagged 1.0.0 release.
4. **Tag `1.0.0`.** Once the workflow is green and the README
   accurately describes the shipped surface.

### Exit criteria

- Green CI badge on the README.
- A 1.0.0 tag pointing at a commit where every requirements.md §V1
  item is implemented or explicitly out-of-scope.

---

## Verification (each phase)

Run from the repository root before declaring the phase done:

```sh
emacs --batch -Q -L . -l test/sdkman-test.el -f ert-run-tests-batch-and-exit
emacs --batch -Q -L . -f batch-byte-compile sdkman.el && rm sdkman.elc
emacs --batch -Q -L . --eval "(progn (require 'checkdoc) (checkdoc-file \"sdkman.el\"))"
emacs --batch -Q --eval "(progn (require 'package) (package-initialize))" \
  -L . --eval "(require 'package-lint)" \
  -f package-lint-batch-and-exit sdkman.el
```

Manual acceptance after Phase 5 — walk the five scenarios in
[`requirements.md`](requirements.md) §Manual Acceptance Scenarios
end-to-end in a real GUI Emacs.

## Reused helpers

- `sdkman-find-sdkmanrc`, `sdkman-read-sdkmanrc`: status section,
  writer, and switch flow read through these.
- `sdkman-candidate-home`, `sdkman-installed-candidates`,
  `sdkman-current-candidate`: status section, completion sources,
  switch flow.
- `sdkman-apply-buffer-env`, `sdkman-mode`: post-switch reapply,
  `sdkman-show-env`.
- `sdkman-known-env-vars`, `sdkman-warn-on-missing-candidate`
  defcustom patterns: mirror these for new defcustoms.
- `sdkman-test-with-temp-dir`, `sdkman-test-write-file`,
  `sdkman-test-mkdir`, `sdkman-test-create-candidate` in
  `test/sdkman-test.el`: every new test should use these fixtures.

## Out of scope

- Discovery from SDKMAN's remote API (requirements.md §Non-Goals).
- Inferring Java language level from SDKMAN (§Non-Goals).
- Implicit LSP restart on env change (§Non-Goals).
- Adding integrations for other LSP servers (Metals, Kotlin LSP,
  etc.) — not in scope for V1.
