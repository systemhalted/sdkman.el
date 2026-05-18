;;; sdkman.el --- SDKMAN project environments -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Palak Mathur

;; Author: Palak Mathur
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: tools, processes, convenience
;; URL: https://github.com/systemhalted/sdkman.el
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is NOT part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; sdkman.el reads project .sdkmanrc files and applies SDKMAN candidates
;; to Emacs buffer-local environments so subprocesses and language servers
;; see the project's SDK selection without depending on shell auto-env
;; behavior.
;;
;; Usage:
;;
;;   (require 'sdkman)
;;   (global-sdkman-mode 1)
;;
;; In any file-backed buffer whose directory (or an ancestor) contains a
;; .sdkmanrc of the form
;;
;;   java=26-tem
;;   maven=3.9.15
;;
;; `sdkman-mode' resolves the named candidates under SDKMAN_DIR (default
;; ~/.sdkman), prepends each candidate's bin/ to buffer-local `exec-path'
;; and PATH, and sets the corresponding home variables (JAVA_HOME,
;; MAVEN_HOME, GRADLE_HOME by default; extend via `sdkman-known-env-vars').
;;
;; When a `java=' entry is present and `lsp-java' is in use,
;; `sdkman-lsp-java-apply' (invoked automatically by `sdkman-mode') sets
;; buffer-local `lsp-java-java-path' to <java-home>/bin/java and seeds
;; `lsp-java-configuration-runtimes' with a JavaSE-N entry derived from
;; the candidate version, so JDT LS launches with the project JDK.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defgroup sdkman nil
  "SDKMAN project environment integration."
  :group 'tools
  :prefix "sdkman-")

(defcustom sdkman-root nil
  "Root directory of the SDKMAN installation.
When nil, `sdkman--default-root' uses the SDKMAN_DIR environment variable
or falls back to ~/.sdkman."
  :type '(choice (const :tag "Auto-detect" nil)
                 directory)
  :group 'sdkman)

(defcustom sdkman-known-env-vars
  '(("java"   . "JAVA_HOME")
    ("maven"  . "MAVEN_HOME")
    ("gradle" . "GRADLE_HOME"))
  "Alist mapping SDKMAN SDK names to environment variable names.
Each entry causes `sdkman-apply-buffer-env' to set the named variable
to the candidate home directory.  Add further entries for any SDK whose
tools expect a home variable, for example:

  (add-to-list \\='sdkman-known-env-vars \\='(\"ant\" . \"ANT_HOME\"))"
  :type '(alist :key-type string :value-type string)
  :group 'sdkman)

(defcustom sdkman-lsp-java-excluded-directories
  (list
   (expand-file-name "eclipse.jdt.ls/workspace/.cache/" user-emacs-directory)
   (expand-file-name "eclipse.jdt.ls/server/" user-emacs-directory))
  "List of lsp-java generated directories to skip when starting LSP.
Defaults to the eclipse.jdt.ls workspace cache and server directories
under `user-emacs-directory'.  Used by `sdkman-lsp-java-excluded-file-p'."
  :type '(repeat directory)
  :group 'sdkman)

(defcustom sdkman-auto-apply t
  "When non-nil, `global-sdkman-mode' activates `sdkman-mode' automatically.
The mode is activated only in file-backed buffers with a `.sdkmanrc'
ancestor."
  :type 'boolean
  :group 'sdkman)

(defcustom sdkman-warn-on-missing-candidate t
  "When non-nil, warn when a `.sdkmanrc' entry names a missing candidate.
The warning identifies the SDK, the candidate, and the expected path
under the SDKMAN root."
  :type 'boolean
  :group 'sdkman)

(defcustom sdkman-before-apply-hook nil
  "Hook run by `sdkman-mode' before applying the project environment."
  :type 'hook
  :group 'sdkman)

(defcustom sdkman-after-apply-hook nil
  "Hook run by `sdkman-mode' after applying the project environment."
  :type 'hook
  :group 'sdkman)

;; Forward declarations for `lsp-java' variables that `sdkman-lsp-java-apply'
;; sets buffer-locally.  Declaring them keeps the byte compiler quiet when
;; `lsp-java' is not installed.  The package itself does not require
;; `lsp-java'.
(defvar lsp-java-java-path)
(defvar lsp-java-configuration-runtimes)

(defun sdkman--default-root ()
  "Return the effective SDKMAN root directory."
  (file-name-as-directory
   (expand-file-name
    (or sdkman-root
        (getenv "SDKMAN_DIR")
        "~/.sdkman"))))

(defun sdkman--ensure-root (&optional implicit)
  "Return the SDKMAN root, or signal an error when it cannot be found.
When IMPLICIT is non-nil, use `display-warning' instead of `user-error'.
Return nil in the implicit/warning case."
  (let ((root (sdkman--default-root)))
    (cond
     ((file-directory-p root) root)
     (implicit
      (display-warning 'sdkman
                       (format "SDKMAN root not found: %s" root)
                       :warning)
      nil)
     (t
      (user-error "SDKMAN root not found: %s" root)))))

(defun sdkman--init-script (&optional root)
  "Return absolute path to SDKMAN init script under ROOT, or nil when absent.
ROOT defaults to `sdkman--default-root'."
  (let ((script (expand-file-name "bin/sdkman-init.sh"
                                  (or root (sdkman--default-root)))))
    (when (file-readable-p script)
      script)))

(defun sdkman--run-sdk-async (subcommand args &optional buffer sentinel)
  "Run `sdk SUBCOMMAND ARGS' asynchronously.
BUFFER is the output buffer; defaults to a new `*sdkman-output*' buffer.
SENTINEL is called with (process event) on state change.
Signal `user-error' when the SDKMAN init script cannot be found."
  (let ((script (sdkman--init-script)))
    (unless script
     (user-error "SDKMAN init script not found: %s"
              (expand-file-name "bin/sdkman-init.sh" (sdkman--default-root))))
    (let* ((buf (or buffer (get-buffer-create "*sdkman-output*")))
           (cmd (format "source %s && sdk %s %s"
                        script subcommand (string-join args " "))))
      (make-process
       :name     "sdkman"
       :buffer   buf
       :command  (list "bash" "-lc" cmd)
       :sentinel (or sentinel #'ignore)))))

(defun sdkman--path-directory (path)
  "Return the directory to search from for PATH.
If PATH names a directory, return PATH.  Otherwise return PATH's parent
directory."
  (let ((expanded (expand-file-name path)))
    (file-name-as-directory
     (if (file-directory-p expanded)
         expanded
       (or (file-name-directory expanded)
           default-directory)))))

(defun sdkman--setenv-local (variable value)
  "Set environment VARIABLE to VALUE in the current buffer only."
  (setq-local process-environment (copy-sequence process-environment))
  (setenv variable value))


(defun sdkman--prepend-bin-local (bin)
  "Prepend BIN to buffer-local exec-path and PATH."
  (setq-local exec-path
              (sdkman--dedupe-path-list
               (cons bin exec-path)))
  (let* ((current-path (or (getenv "PATH") ""))
         (parts (split-string current-path path-separator t)))
    (sdkman--setenv-local
     "PATH"
     (string-join
      (sdkman--dedupe-path-list (cons bin parts))
      path-separator))))


;;;###autoload
(defun sdkman-find-sdkmanrc (&optional path)
  "Find the nearest .sdkmanrc above PATH.
PATH may be a file or directory.  When PATH is nil, use the variable
`buffer-file-name' or `default-directory'.  Return the absolute .sdkmanrc
path, or nil when no project SDKMAN file exists."
  (let* ((start (or path buffer-file-name default-directory))
         (dir (and start
                   (locate-dominating-file
                    (sdkman--path-directory start)
                    ".sdkmanrc"))))
    (when dir
      (expand-file-name ".sdkmanrc" dir))))

(defun sdkman--parse-line (line line-number)
  "Parse LINE from .sdkmanrc at LINE-NUMBER.
Return nil for comments/blank lines, or a cons cell of (SDK . CANDIDATE).
Signal `user-error' for malformed non-comment lines."
  (let ((trimmed (string-trim line)))
    (cond
     ((or (string-empty-p trimmed)
          (string-prefix-p "#" trimmed))
      nil)
     ((string-match "\\`\\([^[:space:]=#]+\\)[[:space:]]*=[[:space:]]*\\([^[:space:]#]+\\)\\'" trimmed)
      (cons (match-string 1 trimmed)
            (match-string 2 trimmed)))
     (t
      (user-error "Malformed .sdkmanrc line %d: %s" line-number line)))))

;;;###autoload
(defun sdkman-read-sdkmanrc (&optional file)
  "Read SDKMAN entries from FILE.
When FILE is nil, find the nearest .sdkmanrc from the current buffer.
Return an ordered alist of (SDK . CANDIDATE), or nil when no .sdkmanrc can
be found."
  (when-let ((sdkmanrc (or file (sdkman-find-sdkmanrc))))
    (let ((entries nil)
          (line-number 0))
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
      (nreverse entries))))

(defun sdkman-candidate-home (sdk candidate &optional root)
  "Return installed SDKMAN home for SDK CANDIDATE under ROOT.
ROOT defaults to `sdkman--default-root'.  Return nil when the candidate
directory does not exist."
  (let ((home (expand-file-name
               (concat "candidates/" sdk "/" candidate)
               (or root (sdkman--default-root)))))
    (when (file-directory-p home)
      (file-name-as-directory home))))

(defun sdkman-installed-candidates (sdk &optional root)
  "Return installed candidate names for SDK under ROOT.
The SDKMAN `current' symlink is excluded from the result.  Return nil when
the SDK directory does not exist."
  (let ((sdk-dir (expand-file-name
                  (concat "candidates/" sdk)
                  (or root (sdkman--default-root)))))
    (when (file-directory-p sdk-dir)
      (sort
       (cl-loop for path in (directory-files sdk-dir t "\\`[^.]")
                for name = (file-name-nondirectory path)
                when (and (file-directory-p path)
                          (not (string= name "current")))
                collect name)
       #'string<))))

(defun sdkman-current-candidate (sdk &optional root)
  "Return the current candidate name for SDK under ROOT.
Return nil when the SDK has no current symlink."
  (let* ((sdk-dir (expand-file-name
                   (concat "candidates/" sdk)
                   (or root (sdkman--default-root))))
         (current (expand-file-name "current" sdk-dir)))
    (when (file-symlink-p current)
      (file-name-nondirectory
       (directory-file-name
        (expand-file-name (file-symlink-p current) sdk-dir))))))

(defun sdkman--candidate-bin (candidate-home)
  "Return the bin directory for CANDIDATE-HOME, or nil if absent."
  (let ((bin (expand-file-name "bin" candidate-home)))
    (when (file-directory-p bin)
      (file-name-as-directory bin))))

(defun sdkman--dedupe-path-list (paths)
  "Return PATHS without duplicates, preserving first occurrence."
  (let ((seen nil)
        (result nil))
    (dolist (path paths)
      (unless (or (null path)
                  (string-empty-p path)
                  (member path seen))
        (push path seen)
        (push path result)))
    (nreverse result)))

;;;###autoload
(defun sdkman-apply-buffer-env (&optional file root)
  "Apply nearest .sdkmanrc environment for FILE to the current buffer.
ROOT defaults to `sdkman--default-root'.  Return an alist of applied
SDK names to candidate home directories.  When a candidate named in the
project file is not installed, warn (subject to
`sdkman-warn-on-missing-candidate') and skip that SDK."
  (when (sdkman--ensure-root t)
    (let ((entries (sdkman-read-sdkmanrc
                    (or file (sdkman-find-sdkmanrc))))
          (applied nil))
      (dolist (entry entries)
      (let* ((sdk (car entry))
             (candidate (cdr entry))
             (home (sdkman-candidate-home sdk candidate root))
             (bin (and home (sdkman--candidate-bin home))))
        (cond
         (home
          (when bin
            (sdkman--prepend-bin-local bin))
          (when-let ((env-var (cdr (assoc sdk sdkman-known-env-vars))))
            (sdkman--setenv-local env-var home))
          (push (cons sdk home) applied))
         (sdkman-warn-on-missing-candidate
          (display-warning
           'sdkman
           (format "Missing %s candidate %s (expected at %s)"
                   sdk candidate
                   (expand-file-name
                    (concat "candidates/" sdk "/" candidate)
                    (or root (sdkman--default-root))))
           :warning)))))
    (nreverse applied))))

(defun sdkman--java-runtime-name (candidate)
  "Return a JDT LS runtime name for CANDIDATE, or nil when undetermined.
The leading digit group of CANDIDATE names the major Java version, so
`26-tem' yields `JavaSE-26' and `21.0.11-tem' yields `JavaSE-21'."
  (when (and candidate
             (string-match "\\`\\([0-9]+\\)" candidate))
    (format "JavaSE-%s" (match-string 1 candidate))))

;;;###autoload
(defun sdkman-lsp-java-apply (&optional file root)
  "Apply SDKMAN Java settings for FILE to the buffer-local `lsp-java' state.
ROOT defaults to `sdkman--default-root'.  When the nearest `.sdkmanrc'
contains a `java=<candidate>' entry, set buffer-local `lsp-java-java-path'
to `<java-home>/bin/java' and seed `lsp-java-configuration-runtimes' with
a single default runtime entry derived from the candidate.  Existing LSP
workspaces are not restarted; restart explicitly when desired."
  (when-let* ((entries (sdkman-read-sdkmanrc
                        (or file (sdkman-find-sdkmanrc))))
              (candidate (cdr (assoc "java" entries))))
    (let ((home (sdkman-candidate-home "java" candidate root)))
      (cond
       (home
        (let ((java-path (expand-file-name "bin/java" home))
              (runtime-name (sdkman--java-runtime-name candidate)))
          (setq-local lsp-java-java-path java-path)
          (when runtime-name
            (setq-local lsp-java-configuration-runtimes
                        (vector (list :name runtime-name
                                      :path home
                                      :default t))))
          home))
       (sdkman-warn-on-missing-candidate
        (display-warning
         'sdkman
         (format "Missing java candidate %s (expected at %s)"
                 candidate
                 (expand-file-name
                  (concat "candidates/java/" candidate)
                  (or root (sdkman--default-root))))
         :warning)
        nil)))))

(defun sdkman-lsp-java-excluded-file-p (file)
  "Return non-nil when FILE lives inside an `lsp-java' generated directory.
Excluded directories are taken from `sdkman-lsp-java-excluded-directories'.
Comparison uses truenames, so symlinks into the workspace or server
directories are also excluded."
  (when file
    (let ((truename (file-truename file)))
      (catch 'excluded
        (dolist (dir sdkman-lsp-java-excluded-directories)
          (when (and (file-exists-p dir)
                     (file-in-directory-p truename (file-truename dir)))
            (throw 'excluded t)))
        nil))))

(defun sdkman--mode-turn-on ()
  "Enable `sdkman-mode' in file-backed buffers with a project `.sdkmanrc'."
  (when (and sdkman-auto-apply
             buffer-file-name
             (sdkman-find-sdkmanrc))
    (sdkman-mode 1)))

;;;###autoload
(define-minor-mode sdkman-mode
  "Apply the project SDKMAN environment to the current buffer.
Reads the nearest `.sdkmanrc' and applies its SDK candidates buffer-locally
to `process-environment', the variable `exec-path', PATH, and the known
SDK-specific environment variables (see `sdkman-known-env-vars').  When
the project declares a Java candidate, `lsp-java-java-path' and
`lsp-java-configuration-runtimes' are set buffer-locally for JDT LS."
  :init-value nil
  :lighter " SDKMAN"
  :group 'sdkman
  (when sdkman-mode
    (run-hooks 'sdkman-before-apply-hook)
    (sdkman-apply-buffer-env)
    (sdkman-lsp-java-apply)
    (run-hooks 'sdkman-after-apply-hook)))

;;;###autoload
(define-globalized-minor-mode global-sdkman-mode
  sdkman-mode
  sdkman--mode-turn-on
  :group 'sdkman)

(provide 'sdkman)

;;; sdkman.el ends here
