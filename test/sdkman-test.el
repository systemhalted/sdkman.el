;;; sdkman-test.el --- Tests for sdkman.el -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'sdkman)

(defmacro sdkman-test-with-temp-dir (var &rest body)
  "Bind VAR to a temporary directory while evaluating BODY."
  (declare (indent 1))
  `(let ((,var (make-temp-file "sdkman-test-" t)))
     (unwind-protect
         (progn ,@body)
       (delete-directory ,var t))))

(defun sdkman-test-write-file (file contents)
  "Write CONTENTS to FILE, creating parent directories."
  (make-directory (file-name-directory file) t)
  (with-temp-file file
    (insert contents)))

(defun sdkman-test-mkdir (dir)
  "Create DIR and parents, then return DIR."
  (make-directory dir t)
  dir)

(ert-deftest sdkman-read-sdkmanrc-ignores-comments-and-blanks ()
  (sdkman-test-with-temp-dir root
			     (let ((file (expand-file-name ".sdkmanrc" root)))
			       (sdkman-test-write-file
				file
				"# Enable auto-env through SDKMAN

java=26-tem

# Another comment
maven=3.9.15
")
			       (should (equal (sdkman-read-sdkmanrc file)
					      '(("java" . "26-tem")
						("maven" . "3.9.15")))))))


(ert-deftest sdkman-read-sdkmanrc-handles-surrounding-whitespace ()
  (sdkman-test-with-temp-dir root
			     (let ((file (expand-file-name ".sdkmanrc" root)))
			       (sdkman-test-write-file
				file
				"# Enable auto-env through SDKMAN
 java = 26-tem
maven=3.9.15
gradle= 9.5.0
")
			       (should (equal (sdkman-read-sdkmanrc file)
					      '(("java" . "26-tem")
						("maven" . "3.9.15")
						("gradle" . "9.5.0")))))))

(ert-deftest sdkman-read-sdkmanrc-preserves-entry-order ()
  (sdkman-test-with-temp-dir root
			     (let ((file (expand-file-name ".sdkmanrc" root)))
			       (sdkman-test-write-file
				file
				"gradle=9.5.0
java=21.0.11-tem
maven=3.9.15
")
			       (should (equal (mapcar #'car (sdkman-read-sdkmanrc file))
					      '("gradle" "java" "maven"))))))

(ert-deftest sdkman-read-sdkmanrc-reports-malformed-line-number ()
  (sdkman-test-with-temp-dir root
			     (let ((file (expand-file-name ".sdkmanrc" root)))
			       (sdkman-test-write-file
				file
				"java=26-tem
this is not valid
maven=3.9.15
")
			       (should-error (sdkman-read-sdkmanrc file)
					     :type 'user-error)
			       (condition-case err
				   (sdkman-read-sdkmanrc file)
				 (user-error
				  (should (string-match-p "line 2" (cadr err))))))))

(ert-deftest sdkman-find-sdkmanrc-finds-nearest-project-file ()
  (sdkman-test-with-temp-dir root
			     (let* ((project (expand-file-name "project" root))
				    (nested (expand-file-name "src/main/java/App.java" project))
				    (sdkmanrc (expand-file-name ".sdkmanrc" project)))
			       (sdkman-test-write-file sdkmanrc "java=26-tem\n")
			       (sdkman-test-write-file nested "class App {}\n")
			       (should (equal (sdkman-find-sdkmanrc nested) sdkmanrc)))))

(ert-deftest sdkman-find-sdkmanrc-returns-nil-when-missing ()
  (sdkman-test-with-temp-dir root
			     (let ((file (expand-file-name "project/src/App.java" root)))
			       (sdkman-test-write-file file "class App {}\n")
			       (should-not (sdkman-find-sdkmanrc file)))))

(ert-deftest sdkman-candidate-home-resolves-installed-candidate ()
  (sdkman-test-with-temp-dir root
			     (let ((java-home (sdkman-test-mkdir
					       (expand-file-name "candidates/java/26-tem" root))))
			       (should (equal (sdkman-candidate-home "java" "26-tem" root)
					      (file-name-as-directory java-home))))))

(ert-deftest sdkman-candidate-home-returns-nil-for-missing-candidate ()
  (sdkman-test-with-temp-dir root
			     (should-not (sdkman-candidate-home "java" "missing" root))))

(ert-deftest sdkman-installed-candidates-excludes-current ()
  (sdkman-test-with-temp-dir root
			     (let ((java-dir (expand-file-name "candidates/java" root)))
			       (sdkman-test-mkdir (expand-file-name "26-tem" java-dir))
			       (sdkman-test-mkdir (expand-file-name "21.0.11-tem" java-dir))
			       (make-symbolic-link "26-tem" (expand-file-name "current" java-dir))
			       (should (equal (sdkman-installed-candidates "java" root)
					      '("21.0.11-tem" "26-tem"))))))

(ert-deftest sdkman-installed-candidates-returns-nil-for-missing-sdk ()
  (sdkman-test-with-temp-dir root
			     (should-not (sdkman-installed-candidates "java" root))))

(ert-deftest sdkman-current-candidate-resolves-current-symlink ()
  (sdkman-test-with-temp-dir root
			     (let ((java-dir (expand-file-name "candidates/java" root)))
			       (sdkman-test-mkdir (expand-file-name "26-tem" java-dir))
			       (make-symbolic-link "26-tem" (expand-file-name "current" java-dir))
			       (should (equal (sdkman-current-candidate "java" root)
					      "26-tem")))))

(ert-deftest sdkman-current-candidate-returns-nil-when-missing ()
  (sdkman-test-with-temp-dir root
			     (sdkman-test-mkdir (expand-file-name "candidates/java/26-tem" root))
			     (should-not (sdkman-current-candidate "java" root))))


(defun sdkman-test-create-candidate (root sdk candidate)
  "Create fake SDK candidate under ROOT and return its home."
  (let ((home (expand-file-name
               (format "candidates/%s/%s" sdk candidate)
               root)))
    (sdkman-test-mkdir (expand-file-name "bin" home))
    home))


(ert-deftest sdkman-apply-buffer-env-sets-java-home ()
  (sdkman-test-with-temp-dir root
			     (let* ((project (expand-file-name "project" root))
				    (file (expand-file-name "App.java" project))
				    (java-home (sdkman-test-create-candidate root "java" "26-tem")))
			       (sdkman-test-write-file (expand-file-name ".sdkmanrc" project)
						       "java=26-tem\n")
			       (sdkman-test-write-file file "class App {}\n")
			       (let ((process-environment process-environment)
				     (exec-path exec-path)
				     (default-directory project))
				 (with-temp-buffer
				   (setq buffer-file-name file)
				   (sdkman-apply-buffer-env nil root)
				   (should (equal (getenv "JAVA_HOME")
						  (file-name-as-directory java-home))))))))

(ert-deftest sdkman-apply-buffer-env-prepends-path-and-exec-path ()
  (sdkman-test-with-temp-dir root
			     (let* ((project (expand-file-name "project" root))
				    (file (expand-file-name "App.java" project))
				    (java-home (sdkman-test-create-candidate root "java" "26-tem"))
				    (java-bin (file-name-as-directory
					       (expand-file-name "bin" java-home))))
			       (sdkman-test-write-file (expand-file-name ".sdkmanrc" project)
						       "java=26-tem\n")
			       (sdkman-test-write-file file "class App {}\n")
			       (let ((process-environment (list "PATH=/usr/bin"))
				     (exec-path '("/usr/bin"))
				     (default-directory project))
				 (with-temp-buffer
				   (setq buffer-file-name file)
				   (sdkman-apply-buffer-env nil root)
				   (should (equal (car exec-path) java-bin))
				   (should (string-prefix-p java-bin (getenv "PATH"))))))))

(ert-deftest sdkman-apply-buffer-env-applies-multiple-sdks-in-sdkmanrc-order ()
  (sdkman-test-with-temp-dir root
			     (let* ((project (expand-file-name "project" root))
				    (file (expand-file-name "App.java" project))
				    (java-home (sdkman-test-create-candidate root "java" "26-tem"))
				    (maven-home (sdkman-test-create-candidate root "maven" "3.9.15")))
			       (sdkman-test-write-file (expand-file-name ".sdkmanrc" project)
						       "java=26-tem\nmaven=3.9.15\n")
			       (sdkman-test-write-file file "class App {}\n")
			       (let ((process-environment (list "PATH=/usr/bin"))
				     (exec-path '("/usr/bin"))
				     (default-directory project))
				 (with-temp-buffer
				   (setq buffer-file-name file)
				   (should (equal (sdkman-apply-buffer-env nil root)
						  `(("java" . ,(file-name-as-directory java-home))
						    ("maven" . ,(file-name-as-directory maven-home)))))
				   (should (equal (getenv "JAVA_HOME")
						  (file-name-as-directory java-home)))
				   (should (equal (getenv "MAVEN_HOME")
						  (file-name-as-directory maven-home))))))))

(ert-deftest sdkman-apply-buffer-env-does-not-duplicate-paths-when-reapplied ()
  (sdkman-test-with-temp-dir root
			     (let* ((project (expand-file-name "project" root))
				    (file (expand-file-name "App.java" project))
				    (java-home (sdkman-test-create-candidate root "java" "26-tem"))
				    (java-bin (file-name-as-directory
					       (expand-file-name "bin" java-home))))
			       (sdkman-test-write-file (expand-file-name ".sdkmanrc" project)
						       "java=26-tem\n")
			       (sdkman-test-write-file file "class App {}\n")
			       (let ((process-environment (list "PATH=/usr/bin"))
				     (exec-path '("/usr/bin"))
				     (default-directory project))
				 (with-temp-buffer
				   (setq buffer-file-name file)
				   (sdkman-apply-buffer-env nil root)
				   (sdkman-apply-buffer-env nil root)
				   (should (= 1 (cl-count java-bin exec-path :test #'string=)))
				   (should (= 1 (cl-count java-bin
							  (split-string (getenv "PATH") path-separator t)
							  :test #'string=))))))))

(ert-deftest sdkman-apply-buffer-env-skips-missing-candidate ()
  (sdkman-test-with-temp-dir root
			     (let* ((project (expand-file-name "project" root))
				    (file (expand-file-name "App.java" project)))
			       (sdkman-test-write-file (expand-file-name ".sdkmanrc" project)
						       "java=missing\n")
			       (sdkman-test-write-file file "class App {}\n")
			       (let ((process-environment (list "PATH=/usr/bin"))
				     (exec-path '("/usr/bin"))
				     (default-directory project))
				 (with-temp-buffer
				   (setq buffer-file-name file)
				   (should-not (sdkman-apply-buffer-env nil root))
				   (should-not (getenv "JAVA_HOME"))
				   (should (equal exec-path '("/usr/bin"))))))))

(ert-deftest sdkman--java-runtime-name-derives-major-version ()
  (should (equal (sdkman--java-runtime-name "26-tem") "JavaSE-26"))
  (should (equal (sdkman--java-runtime-name "21.0.11-tem") "JavaSE-21"))
  (should (equal (sdkman--java-runtime-name "8.0.452-tem") "JavaSE-8")))

(ert-deftest sdkman--java-runtime-name-returns-nil-without-digits ()
  (should-not (sdkman--java-runtime-name "nightly"))
  (should-not (sdkman--java-runtime-name nil)))

(ert-deftest sdkman-lsp-java-apply-sets-java-path-and-runtime ()
  (sdkman-test-with-temp-dir root
                             (let* ((project (expand-file-name "project" root))
                                    (file (expand-file-name "App.java" project))
                                    (java-home (sdkman-test-create-candidate root "java" "26-tem")))
                               (sdkman-test-write-file (expand-file-name ".sdkmanrc" project)
                                                       "java=26-tem\n")
                               (sdkman-test-write-file file "class App {}\n")
                               (with-temp-buffer
                                 (setq buffer-file-name file)
                                 (sdkman-lsp-java-apply nil root)
                                 (should (equal lsp-java-java-path
                                                (expand-file-name "bin/java" java-home)))
                                 (should (vectorp lsp-java-configuration-runtimes))
                                 (should (= 1 (length lsp-java-configuration-runtimes)))
                                 (let ((runtime (aref lsp-java-configuration-runtimes 0)))
                                   (should (equal (plist-get runtime :name) "JavaSE-26"))
                                   (should (equal (plist-get runtime :path)
                                                  (file-name-as-directory java-home)))
                                   (should (eq (plist-get runtime :default) t)))))))

(ert-deftest sdkman-lsp-java-apply-noop-without-java-entry ()
  (sdkman-test-with-temp-dir root
                             (let* ((project (expand-file-name "project" root))
                                    (file (expand-file-name "pom.xml" project)))
                               (sdkman-test-write-file (expand-file-name ".sdkmanrc" project)
                                                       "maven=3.9.15\n")
                               (sdkman-test-write-file file "<project/>\n")
                               (with-temp-buffer
                                 (setq buffer-file-name file)
                                 (let ((lsp-java-java-path 'untouched)
                                       (lsp-java-configuration-runtimes 'untouched))
                                   (should-not (sdkman-lsp-java-apply nil root))
                                   (should (eq lsp-java-java-path 'untouched))
                                   (should (eq lsp-java-configuration-runtimes 'untouched)))))))

(ert-deftest sdkman-lsp-java-apply-warns-and-returns-nil-on-missing-candidate ()
  (sdkman-test-with-temp-dir root
                             (let* ((project (expand-file-name "project" root))
                                    (file (expand-file-name "App.java" project)))
                               (sdkman-test-write-file (expand-file-name ".sdkmanrc" project)
                                                       "java=missing\n")
                               (sdkman-test-write-file file "class App {}\n")
                               (with-temp-buffer
                                 (setq buffer-file-name file)
                                 (let ((warned nil))
                                   (cl-letf (((symbol-function 'display-warning)
                                              (lambda (&rest _) (setq warned t))))
                                     (should-not (sdkman-lsp-java-apply nil root))
                                     (should warned)))))))

(ert-deftest sdkman-lsp-java-excluded-file-p-matches-configured-directories ()
  (sdkman-test-with-temp-dir root
                             (let* ((excluded (sdkman-test-mkdir
                                               (expand-file-name "jdt.ls/workspace" root)))
                                    (allowed (sdkman-test-mkdir
                                              (expand-file-name "project" root)))
                                    (inside (expand-file-name "cache/foo.java" excluded))
                                    (outside (expand-file-name "src/App.java" allowed)))
                               (sdkman-test-write-file inside "")
                               (sdkman-test-write-file outside "")
                               (let ((sdkman-lsp-java-excluded-directories (list excluded)))
                                 (should (sdkman-lsp-java-excluded-file-p inside))
                                 (should-not (sdkman-lsp-java-excluded-file-p outside))
                                 (should-not (sdkman-lsp-java-excluded-file-p nil))))))

(ert-deftest sdkman-apply-buffer-env-warns-on-missing-candidate ()
  (sdkman-test-with-temp-dir root
                             (let* ((project (expand-file-name "project" root))
                                    (file (expand-file-name "App.java" project)))
                               (sdkman-test-write-file (expand-file-name ".sdkmanrc" project)
                                                       "java=missing\n")
                               (sdkman-test-write-file file "class App {}\n")
                               (let ((process-environment (list "PATH=/usr/bin"))
                                     (exec-path '("/usr/bin"))
                                     (default-directory project)
                                     (sdkman-warn-on-missing-candidate t))
                                 (with-temp-buffer
                                   (setq buffer-file-name file)
                                   (let ((warned nil))
                                     (cl-letf (((symbol-function 'display-warning)
                                                (lambda (&rest args) (setq warned args))))
                                       (sdkman-apply-buffer-env nil root)
                                       (should warned)
                                       (should (equal (car warned) 'sdkman))
                                       (should (string-match-p "missing" (cadr warned))))))))))

(ert-deftest sdkman-apply-buffer-env-silent-when-warning-disabled ()
  (sdkman-test-with-temp-dir root
                             (let* ((project (expand-file-name "project" root))
                                    (file (expand-file-name "App.java" project)))
                               (sdkman-test-write-file (expand-file-name ".sdkmanrc" project)
                                                       "java=missing\n")
                               (sdkman-test-write-file file "class App {}\n")
                               (let ((process-environment (list "PATH=/usr/bin"))
                                     (exec-path '("/usr/bin"))
                                     (default-directory project)
                                     (sdkman-warn-on-missing-candidate nil))
                                 (with-temp-buffer
                                   (setq buffer-file-name file)
                                   (let ((warned nil))
                                     (cl-letf (((symbol-function 'display-warning)
                                                (lambda (&rest _) (setq warned t))))
                                       (sdkman-apply-buffer-env nil root)
                                       (should-not warned))))))))


(ert-deftest sdkman--ensure-root-signals-user-error-for-missing-root ()
    (let ((sdkman-root "/tmp/sdkman-does-not-exist-xyzzy"))
      (should-error (sdkman--ensure-root) :type 'user-error)))


 (ert-deftest sdkman--ensure-root-warns-in-implicit-mode ()
    (let ((sdkman-root "/tmp/sdkman-does-not-exist-xyzzy")
          (warned nil))
      (cl-letf (((symbol-function 'display-warning)
                 (lambda (&rest _) (setq warned t))))
        (should-not (sdkman--ensure-root t))
        (should warned))))

(ert-deftest sdkman--init-script-returns-path-under-real-root ()
    (sdkman-test-with-temp-dir root
      (let ((script (expand-file-name "bin/sdkman-init.sh" root)))
        (sdkman-test-write-file script "# stub\n")
        (should (equal (sdkman--init-script root) script)))))


(ert-deftest sdkman--init-script-returns-nil-when-absent ()
    (sdkman-test-with-temp-dir root
			       (should-not (sdkman--init-script root))))


(ert-deftest sdkman--status-lines-no-sdkmanrc ()
    (sdkman-test-with-temp-dir root
      (let ((lines (sdkman--status-lines root nil)))
        (should (string-match-p "(none)" (nth 1 lines))))))

 (ert-deftest sdkman--status-lines-installed-entry ()
    (sdkman-test-with-temp-dir root
      ;; Create the candidate dir AND a `current' symlink pointing at it
      (let* ((java-dir (expand-file-name "candidates/java" root))
             (sdkmanrc (expand-file-name ".sdkmanrc" root)))
        (sdkman-test-mkdir (expand-file-name "26-tem" java-dir))
        (make-symbolic-link "26-tem" (expand-file-name "current" java-dir))
        (sdkman-test-write-file sdkmanrc "java=26-tem\n")
        (let ((lines (sdkman--status-lines root sdkmanrc)))
          (should (cl-some (lambda (line) (string-match-p "\\[current: 26-tem\\]" line))
                           lines))))))
(ert-deftest sdkman--status-lines-missing-entry ()
    (sdkman-test-with-temp-dir root
      (let ((sdkmanrc (expand-file-name ".sdkmanrc" root)))
        (sdkman-test-write-file sdkmanrc "java=26-tem\n")
        (let ((lines (sdkman--status-lines root sdkmanrc)))
          (should (cl-some (lambda (line) (string-match-p "\\[NOT INSTALLED\\]" line))
                           lines))))))

(ert-deftest sdkman--status-lines-multiple-entries ()
    (sdkman-test-with-temp-dir root
      (let ((sdkmanrc (expand-file-name ".sdkmanrc" root)))
        (sdkman-test-write-file sdkmanrc "java=26-tem\nmaven=3.9.15\ngradle=9.5.0\n")
        (let ((lines (sdkman--status-lines root sdkmanrc)))
          (should (= (length lines) 5))))))   ; 2 header lines + 3 entries

 (ert-deftest sdkman-open-sdkmanrc-opens-the-found-rc-file ()
    (sdkman-test-with-temp-dir root
      (let* ((sdkmanrc (expand-file-name ".sdkmanrc" root))
             (opened nil))
        (sdkman-test-write-file sdkmanrc "java=26-tem\n")
        ;; Stub find-file to record its argument instead of opening a buffer.
        (cl-letf (((symbol-function 'find-file)
                   (lambda (path) (setq opened path))))
          (let ((default-directory root))
            (sdkman-open-sdkmanrc)))
        (should (equal opened sdkmanrc)))))

(ert-deftest sdkman-open-sdkmanrc-signals-when-no-rc ()
    (sdkman-test-with-temp-dir root
      (let ((default-directory root))
        (should-error (sdkman-open-sdkmanrc) :type 'user-error))))

(ert-deftest sdkman-show-env-shows-applied-sdks ()
    (sdkman-test-with-temp-dir root
      (let* ((project (expand-file-name "project" root))
             (file    (expand-file-name "App.java" project))
             (java-home (sdkman-test-create-candidate root "java" "26-tem")))
        (sdkman-test-write-file (expand-file-name ".sdkmanrc" project)
                                "java=26-tem\n")
        (sdkman-test-write-file file "class App {}\n")
        ;; Stub pop-to-buffer so the test doesn't try to open a window.
        (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
          (let ((default-directory project)
                (sdkman-root root))
            (with-temp-buffer
              (setq buffer-file-name file)
              (sdkman-show-env))))
        (with-current-buffer "*sdkman-env*"
          (should (string-match-p "java" (buffer-string)))
          (should (string-match-p (regexp-quote java-home) (buffer-string)))))))


(ert-deftest sdkman-show-env-shows-fallback-when-no-env ()
    (sdkman-test-with-temp-dir root
      (let ((default-directory root))
        (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
          (with-temp-buffer
            (sdkman-show-env)))
        (with-current-buffer "*sdkman-env*"
          (should (string-match-p "no SDKMAN environment applied"
                                  (buffer-string)))))))

(ert-deftest sdkman-show-installed-lists-candidates ()
    (sdkman-test-with-temp-dir root
      (let ((sdkman-root root))
        ;; Create two installed candidates under candidates/java
        (sdkman-test-mkdir (expand-file-name "candidates/java/26-tem" root))
        (sdkman-test-mkdir (expand-file-name "candidates/java/21.0.11-tem" root))
        (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
          (sdkman-show-installed "java"))
        (with-current-buffer "*sdkman-installed*"
          (should (string-match-p "26-tem" (buffer-string)))
          (should (string-match-p "21\\.0\\.11-tem" (buffer-string)))))))

 (ert-deftest sdkman-show-installed-shows-fallback-when-no-candidates ()
    (sdkman-test-with-temp-dir root
      (let ((sdkman-root root))
        (cl-letf (((symbol-function 'pop-to-buffer) #'ignore))
          (sdkman-show-installed "java"))
        (with-current-buffer "*sdkman-installed*"
          (should (string-match-p "no installed candidates for java"
                                  (buffer-string)))))))


;;;; Phase 2 — async sdk CLI passthrough

(ert-deftest sdkman--process-sentinel-messages-on-nonzero-exit ()
    "Sentinel calls `message' with the exit info when the process exits non-zero."
    (let ((captured nil))
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args)
                   (setq captured (apply #'format fmt args)))))
        (let ((proc (make-process
                     :name "sdkman-test-fail"
                     :buffer (generate-new-buffer " *sdkman-test-fail*")
                     :command '("sh" "-c" "exit 7")
                     :sentinel #'sdkman--process-sentinel)))
          (unwind-protect
              (progn
                (while (process-live-p proc)
                  (accept-process-output proc 1))
                ;; Let the event loop run once more so the sentinel can fire.
                (accept-process-output nil 0.1)
                (should captured)
                (should (string-match-p "exited" captured))
                (should (string-match-p "7" captured)))
            (when (buffer-live-p (process-buffer proc))
              (kill-buffer (process-buffer proc))))))))


(provide 'sdkman-test)

;;; sdkman-test.el ends here
