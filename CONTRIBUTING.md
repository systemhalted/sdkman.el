# Contributing to sdkman.el

Thank you for contributing. This document covers development setup, code style, and the PR process.

**New to Emacs Lisp?** Read [docs/elisp-primer.md](docs/elisp-primer.md) first — it teaches the language concepts used in this codebase, anchored to real functions in `sdkman.el`, and includes the full call graph.

---

## Naming Conventions

| Pattern | Meaning |
|---|---|
| `sdkman-foo` | public symbol — stable API, safe to call from outside |
| `sdkman--foo` | private/internal — double dash, may change |
| `sdkman-foo-hook` | hook variable (list of functions) |
| `sdkman-foo-p` | predicate (returns t or nil) |

---

## Development Setup

**Requirements:** Emacs 27.1+. `lsp-java` is optional.

Load the package in your current session:

```emacs-lisp
(load-file "/path/to/sdkman.el/sdkman.el")
```

Or add to your init.el for persistent use:

```emacs-lisp
(use-package sdkman
  :load-path "/path/to/sdkman.el"
  :config (global-sdkman-mode 1))
```

---

## Running Tests

**Interactive:**

```
M-x load-file RET /path/to/sdkman.el/sdkman.el RET
M-x load-file RET /path/to/sdkman.el/test/sdkman-test.el RET
M-x ert RET t RET
```

**Batch (CI-style):**

```bash
emacs --batch \
  -l sdkman.el \
  -l test/sdkman-test.el \
  -f ert-run-tests-batch-and-exit
```

All 24 tests must pass before submitting a PR.

---

## Code Style

**Docstrings:** Every `defun` and `defcustom` requires a docstring. Refer to parameters in UPPERCASE. First line must be a complete sentence:

```emacs-lisp
(defun sdkman-candidate-home (sdk candidate &optional root)
  "Return installed SDKMAN home for SDK CANDIDATE under ROOT.
ROOT defaults to `sdkman--default-root'.  Return nil when the
candidate directory does not exist."
  ...)
```

**Comments:** Only add a comment when the WHY is non-obvious — a hidden constraint, a subtle invariant, a workaround for a specific bug. Do not comment what the code does.

**Autoload:** Public entry points that users call to activate the package get `;;;###autoload`. Private helpers and internal callbacks do not.

**Byte-compile clean:** Run before submitting:

```bash
emacs --batch -f batch-byte-compile sdkman.el
```

**checkdoc clean:**

```
M-x checkdoc RET
```

---

## Submitting a Pull Request

1. Branch from `main`: `git checkout -b my-feature`
2. Write tests for new behaviour in `test/sdkman-test.el`
3. Run the full test suite (batch command above)
4. Run byte-compile and checkdoc — both must be clean
5. Open a PR against `main` with a description of what and why

For larger changes, open an issue first to discuss the approach — especially for anything touching the public API or customization variables.

---

## Roadmap

See [docs/v1-plan.md](docs/v1-plan.md) for the phased implementation plan. The next areas are:

- **Phase 1:** Transient UI skeleton and read-only status view
- **Phase 2:** Read-only sdk CLI passthrough (`sdk list`, `sdk current`)
- **Phase 3:** Project-local SDK switching via UI
- **Phase 4:** Explicit LSP restart command
- **Phase 5:** Global SDKMAN mutations with confirmation
