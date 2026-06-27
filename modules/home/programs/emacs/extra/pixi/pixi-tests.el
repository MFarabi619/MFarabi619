;;; pixi-tests.el --- Buttercup tests for pixi.el -*- lexical-binding: t; -*-

;;; Commentary:

;;; Code:

(require 'buttercup)
(require 'ert-x)
(require 'cl-lib)
(require 'pixi)

(buttercup-define-matcher-for-binary-function
    :to-be-file-equal file-equal-p
  :expect-match-phrase    "Expected `%A' to refer to the same file as `%B', but it was `%a'."
  :expect-mismatch-phrase "Expected `%A' not to refer to the same file as `%B', but it did.")

(defconst pixi-tests--info-json
  "{\"platform\":\"osx-arm64\",\"version\":\"0.70.0\",\
\"project_info\":{\"name\":\"X\",\"version\":\"0.1.0\"},\
\"environments_info\":[\
{\"name\":\"default\",\"tasks\":[\"build\",\"run\"]},\
{\"name\":\"dev\",\"tasks\":[\"build\",\"test\"]}\
]}")

(defconst pixi-tests--task-list-json
  "[{\"environment\":\"default\",\
\"features\":[\
{\"name\":\"build\",\"tasks\":[\
{\"name\":\"build\",\"cmd\":\"colcon build\",\"depends_on\":[]}\
]},\
{\"name\":\"default\",\"tasks\":[\
{\"name\":\"robot\",\"cmd\":\"ros2 run robot x\",\
\"depends_on\":[{\"task_name\":\"build\"}]}\
]}]},\
{\"environment\":\"dev\",\
\"features\":[{\"name\":\"build\",\"tasks\":[\
{\"name\":\"build\",\"cmd\":\"colcon build\",\"depends_on\":[]}\
]}]}]")

(defun pixi-tests--info ()
  (json-parse-string pixi-tests--info-json
                     :object-type 'alist :array-type 'list
                     :null-object nil :false-object nil))

(defun pixi-tests--task-list-raw ()
  (json-parse-string pixi-tests--task-list-json
                     :object-type 'alist :array-type 'list
                     :null-object nil :false-object nil))

(defun pixi-tests--make-workspace (dir manifest-name manifest-body)
  "Write MANIFEST-NAME with MANIFEST-BODY in DIR, return the absolute path."
  (let ((manifest (expand-file-name manifest-name dir)))
    (write-region manifest-body nil manifest)
    manifest))

(describe "pixi--pyproject-has-pixi-p"
  (it "is non-nil when [tool.pixi.*] is declared"
    (ert-with-temp-directory dir
      (let ((path (expand-file-name "pyproject.toml" dir)))
        (write-region "[project]\nname = \"x\"\n\n[tool.pixi.workspace]\nchannels = []\n"
                      nil path)
        (expect (pixi--pyproject-has-pixi-p path)))))

  (it "is nil for a plain pyproject.toml without [tool.pixi]"
    (ert-with-temp-directory dir
      (let ((path (expand-file-name "pyproject.toml" dir)))
        (write-region "[project]\nname = \"x\"\n" nil path)
        (expect (pixi--pyproject-has-pixi-p path) :not :to-be-truthy))))

  (it "is nil when the file does not exist"
    (expect (pixi--pyproject-has-pixi-p "/nonexistent/pyproject.toml")
            :not :to-be-truthy)))

(describe "pixi-p"
  (it "is non-nil when pixi.toml is present"
    (ert-with-temp-directory dir
      (pixi-tests--make-workspace dir "pixi.toml" "[workspace]\nname = \"t\"\n")
      (let ((default-directory dir))
        (expect (pixi-p)))))

  (it "is non-nil when pyproject.toml carries a [tool.pixi.*] section"
    (ert-with-temp-directory dir
      (pixi-tests--make-workspace
       dir "pyproject.toml"
       "[tool.pixi.workspace]\nchannels=[]\n")
      (let ((default-directory dir))
        (expect (pixi-p)))))

  (it "is nil for a plain pyproject.toml"
    (ert-with-temp-directory dir
      (pixi-tests--make-workspace dir "pyproject.toml" "[project]\nname=\"x\"\n")
      (let ((default-directory dir))
        (expect (pixi-p) :not :to-be-truthy)))))

(describe "pixi-manifest-file"
  (it "returns the absolute pixi.toml path when present"
    (ert-with-temp-directory dir
      (let ((manifest (pixi-tests--make-workspace dir "pixi.toml" "[workspace]\n"))
            (default-directory dir))
        (expect (pixi-manifest-file) :to-be-file-equal manifest))))

  (it "falls back to pyproject.toml when [tool.pixi] is declared there"
    (ert-with-temp-directory dir
      (let ((manifest (pixi-tests--make-workspace
                       dir "pyproject.toml"
                       "[tool.pixi.workspace]\nchannels=[]\n"))
            (default-directory dir))
        (expect (pixi-manifest-file) :to-be-file-equal manifest))))

  (it "returns nil when neither manifest is present"
    (ert-with-temp-directory dir
      (let ((default-directory dir))
        (expect (pixi-manifest-file) :not :to-be-truthy)))))

(describe "pixi-root"
  (it "walks up from a nested subdirectory to the workspace root"
    (ert-with-temp-directory dir
      (pixi-tests--make-workspace dir "pixi.toml" "[workspace]\n")
      (let ((subdir (expand-file-name "deep/nested/" dir)))
        (make-directory subdir t)
        (let ((default-directory subdir))
          (expect (pixi-root) :to-be-file-equal dir)))))

  (it "returns nil outside any pixi workspace"
    (ert-with-temp-directory dir
      (let ((default-directory dir))
        (expect (pixi-root) :not :to-be-truthy)))))

(describe "pixi--manifest-args"
  (it "returns (\"--manifest-path\" PATH) inside a workspace"
    (ert-with-temp-directory dir
      (let ((manifest (pixi-tests--make-workspace dir "pixi.toml" "[workspace]\n"))
            (default-directory dir))
        (expect (pixi--manifest-args)
                :to-equal (list "--manifest-path" manifest)))))

  (it "returns nil outside any workspace"
    (ert-with-temp-directory dir
      (let ((default-directory dir))
        (expect (pixi--manifest-args) :not :to-be-truthy)))))

(describe "pixi--call"
  (it "appends --manifest-path AFTER the subcommand args"
    (ert-with-temp-directory dir
      (let ((manifest (pixi-tests--make-workspace dir "pixi.toml" "[workspace]\n"))
            (default-directory dir)
            captured)
        (cl-letf (((symbol-function 'call-process)
                   (lambda (_program _infile _dest _display &rest args)
                     (setq captured args)
                     (insert "ok\n")
                     0)))
          (pixi--call '("info" "--json")))
        (expect captured :to-equal
                (list "info" "--json" "--manifest-path" manifest)))))

  (it "signals on non-zero exit"
    (cl-letf (((symbol-function 'call-process)
               (lambda (&rest _) (insert "boom\n") 2)))
      (expect (pixi--call '("info")) :to-throw 'error))))

(describe "pixi--json-call"
  (it "decodes stdout as an alist via pixi--call"
    (spy-on 'pixi--call :and-return-value "{\"name\":\"x\",\"version\":\"1.0\"}")
    (let ((parsed (pixi--json-call '("info" "--json"))))
      (expect (alist-get 'name    parsed) :to-equal "x")
      (expect (alist-get 'version parsed) :to-equal "1.0"))))

(describe "pixi-info"
  :var (manifest dir)
  (before-each
    (clrhash pixi--info-cache))

  (it "shells out only once for repeated reads at the same manifest mtime"
    (ert-with-temp-directory dir
      (pixi-tests--make-workspace dir "pixi.toml" "[workspace]\n")
      (let ((default-directory dir))
        (spy-on 'pixi--json-call :and-call-fake
                (lambda (&rest _) (pixi-tests--info)))
        (pixi-info)
        (pixi-info)
        (expect 'pixi--json-call :to-have-been-called-times 1))))

  (it "re-fetches after `pixi-info-invalidate'"
    (ert-with-temp-directory dir
      (pixi-tests--make-workspace dir "pixi.toml" "[workspace]\n")
      (let ((default-directory dir))
        (spy-on 'pixi--json-call :and-call-fake
                (lambda (&rest _) (pixi-tests--info)))
        (pixi-info)
        (pixi-info-invalidate)
        (pixi-info)
        (expect 'pixi--json-call :to-have-been-called-times 2)))))

(describe "thin info-backed readers"
  (before-each
    (spy-on 'pixi-info :and-call-fake
            (lambda (&rest _) (pixi-tests--info))))

  (it "expose platform / cli-version"
    (expect (pixi-platform)    :to-equal "osx-arm64")
    (expect (pixi-cli-version) :to-equal "0.70.0"))

  (it "expose project name and version"
    (expect (pixi-name)    :to-equal "X")
    (expect (pixi-version) :to-equal "0.1.0"))

  (it "enumerate environment names"
    (expect (pixi-environment-names) :to-equal '("default" "dev")))

  (it "compose `pixi-tasks' as the deduped union of per-env tasks"
    (expect (sort (pixi-tasks) #'string<)
            :to-equal '("build" "run" "test")))

  (it "scope `pixi-environment-tasks' to a single env"
    (expect (pixi-environment-tasks "dev") :to-equal '("build" "test"))))

(describe "pixi-tasks-detailed"
  (before-each
    (spy-on 'pixi-task-list-raw :and-call-fake
            (lambda (&rest _) (pixi-tests--task-list-raw))))

  (it "flattens features and decorates each task with environment+feature"
    (let* ((tasks (pixi-tasks-detailed))
           (robot (seq-find (lambda (task)
                              (equal "robot" (alist-get 'name task)))
                            tasks)))
      (expect (alist-get 'environment robot) :to-equal "default")
      (expect (alist-get 'feature     robot) :to-equal "default")))

  (it "extracts depends_on as a flat list of task names"
    (let* ((tasks (pixi-tasks-detailed))
           (robot (seq-find (lambda (task)
                              (equal "robot" (alist-get 'name task)))
                            tasks)))
      (expect (pixi--task-depends-on robot) :to-equal '("build")))))

(describe "pixi-task"
  (before-each
    (spy-on 'pixi-task-list-raw :and-call-fake
            (lambda (&rest _) (pixi-tests--task-list-raw))))

  (it "disambiguates by (name, environment) when the same task exists in many envs"
    (expect (alist-get 'cmd (pixi-task "build" "default")) :to-equal "colcon build")
    (expect (alist-get 'cmd (pixi-task "build" "dev"))     :to-equal "colcon build"))

  (it "returns nil for an unknown task"
    (expect (pixi-task "nonexistent" "default") :not :to-be-truthy)))

(describe "pixi-packages"
  (it "passes `-e ENV' before `--manifest-path'"
    (ert-with-temp-directory dir
      (let ((manifest (pixi-tests--make-workspace dir "pixi.toml" "[workspace]\n"))
            (default-directory dir)
            captured)
        (cl-letf (((symbol-function 'call-process)
                   (lambda (_program _infile _dest _display &rest args)
                     (setq captured args)
                     (insert "[]")
                     0)))
          (pixi-packages "lyrical"))
        (expect captured :to-equal
                (list "list" "--json" "-e" "lyrical"
                      "--manifest-path" manifest))))))

(describe "pixi--task-list-grouped"
  (before-each
    (spy-on 'pixi-task-list-raw :and-call-fake
            (lambda (&rest _) (pixi-tests--task-list-raw))))

  (it "dedupes (feature, name) pairs across environments"
    (let* ((groups (pixi--task-list-grouped))
           (build  (seq-find (lambda (row)
                               (equal (car row) '("build" . "build")))
                             groups)))
      (expect build :to-be-truthy)
      (expect (cddr build) :to-have-same-items-as '("default" "dev"))
      (expect (length groups) :to-equal 2))))

(describe "pixi--visible-envs"
  (it "removes envs listed in `pixi-task-list-hide-envs'"
    (let ((pixi-task-list-hide-envs '("default")))
      (expect (pixi--visible-envs '("default" "lyrical" "dev"))
              :to-equal '("dev" "lyrical"))
      (expect (pixi--visible-envs '("default")) :not :to-be-truthy)))

  (it "respects a custom hide list"
    (let ((pixi-task-list-hide-envs '("ci")))
      (expect (pixi--visible-envs '("default" "ci" "lyrical"))
              :to-equal '("default" "lyrical")))))

(describe "pixi--truncate"
  (it "passes short strings through unchanged"
    (expect (pixi--truncate "short" 60) :to-equal "short")
    (expect (pixi--truncate "" 60) :to-equal ""))

  (it "appends an ellipsis when over the width limit"
    (let ((truncated (pixi--truncate (make-string 100 ?a) 10)))
      (expect (length truncated) :to-equal 10)
      (expect truncated :to-match "…\\'"))))

(describe "pixi--task-row-title"
  (it "includes every visible-column segment"
    (let* ((pixi-task-list-visible-columns '(task feature environments cmd))
           (task '((name . "robot")
                   (feature . "default")
                   (cmd . "ros2 run robot hat_mdd10sm")))
           (title (substring-no-properties
                   (pixi--task-row-title task '("default" "lyrical")))))
      (expect title :to-match "robot")
      (expect title :to-match "lyrical")
      (expect title :to-match "ros2 run robot hat_mdd10sm")))

  (it "omits disabled columns (default visible set has no FEATURE)"
    (let* ((pixi-task-list-visible-columns '(task cmd environments))
           (task '((name . "robot")
                   (feature . "default")
                   (cmd . "ros2 run robot hat_mdd10sm")))
           (title (substring-no-properties
                   (pixi--task-row-title task '("lyrical")))))
      (expect title :to-match "robot")
      (expect title :to-match "lyrical")
      (expect title :not :to-match "\\bdefault\\b")))

  (it "truncates a long cmd to `pixi-task-list-cmd-width'"
    (let* ((pixi-task-list-cmd-width 20)
           (task '((name . "build")
                   (feature . "build")
                   (cmd . "colcon build --symlink-install --paths libs/robot --cmake-args -DX=Y")))
           (title (substring-no-properties
                   (pixi--task-row-title task '("lyrical")))))
      (expect title :to-match "…")
      (expect title :not :to-match "cmake-args"))))

(describe "pixi--task-header-row"
  (it "uses only the labels of visible columns"
    (let ((pixi-task-list-visible-columns '(task cmd environments))
          (header (substring-no-properties (pixi--task-header-row))))
      (expect header :to-match "TASK")
      (expect header :to-match "ENVIRONMENTS")
      (expect header :to-match "CMD")
      (expect header :not :to-match "FEATURE")))

  (it "respects the visible-columns order"
    (let* ((pixi-task-list-visible-columns '(environments task cmd))
           (header (substring-no-properties (pixi--task-header-row))))
      (expect (string-match "ENVIRONMENTS" header)
              :to-be-less-than
              (string-match "TASK" header))))

  (it "renders FEATURE when explicitly enabled"
    (let* ((pixi-task-list-visible-columns '(task feature environments cmd))
           (header (substring-no-properties (pixi--task-header-row))))
      (expect header :to-match "FEATURE"))))

(describe "pixi--column-spec"
  (it "errors for an unknown column key"
    (expect (pixi--column-spec 'nonexistent) :to-throw 'error)))

(describe "pixi--resolve-width"
  (it "passes numeric widths through"
    (expect (pixi--resolve-width 14) :to-equal 14))

  (it "returns nil for a nil width"
    (expect (pixi--resolve-width nil) :not :to-be-truthy))

  (it "looks up a symbol width from its variable binding"
    (let ((pixi-task-list-cmd-width 42))
      (expect (pixi--resolve-width 'pixi-task-list-cmd-width) :to-equal 42)))

  (it "errors for an unknown width form"
    (expect (pixi--resolve-width '(weird)) :to-throw 'error)))

(describe "pixi--platform-icon"
  :var (capture)
  (before-each
    (setq capture nil)
    (spy-on 'nerd-icons-faicon :and-call-fake
            (lambda (name &rest _) (setq capture (cons 'faicon name)) ""))
    (spy-on 'nerd-icons-mdicon :and-call-fake
            (lambda (name &rest _) (setq capture (cons 'mdicon name)) "")))

  (it "dispatches to the apple faicon for osx-* platforms"
    (pixi--platform-icon "osx-arm64" 'vui-muted)
    (expect capture :to-equal '(faicon . "nf-fa-apple")))

  (it "dispatches to the linux faicon for linux-* platforms"
    (pixi--platform-icon "linux-64" 'vui-muted)
    (expect capture :to-equal '(faicon . "nf-fa-linux")))

  (it "dispatches to the windows faicon for win-* platforms"
    (pixi--platform-icon "win-64" 'vui-muted)
    (expect capture :to-equal '(faicon . "nf-fa-windows")))

  (it "falls back to the generic monitor mdicon for unknown families"
    (pixi--platform-icon "freebsd-x86_64" 'vui-muted)
    (expect capture :to-equal '(mdicon . "nf-md-monitor"))))

(describe "pixi--task-list-set-mode-line"
  :var (icon-calls joined)
  (before-each
    (setq icon-calls nil)
    (spy-on 'pixi-info  :and-call-fake (lambda (&rest _) (pixi-tests--info)))
    (spy-on 'pixi-tasks :and-return-value '("build" "run" "test"))
    (spy-on 'nerd-icons-codicon :and-call-fake
            (lambda (name &rest _) (push name icon-calls) ""))
    (with-temp-buffer
      (pixi--task-list-set-mode-line)
      (setq joined (apply #'concat
                          (cl-remove-if-not #'stringp
                                            (flatten-list mode-name))))))

  (it "prefixes the CLI version with `v'"
    (expect joined :to-match "v0\\.70\\.0"))

  (it "renders the env count followed by labels (no `envs' word)"
    (expect joined :to-match " 2 ")
    (expect joined :not :to-match "envs"))

  (it "renders the task count followed by labels (no `tasks' word)"
    (expect joined :to-match " 3 ")
    (expect joined :not :to-match "tasks"))

  (it "uses the nf-cod-json codicon for envs"
    (expect icon-calls :to-contain "nf-cod-json"))

  (it "uses the nf-cod-play codicon for tasks"
    (expect icon-calls :to-contain "nf-cod-play"))

  (it "still shows the platform"
    (expect joined :to-match "osx-arm64")))

(describe "pixi-refresh"
  (it "invalidates the info cache, then triggers a vui re-render"
    (let ((sequence nil))
      (spy-on 'pixi-info-invalidate :and-call-fake
              (lambda (&rest _) (push 'invalidate sequence)))
      (spy-on 'vui-refresh :and-call-fake
              (lambda (&rest _) (push 'refresh sequence)))
      (pixi-refresh)
      (expect (nreverse sequence) :to-equal '(invalidate refresh)))))

(describe "pixi-clean"
  (before-each (spy-on 'yes-or-no-p :and-return-value t))

  (it "compiles `pixi clean' without -e by default"
    (ert-with-temp-directory dir
      (pixi-tests--make-workspace dir "pixi.toml" "[workspace]\n")
      (let ((default-directory dir)
            captured)
        (spy-on 'compile :and-call-fake (lambda (cmd) (setq captured cmd)))
        (pixi-clean)
        (expect captured :to-match "\\bclean\\b")
        (expect captured :to-match "--manifest-path")
        (expect captured :not :to-match "-e"))))

  (it "adds `-e ENV' when scoped to an environment"
    (ert-with-temp-directory dir
      (pixi-tests--make-workspace dir "pixi.toml" "[workspace]\n")
      (let ((default-directory dir)
            captured)
        (spy-on 'compile :and-call-fake (lambda (cmd) (setq captured cmd)))
        (pixi-clean "lyrical")
        (expect captured :to-match "-e lyrical"))))

  (it "aborts (no compile call) when confirmation is declined"
    (ert-with-temp-directory dir
      (pixi-tests--make-workspace dir "pixi.toml" "[workspace]\n")
      (let ((default-directory dir))
        (spy-on 'yes-or-no-p :and-return-value nil)
        (spy-on 'compile)
        (pixi-clean)
        (expect 'compile :not :to-have-been-called)))))

(describe "pixi-tree"
  (it "compiles `pixi tree' with no -e when bare"
    (ert-with-temp-directory dir
      (pixi-tests--make-workspace dir "pixi.toml" "[workspace]\n")
      (let ((default-directory dir)
            captured)
        (spy-on 'compile :and-call-fake (lambda (cmd) (setq captured cmd)))
        (pixi-tree)
        (expect captured :to-match "\\btree\\b")
        (expect captured :to-match "--manifest-path")
        (expect captured :not :to-match "-e"))))

  (it "scopes to an environment via -e"
    (ert-with-temp-directory dir
      (pixi-tests--make-workspace dir "pixi.toml" "[workspace]\n")
      (let ((default-directory dir)
            captured)
        (spy-on 'compile :and-call-fake (lambda (cmd) (setq captured cmd)))
        (pixi-tree "lyrical")
        (expect captured :to-match "tree -e lyrical"))))

  (it "appends the regex as a positional after `-e ENV'"
    (ert-with-temp-directory dir
      (pixi-tests--make-workspace dir "pixi.toml" "[workspace]\n")
      (let ((default-directory dir)
            captured)
        (spy-on 'compile :and-call-fake (lambda (cmd) (setq captured cmd)))
        (pixi-tree "default" "ros")
        (expect captured :to-match "tree -e default ros"))))

  (it "drops an empty regex string from the command line"
    (ert-with-temp-directory dir
      (pixi-tests--make-workspace dir "pixi.toml" "[workspace]\n")
      (let ((default-directory dir)
            captured)
        (spy-on 'compile :and-call-fake (lambda (cmd) (setq captured cmd)))
        (pixi-tree "default" "")
        (expect captured :to-match "tree -e default --manifest-path")))))

(defconst pixi-tests--pixi-el
  (expand-file-name "pixi.el"
                    (file-name-directory (locate-library "pixi"))))

(defun pixi-tests--all-pixi-symbols ()
  (let (syms)
    (mapatoms
     (lambda (s)
       (let ((name (symbol-name s)))
         (when (and (or (fboundp s) (boundp s))
                    (or (string-prefix-p "pixi-" name)
                        (string-prefix-p "pixi--" name)
                        (string= "pixi" name))
                    (not (string-prefix-p "pixi-tests" name))
                    (not (string-prefix-p "pixi--task-overview" name)))
           (push s syms)))))
    syms))

(describe "docstring coverage (matches west.el / zephyr.el / platformio.el)"
  (it "every defun has a non-empty docstring"
    (let ((undocumented
           (seq-filter
            (lambda (sym)
              (and (fboundp sym)
                   (not (autoloadp (symbol-function sym)))
                   (not (subrp (symbol-function sym)))
                   (let ((doc (documentation sym)))
                     (or (null doc) (string-empty-p doc)))))
            (pixi-tests--all-pixi-symbols))))
      (expect undocumented :to-equal nil)))

  (it "every defvar/defcustom/defconst has a docstring"
    (let ((undocumented
           (seq-filter
            (lambda (sym)
              (and (boundp sym)
                   (not (keywordp sym))
                   (not (custom-variable-p sym))
                   (not (get sym 'variable-documentation))
                   (not (fboundp sym))))
            (pixi-tests--all-pixi-symbols))))
      (expect undocumented :to-equal nil))))

(describe "file header"
  :var (contents)
  (before-each
    (setq contents (with-temp-buffer
                     (insert-file-contents pixi-tests--pixi-el)
                     (buffer-string))))

  (it "uses the typographic copyright symbol"
    (expect contents :to-match "Copyright © "))

  (it "declares a URL line"
    (expect contents :to-match "^;; URL: https://github\\.com/MFarabi619/MFarabi619"))

  (it "declares Package-Version, Package-Revision, Package-Requires"
    (expect contents :to-match "^;; Package-Version:")
    (expect contents :to-match "^;; Package-Revision:")
    (expect contents :to-match "^;; Package-Requires:"))

  (it "carries the `not part of GNU Emacs' notice with full GPL header"
    (expect contents :to-match "This file is NOT part of GNU Emacs")
    (expect contents :to-match "GNU General Public License")
    (expect contents :to-match "Free Software Foundation"))

  (it "has a `;;; Commentary:' block"
    (expect contents :to-match "^;;; Commentary:"))

  (it "lists every interactive command under `Commands:'"
    (let ((commands-section
           (and (string-match
                 ";;; Commentary:\\(\\(?:\n;;.*\\)*\\)"
                 contents)
                (match-string 1 contents))))
      (expect commands-section :to-match "Commands:")
      (expect commands-section :to-match "^;;   pixi\\b")
      (expect commands-section :to-match "^;;   pixi-clean\\b")
      (expect commands-section :to-match "^;;   pixi-tree\\b")
      (expect commands-section :to-match "^;;   pixi-refresh\\b"))))

(describe "pixi--buffer-name"
  (it "embeds the workspace identity as `*pixi:NAME@VERSION*'"
    (spy-on 'pixi-info :and-call-fake (lambda (&rest _) (pixi-tests--info)))
    (expect (pixi--buffer-name) :to-equal "*pixi:X@0.1.0*"))

  (it "falls back to `*pixi*' when pixi-info is unavailable"
    (spy-on 'pixi-info :and-return-value nil)
    (expect (pixi--buffer-name) :to-equal "*pixi*")))

(describe "pixi--task-list-set-mode-line color diversity"
  :var (mode-line-text faces)
  (before-each
    (spy-on 'pixi-info  :and-call-fake (lambda (&rest _) (pixi-tests--info)))
    (spy-on 'pixi-tasks :and-return-value '("build" "run" "test"))
    (with-temp-buffer
      (pixi--task-list-set-mode-line)
      (setq mode-line-text (apply #'concat
                                  (cl-remove-if-not #'stringp
                                                    (flatten-list mode-name))))
      (setq faces
            (delq nil
                  (mapcar (lambda (part)
                            (and (stringp part)
                                 (get-text-property 0 'face part)))
                          (flatten-list mode-name))))))

  (it "no longer embeds the workspace name (lives in buffer name now)"
    (expect mode-line-text :not :to-match "MFarabi619")
    (expect mode-line-text :not :to-match "0\\.1\\.0"))

  (it "still shows the pixi CLI version"
    (expect mode-line-text :to-match "0\\.70\\.0"))

  (it "uses more than one face across its icons (not all vui-success)"
    (expect (length (delete-dups faces)) :to-be-greater-than 2)))

(describe "pixi (single entry point)"
  (it "is registered as `pixi' and callable from any buffer"
    (expect (fboundp 'pixi)                   :to-be-truthy)
    (expect (commandp 'pixi)                  :to-be-truthy)
    (expect (command-modes 'pixi)             :not :to-be-truthy))

  (it "no longer exposes the old `pixi-task-list' command"
    (expect (commandp 'pixi-task-list)        :not :to-be-truthy))

  (it "renders into a `*pixi:NAME@VERSION*' buffer in `pixi-mode'"
    (let (captured-buffer-name)
      (spy-on 'vui-mount :and-call-fake
              (lambda (_component buffer-name)
                (setq captured-buffer-name buffer-name)))
      (spy-on 'pixi--task-list-set-mode-line)
      (spy-on 'pixi-mode)
      (spy-on 'pixi-info :and-call-fake (lambda (&rest _) (pixi-tests--info)))
      (when (get-buffer "*pixi:X@0.1.0*") (kill-buffer "*pixi:X@0.1.0*"))
      (pixi)
      (expect captured-buffer-name :to-equal "*pixi:X@0.1.0*"))))

(describe "M-x discoverability"
  (it "scopes `pixi-clean' to pixi-mode buffers"
    (expect (command-modes 'pixi-clean)   :to-equal '(pixi-mode)))

  (it "scopes `pixi-tree' to pixi-mode buffers"
    (expect (command-modes 'pixi-tree)    :to-equal '(pixi-mode)))

  (it "scopes `pixi-refresh' to pixi-mode buffers"
    (expect (command-modes 'pixi-refresh) :to-equal '(pixi-mode)))

  (it "hides `pixi-info-invalidate' from M-x entirely"
    (expect (get 'pixi-info-invalidate 'completion-predicate)
            :to-equal #'ignore)))

(describe "against MFarabi619 (real-world integration)"
  :var (workspace)
  (before-each
    (setq workspace (expand-file-name "~/MFarabi619/"))
    (assume (file-exists-p (expand-file-name "pixi.toml" workspace))
            "MFarabi619 workspace not present")
    (assume (executable-find "pixi") "pixi CLI not on PATH")
    (pixi-info-invalidate))

  (it "detects the workspace from the repo root"
    (expect (pixi-root workspace) :to-be-file-equal workspace))

  (it "exposes workspace identity via pixi-info"
    (expect (pixi-name workspace)    :to-equal "MFarabi619")
    (expect (pixi-version workspace) :to-equal "0.1.0"))

  (it "lists both environments (default + lyrical)"
    (expect (pixi-environment-names workspace)
            :to-have-same-items-as '("default" "lyrical")))

  (it "collapses bridge/robot/teleop/build into 4 unique grouped tasks"
    (let ((default-directory workspace))
      (expect (length (pixi--task-list-grouped)) :to-equal 4)))

  (it "discovers `colcon build' as the `build' task's cmd in the default env"
    (let* ((default-directory workspace)
           (build (pixi-task "build" "default")))
      (expect (alist-get 'cmd build) :to-match "\\bcolcon build\\b"))))

;;; pixi-tests.el ends here
