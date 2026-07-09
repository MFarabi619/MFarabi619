;;; dioxus-tests.el --- Buttercup tests for dioxus.el  -*- lexical-binding: t; -*-

;;; Code:

(require 'buttercup)
(require 'nerd-icons)
(require 'seq)
(require 'dioxus)

(buttercup-error-on-stale-elc)
(setq buttercup-stack-frame-style 'pretty)

(defmacro dioxus-tests--with-workspace (files &rest body)
  "Run BODY in a throwaway workspace built from FILES.
FILES is an alist of (RELATIVE-PATH . CONTENT); a `.git/' marker is always
created so the workspace root resolves.  `dir' is bound to the root."
  (declare (indent 1))
  `(let ((dir (make-temp-file "dioxus-test" t)))
     (unwind-protect
       (progn
         (make-directory (expand-file-name ".git" dir))
         (dolist (file ,files)
           (let ((path (expand-file-name (car file) dir)))
             (make-directory (file-name-directory path) t)
             (with-temp-file path (insert (cdr file)))))
         ,@body)
       (delete-directory dir t))))

(defconst dioxus-tests--expected
  ;; DISPLAY          COMMAND                               ICON-FN            ICON-NAME
  '(("serve"         "dx serve -p web"                    nerd-icons-mdicon "nf-md-cursor_default_click")
     ("serve:desktop" "dx serve --platform desktop -p web" nerd-icons-mdicon "nf-md-desktop_classic")
     ("serve:ssg"     "dx serve -r --ssg -p web"           nerd-icons-faicon "nf-fa-scroll")
     ("build"         "dx build -p web"                    nerd-icons-mdicon "nf-md-crane"))
  "Expected dioxus tasks, reproduced from `.dir-locals.el' (serve:desktop fixed
to `--platform desktop'), with `-p PKG' derived from the app's Cargo.toml.")

(defun dioxus-tests--task (display)
  "Return the generated task named DISPLAY."
  (seq-find (lambda (task) (equal (plist-get task :name) display))
    (dioxus-tasks-source)))

(describe "dioxus-project-p"
  (it "detects a workspace containing a Dioxus app"
    (dioxus-tests--with-workspace
        '(("apps/web/Dioxus.toml" . "[web.app]\ntitle = \"x\"\n")
           ("apps/web/Cargo.toml" . "[package]\nname = \"web\"\n"))
      (expect (dioxus-project-p dir) :to-be-truthy)))

  (it "returns nil with no Dioxus.toml anywhere"
    (dioxus-tests--with-workspace
        '(("apps/web/Cargo.toml" . "[package]\nname = \"web\"\n"))
      (expect (dioxus-project-p dir) :to-be nil))))

(describe "dioxus--package"
  (it "derives the package name from the Dioxus app's Cargo.toml"
    (dioxus-tests--with-workspace
        '(("apps/web/Dioxus.toml" . "[web.app]\ntitle = \"x\"\n")
           ("apps/web/Cargo.toml" . "[package]\nname = \"web\"\n"))
      (expect (dioxus--package dir) :to-equal "web"))))

(describe "dioxus-tasks-source"
  (before-each
    (spy-on 'dioxus--workspace-root :and-return-value "/Users/x/repo/")
    (spy-on 'dioxus--package :and-return-value "web"))

  (it "generates exactly the four dioxus tasks in the package namespace"
    (let ((tasks (dioxus-tasks-source)))
      (expect (length tasks) :to-equal 4)
      (expect (seq-every-p
                (lambda (task) (equal (plist-get task :namespace) "web"))
                tasks)
        :to-be-truthy)
      (expect (seq-every-p
                (lambda (task) (equal (plist-get task :tool) "dioxus"))
                tasks)
        :to-be-truthy)))

  (describe "each task reproduces its command and icon"
    (dolist (spec dioxus-tests--expected)
      (let ((display   (nth 0 spec))
             (command  (nth 1 spec))
             (icon-fn  (nth 2 spec))
             (icon-name (nth 3 spec)))
        (it (format "renders `%s'" display)
          (let ((task (dioxus-tests--task display)))
            (expect task :not :to-be nil)
            (expect (plist-get task :command) :to-equal command)
            (expect (plist-get task :icon)
              :to-equal (funcall icon-fn icon-name)))))))

  (it "supervises the serve tasks with a daemon runner + readiness probe"
    (dolist (display '("serve" "serve:desktop" "serve:ssg"))
      (let* ((task (dioxus-tests--task display))
             (http-get (cdr (assq 'http_get
                                  (cdr (assq 'readiness_probe
                                             (plist-get task :config)))))))
        (expect (plist-get task :runner) :to-be 'daemon)
        (expect (cdr (assq 'port http-get)) :to-equal dioxus-serve-port))))

  (it "leaves `build' as a one-shot (no runner override, no config)"
    (expect (plist-get (dioxus-tests--task "build") :runner) :to-be nil)
    (expect (plist-get (dioxus-tests--task "build") :config) :to-be nil)))

(describe "dioxus--compile-multi-tasks"
  (it "feeds every source task through microvisor-task"
    (spy-on 'dioxus--workspace-root :and-return-value "/Users/x/repo/")
    (spy-on 'dioxus--package :and-return-value "web")
    (cl-letf (((symbol-function 'microvisor-task)
               (lambda (task) (plist-get task :name))))
      (expect (dioxus--compile-multi-tasks)
              :to-equal '("serve" "serve:desktop" "serve:ssg" "build")))))

(provide 'dioxus-tests)

;;; dioxus-tests.el ends here
