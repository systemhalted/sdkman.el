# Emacs Lisp Primer: Learning Through sdkman.el

This guide teaches Emacs Lisp using the sdkman.el codebase as the anchor. Every concept is tied to a real function in the package — not toy examples. By the end you will be able to read, understand, and extend every line of `sdkman.el`.

**Prerequisite:** Basic familiarity with at least one programming language. No prior Emacs Lisp experience required.

---

## How to Use This Guide

Evaluate code as you read. Open Emacs and use one of:

| Method | How | Best for |
|---|---|---|
| `*scratch*` buffer | `C-x b *scratch*`, then `C-x C-e` at end of expression | Multi-line experiments |
| `M-:` | Works in any buffer including read-only ones | Quick one-liners |
| `M-x ielm` | Full REPL | Interactive exploration |

Load sdkman.el at the start of each session so all functions are available:

```emacs-lisp
(load-file "/path/to/sdkman.el/sdkman.el")
```

When you get dropped into the `*Backtrace*` debugger, press `q` to exit.

---

## The Call Graph

Read this top-to-bottom. It shows how opening a file triggers everything in sdkman.el:

```
USER-FACING ENTRY POINTS
────────────────────────
global-sdkman-mode              ← you enable this once in your init.el
  └─ sdkman--mode-turn-on       ← Emacs calls this for every file buffer
       ├─ guard: sdkman-auto-apply (defcustom)
       ├─ guard: buffer-file-name (must be a real file, not *scratch*)
       ├─ guard: sdkman-find-sdkmanrc (must find a .sdkmanrc above us)
       └─ sdkman-mode 1          ← activate the local mode

sdkman-mode                     ← the local minor mode
  ├─ run-hooks sdkman-before-apply-hook
  ├─ sdkman-apply-buffer-env    ← main env application
  ├─ sdkman-lsp-java-apply      ← lsp-java wiring
  └─ run-hooks sdkman-after-apply-hook

DISCOVERY LAYER
───────────────
sdkman-find-sdkmanrc
  └─ sdkman--path-directory     ← file path? → parent dir; dir? → itself

sdkman-read-sdkmanrc
  ├─ sdkman-find-sdkmanrc
  └─ sdkman--parse-line         ← called once per line of the file

CANDIDATE RESOLUTION LAYER
──────────────────────────
sdkman-candidate-home           → ~/.sdkman/candidates/java/21.0.11-tem/
  └─ sdkman--default-root       ← sdkman-root → $SDKMAN_DIR → ~/.sdkman

sdkman-installed-candidates     → ("21.0.11-tem" "26-tem")
  └─ sdkman--default-root

sdkman-current-candidate        → "21.0.11-tem"
  └─ sdkman--default-root

sdkman--candidate-bin           → ~/.sdkman/candidates/java/21.0.11-tem/bin/

ENVIRONMENT APPLICATION LAYER
─────────────────────────────
sdkman-apply-buffer-env         ← the workhorse
  ├─ sdkman-read-sdkmanrc
  ├─ (for each sdk entry):
  │    ├─ sdkman-candidate-home
  │    ├─ sdkman--candidate-bin
  │    ├─ sdkman--prepend-bin-local   ← modifies exec-path and PATH
  │    │    ├─ sdkman--dedupe-path-list
  │    │    └─ sdkman--setenv-local
  │    └─ sdkman--setenv-local        ← sets JAVA_HOME, MAVEN_HOME, etc.
  └─ returns alist of applied sdks

LSP-JAVA INTEGRATION LAYER
──────────────────────────
sdkman-lsp-java-apply
  ├─ sdkman-read-sdkmanrc
  ├─ sdkman-candidate-home
  └─ sdkman--java-runtime-name        ← "26-tem" → "JavaSE-26"

sdkman-lsp-java-excluded-file-p       ← standalone predicate
```

**Naming conventions:**

| Pattern | Meaning |
|---|---|
| `sdkman-foo` | public symbol (API, customization) |
| `sdkman--foo` | private/internal (double dash) |
| `sdkman-foo-hook` | a hook (list of functions) |
| `sdkman-foo-p` | predicate (returns t or nil) |

---

## Module 1+2 — S-expressions, defvar, defgroup

### Concept

Every Emacs Lisp expression is a list: `(operator arg1 arg2 ...)`. The first element is always the operator — a function, special form, or macro. Everything else is an argument. This applies to arithmetic, conditionals, and definitions alike:

```emacs-lisp
(+ 1 2)            ; → 3
(if t "yes" "no")  ; → "yes"
(defun foo () 42)  ; defines a function
```

Two symbols are special: `t` (true) and `nil` (false / empty list). They evaluate to themselves — no quoting needed. The `'` (quote) before any other symbol means "treat as literal data, don't evaluate":

```emacs-lisp
t          ; → t      (self-evaluating)
nil        ; → nil    (self-evaluating)
'boolean   ; → boolean (the symbol, not a variable lookup)
boolean    ; → error: void-variable boolean
```

### In sdkman.el (lines 58–64, 121–122)

```emacs-lisp
(require 'cl-lib)    ; load the cl-lib feature
(require 'subr-x)    ; load subr-x feature

(defgroup sdkman nil
  "SDKMAN project environment integration."
  :group 'tools
  :prefix "sdkman-")

(defvar lsp-java-java-path)              ; forward declaration, no value
(defvar lsp-java-configuration-runtimes) ; keeps byte compiler quiet
```

`defvar` with no initial value leaves the variable **void** — not even `nil`. This is used only for forward declarations of variables owned by another package.

`defvar` with an initial value binds the variable:

```emacs-lisp
(defvar sdkman--debug nil "Enable debug output.")
sdkman--debug   ; → nil
```

### Exercise

In `*scratch*`, evaluate these one at a time:

```emacs-lisp
(+ 1 2)
(message "Hello from %s!" "sdkman")
(defvar sdkman--version "0.1.0" "Package version string.")
sdkman--version
```

### Common mistakes

- `nill` instead of `nil` → `void-variable nill`
- `(sdkman--version)` instead of `sdkman--version` → `void-function` — parentheses mean "call as function"
- `(defvar foo)` with no value → variable is void, not nil; use `(defvar foo nil)` to initialize

---

## Module 3 — defcustom

### Concept

`defcustom` is `defvar` with three extra powers: a `:type` spec for validation, a `:group` for the Customize UI, and automatic persistence via `M-x customize-group`.

```emacs-lisp
(defcustom variable-name default-value
  "Docstring."
  :type TYPE-SPEC
  :group 'group-name)
```

Common type specs:

```emacs-lisp
:type 'boolean
:type 'string
:type '(alist :key-type string :value-type string)
:type '(choice (const :tag "Auto-detect" nil) directory)
:type 'hook
```

### In sdkman.el (lines 66–115)

```emacs-lisp
(defcustom sdkman-auto-apply t          ; t needs no quote — self-evaluating
  "When non-nil, activate sdkman-mode automatically."
  :type 'boolean
  :group 'sdkman)

(defcustom sdkman-known-env-vars
  '(("java" . "JAVA_HOME")             ; list needs ' — literal data
    ("maven" . "MAVEN_HOME"))
  "Alist mapping SDK names to env var names."
  :type '(alist :key-type string :value-type string)
  :group 'sdkman)
```

### Exercise

```emacs-lisp
(defcustom sdkman-verbose nil
  "When non-nil, log sdkman operations to *Messages*."
  :type 'boolean
  :group 'sdkman)

sdkman-verbose   ; → nil
```

### Common mistakes

- Forgetting `'` on a list default → Emacs tries to call the first element as a function
- `t` and `nil` never need `'` — `'t` works but is redundant

---

## Module 4 — defun and &optional

### Concept

`defun` defines a function. The last expression in the body is the return value — there is no `return` keyword. Parameters after `&optional` default to `nil` if not provided:

```emacs-lisp
(defun function-name (required &optional optional-param)
  "Docstring."
  body...)
```

The `(or param fallback)` idiom provides defaults for optional parameters: `or` returns the first non-nil value.

### In sdkman.el (lines 124–130, 215–223)

```emacs-lisp
(defun sdkman--default-root ()
  "Return the effective SDKMAN root directory."
  (file-name-as-directory
   (expand-file-name
    (or sdkman-root          ; custom var first
        (getenv "SDKMAN_DIR") ; then env var
        "~/.sdkman"))))       ; then hardcoded default

(defun sdkman-candidate-home (sdk candidate &optional root)
  "Return installed SDKMAN home for SDK CANDIDATE under ROOT."
  (let ((home (expand-file-name
               (concat "candidates/" sdk "/" candidate)
               (or root (sdkman--default-root)))))
    (when (file-directory-p home)
      (file-name-as-directory home))))
```

### Exercise

```emacs-lisp
(defun sdkman--sdk-dir (sdk &optional root)
  "Return the directory for SDK under ROOT."
  (expand-file-name (concat "candidates/" sdk)
                    (or root (sdkman--default-root))))

(sdkman--sdk-dir "java")
(sdkman--sdk-dir "java" "/tmp/fake-sdkman")
```

### Common mistakes

- Calling a function before evaluating its `defun` → `void-function`
- `or` returns the actual value, not `t`/`nil` — use it directly as a return value

---

## Module 5+6 — let/let* and when/cond

### Concept

`let` binds local variables. `let*` allows each binding to reference previous ones. The body always has access to all bindings — the `let`/`let*` distinction only applies within the binding list itself:

```emacs-lisp
(let ((x 1)
      (y 2))        ; x and y computed independently
  (+ x y))         ; body sees both

(let* ((x 1)
       (y (* x 2))) ; y depends on x — needs let*
  (+ x y))
```

`when` is `if` with no else branch. `cond` is multi-branch. `or`/`and` return actual values, not booleans:

```emacs-lisp
(or nil "hello" t)    ; → "hello"  (first non-nil)
(and 1 2 3)           ; → 3        (last non-nil if all truthy)
(when condition body) ; → body result or nil
(unless condition body) ; → body result or nil (inverted)
```

### In sdkman.el (lines 132–141, 182–190)

```emacs-lisp
(defun sdkman--path-directory (path)
  (let ((expanded (expand-file-name path)))   ; one binding
    (file-name-as-directory
     (if (file-directory-p expanded)
         expanded
       (or (file-name-directory expanded)
           default-directory)))))

(defun sdkman--parse-line (line line-number)
  (let ((trimmed (string-trim line)))
    (cond
     ((or (string-empty-p trimmed)
          (string-prefix-p "#" trimmed))    ; blank or comment
      nil)
     ((string-match "\\`\\([^[:space:]=#]+\\)..." trimmed)  ; key=value
      (cons (match-string 1 trimmed)
            (match-string 2 trimmed)))
     (t                                     ; default: error
      (user-error "Malformed .sdkmanrc line %d: %s"
                  line-number line)))))
```

### Exercise

```emacs-lisp
(defun sdkman--root-status ()
  "Return a string describing the SDKMAN root status."
  (let ((root (sdkman--default-root)))
    (if (file-directory-p root)
        (format "SDKMAN found at %s" root)
      (format "SDKMAN not found (expected at %s)" root))))

(sdkman--root-status)
```

### Common mistakes

- Using `let` when bindings depend on each other → `void-variable` for the referenced binding
- `progn` vs `when`: `progn` always runs all expressions; `when` short-circuits on nil
- `unless (or A B)` = `when (and (not A) (not B))` — De Morgan's law

---

## Module 7+8 — when-let and Alists

### Concept

An alist is a list of cons cells: `'((key . value) ...)`. `assoc` finds an entry by key and returns the whole cons cell. `car`/`cdr` extract halves (historical names: Contents of Address Register / Contents of Decrement Register):

```emacs-lisp
(assoc "java" sdkman-known-env-vars)   ; → ("java" . "JAVA_HOME")
(car '("java" . "JAVA_HOME"))          ; → "java"
(cdr '("java" . "JAVA_HOME"))          ; → "JAVA_HOME"
```

`when-let` combines a binding with a nil check — if the binding is nil, the body is skipped:

```emacs-lisp
(when-let ((value (some-function)))
  (use value))   ; only runs if some-function returned non-nil

(when-let* ((a (f1))   ; stops at first nil
            (b (f2 a)))
  (use a b))
```

Alists vs hash tables: alists are O(n) lookup but have literal syntax and preserve order. Use alists for small, config-like data (sdkman.el has at most 10 SDK entries); use hash tables for large datasets.

### In sdkman.el (lines 74–81, 291, 324)

```emacs-lisp
(defcustom sdkman-known-env-vars
  '(("java" . "JAVA_HOME")
    ("maven" . "MAVEN_HOME")
    ("gradle" . "GRADLE_HOME")
    ("kotlin" . "KOTLIN_HOME"))
  ...)

; In sdkman-apply-buffer-env (line 291):
(when-let ((env-var (cdr (assoc sdk sdkman-known-env-vars))))
  (sdkman--setenv-local env-var home))

; In sdkman-lsp-java-apply (line 324):
(when-let* ((entries (sdkman-read-sdkmanrc ...))
            (candidate (cdr (assoc "java" entries))))
  ...)
```

### Exercise

```emacs-lisp
(defun sdkman--env-var-for (sdk)
  "Return env var string for SDK, or nil if unknown."
  (when-let ((env-var (cdr (assoc sdk sdkman-known-env-vars))))
    (format "%s is controlled by %s" sdk env-var)))

(sdkman--env-var-for "java")   ; → "java is controlled by JAVA_HOME"
(sdkman--env-var-for "scala")  ; → nil
```

---

## Module 9+10 — push/nreverse and dolist

### Concept

Building a list by appending is O(n²). The idiomatic alternative: prepend with `push` (O(1)), then reverse once at the end:

```emacs-lisp
(let ((result nil))
  (push "java" result)    ; → ("java")
  (push "maven" result)   ; → ("maven" "java")
  (nreverse result))      ; → ("java" "maven")
```

`nreverse` is **destructive** — it rewires cons cells in place. Always capture its return value: `(setq x (nreverse x))`. After `nreverse`, the original variable points to what is now the tail.

`dolist` iterates a list for side effects. It always returns `nil` — you cannot capture a value from the body:

```emacs-lisp
(dolist (item list)
  body...)   ; returns nil, body values discarded
```

### In sdkman.el (lines 199–213, 259–269)

```emacs-lisp
; sdkman-read-sdkmanrc — build entries list:
(let ((entries nil))
  ...
  (while ...
    (when entry
      (push entry entries)))   ; prepend each entry
  (nreverse entries))          ; restore file order

; sdkman--dedupe-path-list:
(dolist (path paths)
  (unless (member path seen)
    (push path seen)
    (push path result)))
(nreverse result)
```

### Exercise

```emacs-lisp
(defun sdkman--sdk-names (entries)
  "Return a list of sdk names from ENTRIES alist."
  (let ((names nil))
    (dolist (entry entries)
      (push (car entry) names))
    (nreverse names)))   ; ← inside let, after dolist

(sdkman--sdk-names sdkman-known-env-vars)
; → ("java" "maven" "gradle" "kotlin")
```

### Common mistakes

- `nreverse` outside `let` → the variable `names` is out of scope
- `(setq result (dolist ...))` → dolist returns nil, not your collected values
- Not capturing `nreverse` return value → original variable becomes the one-element tail

---

## Module 11 — String Operations

### Concept

Core string functions:

```emacs-lisp
(string-empty-p "")                    ; → t
(string-prefix-p "#" "# comment")     ; → t
(string-trim "  java=21  ")           ; → "java=21"
(format "candidates/%s/%s" "java" "21") ; → "candidates/java/21"
(split-string "/usr/bin:/usr/local" ":" t)  ; → ("/usr/bin" "/usr/local")
(string-join '("/usr/bin" "/usr/local") ":") ; → "/usr/bin:/usr/local"
```

The `t` third argument to `split-string` drops zero-length strings only — not whitespace-only strings like `" "`.

`string-match` and `match-string` are always used together. `string-match` runs the regex and stores match positions globally. `match-string` reads from that global state immediately after:

```emacs-lisp
(when (string-match "\\`\\([0-9]+\\)" "21.0.11-tem")
  (match-string 1 "21.0.11-tem"))   ; → "21"
```

Never separate `string-match` and `match-string` across evaluations — any intervening operation may overwrite the match data.

Regex special characters need double-escaping: `\\(` = capture group, `\\`` = start of string, `\\'` = end of string.

### In sdkman.el (lines 177–190, 308–314)

```emacs-lisp
; sdkman--java-runtime-name:
(when (string-match "\\`\\([0-9]+\\)" candidate)
  (format "JavaSE-%s" (match-string 1 candidate)))
; "21.0.11-tem" → "JavaSE-21"

; sdkman--parse-line regex:
(string-match
 "\\`\\([^[:space:]=#]+\\)[[:space:]]*=[[:space:]]*\\([^[:space:]#]+\\)\\'"
 trimmed)
; group 1: key, group 2: value
```

### Exercise

```emacs-lisp
(defun sdkman--candidate-major-version (candidate)
  "Return the major version string from CANDIDATE, or nil."
  (when (string-match "\\`\\([0-9]+\\)" candidate)
    (match-string 1 candidate)))

(sdkman--candidate-major-version "21.0.11-tem")  ; → "21"
(sdkman--candidate-major-version "26-tem")        ; → "26"
(sdkman--candidate-major-version "no-version")    ; → nil
```

### Common mistakes

- Calling `match-string` as a separate evaluation after `string-match` → stale match data, wrong results
- `string-match` returning nil does NOT clear match data — `match-string` reads garbage from the previous match
- `" "` is not empty — `string-empty-p` returns nil for whitespace-only strings

---

## Module 12 — File System Operations

### Concept

```emacs-lisp
(expand-file-name "candidates/java" "~/.sdkman/")
; → "/Users/you/.sdkman/candidates/java"

(file-directory-p path)           ; exists as directory?
(file-exists-p path)              ; exists at all?
(file-symlink-p path)             ; symlink? returns target or nil
(file-truename path)              ; resolve all symlinks → real path

(file-name-directory "/a/b/c")    ; → "/a/b/"   (strips last component)
(file-name-nondirectory "/a/b/c") ; → "c"
(file-name-as-directory "/a/b")   ; → "/a/b/"   (adds trailing /)
(directory-file-name "/a/b/")     ; → "/a/b"    (removes trailing /)

(locate-dominating-file "/a/b/c/" ".sdkmanrc")
; walks up: /a/b/c/, /a/b/, /a/, / — returns dir containing .sdkmanrc or nil

(file-in-directory-p file dir)    ; is file inside dir? (needs absolute paths)
```

A trailing `/` changes string manipulation: `(file-name-directory "/a/b/")` returns `"/a/b/"` — nothing stripped, because the last component after `/` is empty.

`file-in-directory-p` requires absolute paths for both arguments — bare filenames always return nil.

### In sdkman.el (lines 124–130, 164–175)

```emacs-lisp
(defun sdkman--default-root ()
  (file-name-as-directory
   (expand-file-name
    (or sdkman-root (getenv "SDKMAN_DIR") "~/.sdkman"))))

(defun sdkman-find-sdkmanrc (&optional path)
  (let* ((start (or path buffer-file-name default-directory))
         (dir (and start
                   (locate-dominating-file
                    (sdkman--path-directory start)
                    ".sdkmanrc"))))
    (when dir
      (expand-file-name ".sdkmanrc" dir))))
```

### Exercise

```emacs-lisp
(file-directory-p "~/.sdkman")
(directory-files (expand-file-name "candidates" (sdkman--default-root))
                 nil "\\`[^.]")
(locate-dominating-file default-directory ".sdkmanrc")
```

---

## Module 13+14 — setq-local and Buffer-Local Environment

### Concept

`setq-local` creates a buffer-local binding — the variable has a different value in each buffer. Other buffers see the global value; this buffer sees its own.

`process-environment` and `exec-path` control what subprocesses see. Making them buffer-local lets each buffer carry its own SDK environment:

```emacs-lisp
(setq-local process-environment (copy-sequence process-environment))
; ← copy FIRST, then make local — otherwise all buffers share the same list object

(setenv "JAVA_HOME" "/path/to/java")   ; modifies the buffer-local copy
(getenv "JAVA_HOME")                   ; reads from buffer-local copy
```

`getenv`/`setenv` take **string** arguments — the variable name in double quotes:

```emacs-lisp
(getenv "PATH")     ; ← correct
(getenv PATH)       ; ← error: PATH treated as a variable name
```

To evaluate an expression in a specific buffer from a read-only buffer, use `M-:` (eval-expression) — it runs in the context of whatever buffer was current when invoked.

### In sdkman.el (lines 143–160)

```emacs-lisp
(defun sdkman--setenv-local (variable value)
  (setq-local process-environment (copy-sequence process-environment))
  (setenv variable value))

(defun sdkman--prepend-bin-local (bin)
  (setq-local exec-path
              (sdkman--dedupe-path-list (cons bin exec-path)))
  (let* ((current-path (or (getenv "PATH") ""))
         (parts (split-string current-path path-separator t)))
    (sdkman--setenv-local
     "PATH"
     (string-join
      (sdkman--dedupe-path-list (cons bin parts))
      path-separator))))
```

Both `exec-path` and `PATH` must be updated together — `exec-path` is Emacs's internal lookup list; `PATH` is what spawned subprocesses see.

### Exercise

```emacs-lisp
; In *scratch*:
(setq-local process-environment (copy-sequence process-environment))
(setenv "SDKMAN_TEST" "hello")
(getenv "SDKMAN_TEST")   ; → "hello"

; Switch to *Messages*, press M-: and evaluate:
; (getenv "SDKMAN_TEST") → nil  (not set in this buffer)
```

---

## Module 15 — cl-loop

### Concept

`cl-loop` is a Common Lisp macro for expressive iteration. It reads like English and handles `push`/`nreverse` automatically via `collect`:

```emacs-lisp
(cl-loop for x in '(1 2 3 4 5)
         when (> x 2)
         collect x)
; → (3 4 5)

(cl-loop for x in list
         for y = (transform x)   ; parallel binding
         when (condition y)
         collect y)
```

`return` exits early and produces a value — equivalent to `catch`/`throw` for simple cases:

```emacs-lisp
(cl-loop for x in list
         when (= x 3)
         return x)
; → 3, stops at x=3
```

### In sdkman.el (lines 234–238)

```emacs-lisp
(cl-loop for path in (directory-files sdk-dir t "\\`[^.]")
         for name = (file-name-nondirectory path)
         when (and (file-directory-p path)
                   (not (string= name "current")))
         collect name)
```

Two parallel `for` clauses: `name` is derived from `path` each iteration. `when` filters out files and the `current` symlink. `collect` builds the result in correct order.

### Exercise

Write the same logic with `dolist` first, then compare:

```emacs-lisp
; dolist version:
(let ((result nil)
      (sdk-dir (expand-file-name "candidates/java" (sdkman--default-root))))
  (dolist (path (directory-files sdk-dir t "\\`[^.]"))
    (let ((name (file-name-nondirectory path)))
      (when (and (file-directory-p path)
                 (not (string= name "current")))
        (push name result))))
  (nreverse result))

; cl-loop version:
(let ((sdk-dir (expand-file-name "candidates/java" (sdkman--default-root))))
  (cl-loop for path in (directory-files sdk-dir t "\\`[^.]")
           for name = (file-name-nondirectory path)
           when (and (file-directory-p path)
                     (not (string= name "current")))
           collect name))
```

---

## Module 16 — catch/throw

### Concept

`dolist` has no `break`. `catch`/`throw` provides early exit from any depth of nesting:

```emacs-lisp
(catch 'tag
  body...)          ; returns body value, or value from throw

(throw 'tag value)  ; jumps to catch 'tag immediately
```

If `throw` never fires, `catch` returns the value of its last body expression.

```emacs-lisp
(catch 'found
  (dolist (x '(1 2 3 4 5))
    (when (= x 3)
      (throw 'found x)))
  nil)
; → 3  (stops at 3, never visits 4 or 5)
```

Alternatives for simple cases:
- `cl-loop` with `return` — cleaner for list iteration
- `cl-find-if` — for finding the first matching element

### In sdkman.el (lines 350–362)

```emacs-lisp
(defun sdkman-lsp-java-excluded-file-p (file)
  (when file
    (let ((truename (file-truename file)))
      (catch 'excluded
        (dolist (dir sdkman-lsp-java-excluded-directories)
          (when (and (file-exists-p dir)
                     (file-in-directory-p truename (file-truename dir)))
            (throw 'excluded t)))
        nil))))
```

`catch`/`throw` is used here because this is a predicate — it needs one `t` or `nil`, not a list. The moment one excluded directory matches, there's no reason to check the rest.

### Exercise

```emacs-lisp
(defun sdkman--first-available-sdk (sdks)
  "Return the first SDK name from SDKS that has candidates installed."
  (catch 'found
    (dolist (sdk sdks)
      (when (sdkman-installed-candidates sdk)
        (throw 'found sdk)))
    nil))

(sdkman--first-available-sdk '("scala" "java" "maven"))
```

---

## Module 17 — with-temp-buffer

### Concept

Reading a file in Emacs means loading it into a buffer and navigating it as text. `with-temp-buffer` creates a disposable buffer that is killed when the body exits:

```emacs-lisp
(with-temp-buffer
  (insert-file-contents "/path/to/file")
  (goto-char (point-min))          ; start at beginning
  (while (not (eobp))              ; until end of buffer
    (let ((line (buffer-substring-no-properties
                 (line-beginning-position)
                 (line-end-position))))
      (do-something-with line))
    (forward-line 1)))
```

Key functions:

| Function | Purpose |
|---|---|
| `(point-min)` / `(point-max)` | start / end position of buffer |
| `(eobp)` | at end of buffer? |
| `(forward-line 1)` | advance one line |
| `(line-beginning-position)` | position of line start |
| `(line-end-position)` | position of line end |
| `(buffer-substring-no-properties start end)` | extract text, strip formatting |

### In sdkman.el (lines 198–213)

```emacs-lisp
(with-temp-buffer
  (insert-file-contents sdkmanrc)
  (goto-char (point-min))
  (while (not (eobp))
    (setq line-number (1+ line-number))
    (let* ((line (buffer-substring-no-properties
                  (line-beginning-position)
                  (line-end-position)))
           (entry (sdkman--parse-line line line-number)))
      (when entry
        (push entry entries)))
    (forward-line 1)))
```

### Exercise

```emacs-lisp
(defun sdkman--count-lines (file)
  "Return the number of lines in FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let ((count 0))
      (while (not (eobp))
        (setq count (1+ count))
        (forward-line 1))
      count)))

(sdkman--count-lines
 "/path/to/sdkman.el/sdkman.el")   ; → 397
```

---

## Module 18+19 — define-minor-mode, define-globalized-minor-mode, and Hooks

### Concept

`define-minor-mode` generates four things from one call:

1. A **variable** `sdkman-mode` — `t`/`nil`, buffer-local
2. A **command** `sdkman-mode` — `(sdkman-mode 1)` enable, `(sdkman-mode -1)` disable, `(sdkman-mode)` toggle
3. A **hook** `sdkman-mode-hook` — runs after each toggle
4. A **mode-line lighter** — appears when active

```emacs-lisp
(define-minor-mode my-mode
  "Docstring."
  :init-value nil
  :lighter " MY"
  :group 'my-group
  (when my-mode       ; guard: runs only on enable
    (do-setup)))
```

A **hook** is a variable holding a list of functions. `run-hooks` calls each in order. Users extend behavior with `add-hook`:

```emacs-lisp
(add-hook 'sdkman-after-apply-hook
          (lambda () (message "env applied in %s" (buffer-name))))
```

`define-globalized-minor-mode` watches every buffer and calls a turn-on function. The turn-on function guards against inappropriate buffers:

```emacs-lisp
(defun sdkman--mode-turn-on ()
  (when (and sdkman-auto-apply
             buffer-file-name
             (sdkman-find-sdkmanrc))
    (sdkman-mode 1)))

(define-globalized-minor-mode global-sdkman-mode
  sdkman-mode
  sdkman--mode-turn-on
  :group 'sdkman)
```

### In sdkman.el (lines 372–392)

```emacs-lisp
(define-minor-mode sdkman-mode
  "Apply the project SDKMAN environment to the current buffer."
  :init-value nil
  :lighter " SDKMAN"
  :group 'sdkman
  (when sdkman-mode
    (run-hooks 'sdkman-before-apply-hook)
    (sdkman-apply-buffer-env)
    (sdkman-lsp-java-apply)
    (run-hooks 'sdkman-after-apply-hook)))
```

### Exercise

```emacs-lisp
(define-minor-mode sdkman-debug-mode
  "Log sdkman operations to *Messages*."
  :init-value nil
  :lighter " SDKMAN-DBG"
  :group 'sdkman
  (if sdkman-debug-mode
      (message "sdkman-debug-mode ON in %s" (buffer-name))
    (message "sdkman-debug-mode OFF in %s" (buffer-name))))

; Toggle with M-x sdkman-debug-mode
; Check the generated variable:
sdkman-debug-mode       ; → nil
(sdkman-debug-mode 1)
sdkman-debug-mode       ; → t
```

---

## Module 20 — provide and autoload

### Concept

`provide` registers a feature name. `require` loads the file only if the feature isn't registered yet — preventing double-loading:

```emacs-lisp
(provide 'sdkman)       ; last line of sdkman.el
(require 'sdkman)       ; in init.el — loads file if not already loaded
(featurep 'sdkman)      ; → t if loaded
```

The `;;;###autoload` cookie marks entry points for lazy loading. Package managers generate stub functions that load the real file on first call — without it, the entire file must be loaded at Emacs startup:

```emacs-lisp
;;;###autoload
(define-globalized-minor-mode global-sdkman-mode ...)
```

**What to autoload:** functions and modes a user calls **to activate** the package. Private helpers and callbacks (like `sdkman-lsp-java-excluded-file-p`) do not need autoloading — by the time lsp-java is running and could call them, sdkman.el is already loaded.

### In sdkman.el

Autoloaded symbols: `sdkman-find-sdkmanrc`, `sdkman-read-sdkmanrc`, `sdkman-apply-buffer-env`, `sdkman-lsp-java-apply`, `sdkman-mode`, `global-sdkman-mode`.

Not autoloaded: `sdkman--default-root`, `sdkman--parse-line`, `sdkman--prepend-bin-local`, `sdkman-lsp-java-excluded-file-p`, and all other private helpers.

### Exercise

```emacs-lisp
(featurep 'sdkman)    ; → t  (if loaded this session)
(featurep 'cl-lib)    ; → t  (always — sdkman requires it)
(length features)     ; how many features are loaded?
```

---

## What You Now Know

Every concept above is present in code we've written or read:

```
S-expressions       → every line of the file
defvar/defgroup     → lines 61–64, 121–122
defcustom           → lines 66–115
defun/&optional     → lines 124–369
let/let*            → lines 132, 149, 219, 244...
when/cond           → lines 182, 253, 287...
when-let/when-let*  → lines 170, 198, 324
alists/car/cdr      → lines 74–81, 186–189, 291
push/nreverse       → lines 199–213, 259–269
dolist              → lines 263, 282
string operations   → lines 177–190, 308–314
file system ops     → lines 124–257
setq-local/getenv   → lines 143–160
cl-loop             → lines 234–238
catch/throw         → lines 357–362
with-temp-buffer    → lines 201–212
define-minor-mode   → lines 372–386
define-globalized   → lines 389–392
provide/autoload    → line 394, cookies throughout
```

The next step is the V1 roadmap in `docs/v1-plan.md` — transient UI, sdk CLI wrapper, and explicit LSP restart.
