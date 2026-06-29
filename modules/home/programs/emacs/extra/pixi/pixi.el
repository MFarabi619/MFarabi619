;;; pixi.el --- Pixi workspace integration -*- lexical-binding: t -*-

;; Copyright © 2026 Mumtahin Farabi <mfarabi619@gmail.com>

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; URL: https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/pixi
;; Keywords: tools, embedded
;; Version: 0.0.1
;; Package-Requires: ((emacs "29.1") (nerd-icons "0.1") (vui "0.1"))

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.


;;; Commentary:
;;
;; Pixi workspace integration: project detection, JSON-driven readers over
;; `pixi info' / `pixi task list' / `pixi list', and a vui-rendered tasks
;; dashboard with mode-line workspace metadata.
;;
;; Commands:
;;   pixi          open the `*pixi:NAME@VERSION*' tasks dashboard
;;   pixi-clean    run `pixi clean' (all envs, or one with `\\[universal-argument]')
;;   pixi-tree     run `pixi tree' in a compile buffer
;;   pixi-refresh  drop the `pixi info' cache and re-render the dashboard
;;
;;; Code:

(require 'json)
(require 'map)
(require 'pcase)
(require 'nerd-icons)
(require 'vui)
(require 'vui-components)

(defgroup pixi ()
  "Pixi workspace integration."
  :prefix "pixi-"
  :group 'tools)

(defface pixi-task-list-task
  '((t :inherit vui-heading-1))
  "Face for the TASK column in the `pixi' dashboard."
  :group 'pixi)

(defface pixi-task-list-env
  '((t :inherit vui-muted :box (:line-width -1 :color nil :style nil)))
  "Pill face for entries in the ENVIRONMENTS column of the `pixi' dashboard."
  :group 'pixi)

(defface pixi-task-list-dep
  '((t :inherit vui-muted :box (:line-width -1 :color nil :style nil)))
  "Pill face for dependency chips in the `pixi' dashboard."
  :group 'pixi)

(defun pixi--pill (text face)
  "Render TEXT padded by one space on each side, propertized with FACE."
  (propertize (format " %s " text) 'face face))

(defcustom pixi-task-list-hide-envs '("default")
  "Environment names to hide from the ENVIRONMENTS column in the `pixi' dashboard.
The default environment is implicit in the TUI, so suppress it as visual noise."
  :type '(repeat string)
  :group 'pixi)

(defcustom pixi-task-list-cmd-width 60
  "Maximum displayed width of the CMD column in the `pixi' dashboard.
Commands longer than this are truncated with a trailing ellipsis."
  :type 'integer
  :group 'pixi)

(defun pixi--truncate (string width)
  "Return STRING capped to WIDTH chars (ellipsis appended when truncated)."
  (if (<= (length string) width)
    string
    (concat (substring string 0 (max 0 (1- width))) "…")))

(defvar pixi-task-list-columns
  '((task         :header "TASK"         :width 14
      :cell (lambda (task _envs)
              (propertize (alist-get 'name task)
                'face 'pixi-task-list-task)))
     (feature      :header "FEATURE"      :width 12
       :cell (lambda (task _envs)
               (propertize (alist-get 'feature task)
                 'face 'vui-muted)))
     (environments :header "ENVIRONMENTS" :width 16
       :cell (lambda (_task envs)
               (mapconcat (lambda (env)
                            (pixi--pill env 'pixi-task-list-env))
                 (pixi--visible-envs envs) " ")))
     (cmd          :header "CMD"          :width pixi-task-list-cmd-width
       :cell (lambda (task _envs)
               (propertize
                 (pixi--truncate
                   (string-clean-whitespace
                     (or (alist-get 'cmd task) ""))
                   pixi-task-list-cmd-width)
                 'face 'vui-code))))
  "Registry of available `pixi' dashboard columns.
Each entry is (KEY :header LABEL :width N :cell FN), where FN is
(task envs) -> propertized string. :width may be a number, a
symbol naming a variable to look up, or nil (leave un-padded, last
column only).")

(defcustom pixi-task-list-visible-columns '(task cmd environments)
  "Columns to display in the `pixi' dashboard, in order.
Each symbol must be a key in `pixi-task-list-columns'. Reorder or
remove entries to customize the view; see also `pixi-task-list-columns'
to add new columns."
  :type '(repeat symbol)
  :group 'pixi)

(defun pixi--column-spec (key)
  "Return the spec plist for column KEY, signaling on unknown keys."
  (or (alist-get key pixi-task-list-columns)
    (error "Unknown pixi-task-list column: %s" key)))

(defun pixi--resolve-width (width)
  "Resolve a column WIDTH.
Number passes through, symbol is looked up, nil stays nil."
  (cond ((null width) nil)
    ((numberp width) width)
    ((and (symbolp width) (boundp width)) (symbol-value width))
    (t (error "Invalid pixi-task-list column width: %S" width))))

(defun pixi--pad-cell (text width)
  "Pad TEXT to WIDTH columns (resolving symbolic widths).
Pass through unchanged when WIDTH is nil."
  (let ((resolved (pixi--resolve-width width)))
    (if resolved (string-pad text resolved) text)))

(defconst pixi--platform-icons
  '(("osx"   . ("nf-fa-apple"   . nerd-icons-faicon))
     ("linux" . ("nf-fa-linux"   . nerd-icons-faicon))
     ("win"   . ("nf-fa-windows" . nerd-icons-faicon)))
  "Alist mapping platform prefix to (ICON-NAME . NERD-ICONS-FN).")

(defun pixi--platform-icon (platform face)
  "Return a nerd-icon for PLATFORM (e.g. `osx-arm64'), colored with FACE."
  (let* ((prefix (car (split-string (or platform "") "-")))
          (entry  (assoc prefix pixi--platform-icons)))
    (if entry
      (funcall (cdr (cdr entry)) (car (cdr entry)) :face face)
      (nerd-icons-mdicon "nf-md-monitor" :face face))))

(defcustom pixi-executable nil
  "Path to the pixi executable. If nil, search PATH."
  :type '(choice (const :tag "Auto-detect" nil) file)
  :group 'pixi)

(defun pixi--executable ()
  "Return the configured pixi binary, falling back to a PATH lookup."
  (or pixi-executable (executable-find "pixi") "pixi"))

;;; Error taxonomy
;; Subclasses of `pixi-error' so callers can `condition-case' on specific
;; failure modes without parsing message strings.

(define-error 'pixi-error       "Pixi error")
(define-error 'pixi-exec-error  "Pixi CLI execution failed" 'pixi-error)
(define-error 'pixi-parse-error "Pixi output parse failed"  'pixi-error)

(defun pixi-p (&optional directory)
  "Non-nil if DIRECTORY contains a `pixi.toml'.
Also matches a `pyproject.toml' declaring a `[tool.pixi]' section."
  (let ((dir (or directory default-directory)))
    (or (file-exists-p (expand-file-name "pixi.toml" dir))
      (pixi--pyproject-has-pixi-p
        (expand-file-name "pyproject.toml" dir)))))

(defun pixi--pyproject-has-pixi-p (path)
  "Non-nil if PATH is a `pyproject.toml' file declaring a `[tool.pixi.*]' section."
  (and (file-exists-p path)
    (with-temp-buffer
      (insert-file-contents path)
      (goto-char (point-min))
      (re-search-forward "^\\[tool\\.pixi\\(\\.\\|\\]\\)" nil t))))

(defun pixi-root (&optional directory)
  "Walk up from DIRECTORY to find the enclosing pixi workspace root."
  (locate-dominating-file (or directory default-directory) #'pixi-p))

(defun pixi-in-project-p (&optional directory)
  "Non-nil if DIRECTORY (or `default-directory') is inside a pixi workspace."
  (and (pixi-root directory) t))

(defun pixi-manifest-file (&optional project-root)
  "Return the absolute manifest path for PROJECT-ROOT.
Falls back to the discovered workspace when PROJECT-ROOT is nil."
  (when-let ((root (or project-root (pixi-root))))
    (let ((pixi-toml (expand-file-name "pixi.toml" root))
           (pyproject (expand-file-name "pyproject.toml" root)))
      (cond
        ((file-exists-p pixi-toml) pixi-toml)
        ((pixi--pyproject-has-pixi-p pyproject) pyproject)))))

(defun pixi--manifest-args (&optional project-root)
  "Return (\"--manifest-path\" PATH) for PROJECT-ROOT, or nil outside any workspace."
  (when-let ((manifest (pixi-manifest-file project-root)))
    (list "--manifest-path" manifest)))

(defun pixi--call (args &optional project-root)
  "Run pixi with ARGS, splicing --manifest-path for PROJECT-ROOT; return stdout.
Signals `pixi-exec-error' on non-zero exit, with :args/:exit-code/:output data."
  (with-temp-buffer
    (let* ((full-args (append args (pixi--manifest-args project-root)))
            (exit-code (apply #'call-process (pixi--executable) nil t nil full-args)))
      (unless (zerop exit-code)
        (signal 'pixi-exec-error
          (list :args full-args :exit-code exit-code
            :output (buffer-string))))
      (buffer-string))))

(defun pixi--json-call (args &optional project-root)
  "Like `pixi--call', but decode stdout as a JSON alist.
Signals `pixi-parse-error' on bad JSON; passes through `pixi-exec-error'."
  (let ((output (pixi--call args project-root)))
    (condition-case-unless-debug parse-failure
      (json-parse-string output
        :object-type 'alist
        :array-type 'list
        :null-object nil
        :false-object nil)
      (json-parse-error
        (signal 'pixi-parse-error
          (list :args args :output output :cause parse-failure))))))

(defvar pixi--info-cache (make-hash-table :test 'equal)
  "Per-workspace cache mapping ROOT -> (MTIME . PARSED-INFO).")

(defun pixi-info (&optional project-root)
  "Return parsed `pixi info --json' for PROJECT-ROOT, cached by manifest mtime."
  (when-let* ((root     (or project-root (pixi-root)))
               (manifest (pixi-manifest-file root)))
    (let* ((mtime  (file-attribute-modification-time (file-attributes manifest)))
            (cached (gethash root pixi--info-cache)))
      (if (and cached (equal (car cached) mtime))
        (cdr cached)
        (let ((parsed (pixi--json-call '("info" "--json") root)))
          (puthash root (cons mtime parsed) pixi--info-cache)
          parsed)))))

(defun pixi-info-invalidate (&optional project-root)
  "Drop the cached `pixi info' parse for PROJECT-ROOT (or every workspace)."
  (interactive)
  (if project-root
    (remhash project-root pixi--info-cache)
    (clrhash pixi--info-cache)))
(put 'pixi-info-invalidate 'completion-predicate #'ignore)

(defun pixi-platform        (&optional project-root) "Workspace target platform string." (alist-get 'platform     (pixi-info project-root)))
(defun pixi-cli-version     (&optional project-root) "Pixi CLI version string."          (alist-get 'version      (pixi-info project-root)))
(defun pixi-cache-dir       (&optional project-root) "Pixi cache directory path."        (alist-get 'cache_dir    (pixi-info project-root)))
(defun pixi-auth-dir        (&optional project-root) "Pixi auth/credentials directory."  (alist-get 'auth_dir     (pixi-info project-root)))
(defun pixi-virtual-packages (&optional project-root) "Resolved virtual packages list."  (alist-get 'virtual_packages (pixi-info project-root)))

(defun pixi--project (&optional project-root)
  "Return the `project_info' sub-alist from `pixi-info' for PROJECT-ROOT."
  (alist-get 'project_info (pixi-info project-root)))

(defun pixi-name         (&optional project-root) "Workspace name from PROJECT-ROOT's manifest."     (alist-get 'name          (pixi--project project-root)))
(defun pixi-version      (&optional project-root) "Workspace version from PROJECT-ROOT's manifest."  (alist-get 'version       (pixi--project project-root)))
(defun pixi-manifest-path (&optional project-root) "Absolute manifest path reported by pixi."        (alist-get 'manifest_path (pixi--project project-root)))
(defun pixi-last-updated (&optional project-root) "Last-update timestamp string for PROJECT-ROOT."   (alist-get 'last_updated  (pixi--project project-root)))

(defun pixi-environments (&optional project-root)
  "Return the list of environment entries for PROJECT-ROOT."
  (alist-get 'environments_info (pixi-info project-root)))

(defun pixi-environment-names (&optional project-root)
  "Return the list of environment names declared in PROJECT-ROOT."
  (mapcar (lambda (env) (alist-get 'name env))
    (pixi-environments project-root)))

(defun pixi-environment (name &optional project-root)
  "Return the environment alist NAMED in PROJECT-ROOT, or nil if unknown."
  (seq-find (lambda (env) (equal name (alist-get 'name env)))
    (pixi-environments project-root)))

(defun pixi-tasks (&optional project-root)
  "Return the deduped union of task names across PROJECT-ROOT's environments."
  (seq-uniq
    (mapcan (lambda (env) (copy-sequence (alist-get 'tasks env)))
      (pixi-environments project-root))
    #'equal))

(defun pixi-environment-tasks (name &optional project-root)
  "Return task names scoped to environment NAME in PROJECT-ROOT."
  (alist-get 'tasks (pixi-environment name project-root)))

(defun pixi-task-list-raw (&optional project-root environment)
  "Return raw `pixi task list --json' output for PROJECT-ROOT.
ENVIRONMENT, if non-nil, scopes the listing to that env."
  (pixi--json-call
    (append '("task" "list" "--json")
      (when environment (list "-e" environment)))
    project-root))

(defun pixi-tasks-detailed (&optional project-root environment)
  "Flatten `pixi-task-list-raw' into a list of task alists.
Each task is decorated with `environment' and `feature' keys naming the
environment + feature it belongs to."
  (mapcan
    (lambda (env-entry)
      (let ((env-name (alist-get 'environment env-entry)))
        (mapcan
          (lambda (feature)
            (let ((feature-name (alist-get 'name feature)))
              (mapcar
                (lambda (task)
                  (append task
                    (list (cons 'environment env-name)
                      (cons 'feature     feature-name))))
                (alist-get 'tasks feature))))
          (alist-get 'features env-entry))))
    (pixi-task-list-raw project-root environment)))

(defun pixi-task (name &optional environment project-root)
  "Find the task NAMED (optionally scoped to ENVIRONMENT) in PROJECT-ROOT.
Returns nil when no task matches."
  (seq-find (lambda (task)
              (and (equal name (alist-get 'name task))
                (or (null environment)
                  (equal environment (alist-get 'environment task)))))
    (pixi-tasks-detailed project-root environment)))

(defun pixi-packages (&optional environment project-root)
  "Return parsed `pixi list --json' for ENVIRONMENT in PROJECT-ROOT."
  (pixi--json-call
    (append '("list" "--json")
      (when environment (list "-e" environment)))
    project-root))

(defun pixi--task-depends-on (task)
  "Return TASK's `depends_on' entries as a flat list of task names."
  (mapcar (lambda (dep) (alist-get 'task_name dep))
    (alist-get 'depends_on task)))

(defun pixi--compile (label args &optional project-root)
  "Run pixi with ARGS via `compile' in `*pixi:LABEL*' (scoped to PROJECT-ROOT)."
  (let* ((command (mapconcat #'shell-quote-argument
                    (append (list (pixi--executable))
                      args
                      (pixi--manifest-args project-root))
                    " "))
          (compilation-buffer-name-function
            (lambda (_mode) (format "*pixi:%s*" label))))
    (compile command)))

(defun pixi-clean (&optional environment)
  "Run `pixi clean' on the workspace.
With \\[universal-argument], prompt for an ENVIRONMENT to clean instead of all."
  (declare (modes pixi-mode))
  (interactive
    (when current-prefix-arg
      (list (completing-read "Clean environment: "
              (pixi-environment-names) nil t))))
  (when (yes-or-no-p
          (if environment
            (format "Clean pixi environment `%s'? " environment)
            "Clean ALL pixi environments in this workspace? "))
    (pixi--compile
      (or environment "all")
      (append '("clean")
        (when environment (list "-e" environment))))))

(defun pixi-tree (&optional environment regex)
  "Show `pixi tree' output in a compile buffer.
With \\[universal-argument], prompt for an ENVIRONMENT and a filter REGEX."
  (declare (modes pixi-mode))
  (interactive
    (when current-prefix-arg
      (list (completing-read "Environment: "
              (pixi-environment-names) nil t)
        (read-string "Filter regex (empty for all): "))))
  (pixi--compile
    (concat "tree" (when environment (concat ":" environment)))
    (append '("tree")
      (when environment (list "-e" environment))
      (when (and regex (not (string-empty-p regex)))
        (list regex)))))

(defun pixi--task-list-grouped ()
  "Return `pixi-tasks-detailed' collapsed by (FEATURE . NAME).
Each entry is ((FEATURE . NAME) TASK-ALIST ENV1 ENV2 ...) with envs in
first-seen order across the detailed task list."
  (let ((groups (make-hash-table :test 'equal))
         (order  nil))
    (dolist (task (pixi-tasks-detailed))
      (let* ((feature (alist-get 'feature     task))
              (name    (alist-get 'name        task))
              (env     (alist-get 'environment task))
              (key     (cons feature name))
              (entry   (gethash key groups)))
        (if entry
          (setcdr entry (append (cdr entry) (list env)))
          (puthash key (cons task (list env)) groups)
          (push key order))))
    (mapcar (lambda (key) (cons key (gethash key groups))) (nreverse order))))

(defun pixi--visible-envs (envs)
  "Return ENVS with `pixi-task-list-hide-envs' filtered out, alphabetized."
  (sort (seq-remove (lambda (env) (member env pixi-task-list-hide-envs))
          envs)
    #'string<))

(defun pixi--task-row-title (task envs)
  "Render a single dashboard row for TASK + ENVS using the visible columns.
The whole line carries a `pixi-task' text property naming the task, so
`pixi-run-task' can resolve the row at point."
  (propertize
    (mapconcat
      (lambda (key)
        (let* ((spec  (pixi--column-spec key))
                (cell  (funcall (plist-get spec :cell) task envs))
                (width (plist-get spec :width)))
          (pixi--pad-cell cell width)))
      pixi-task-list-visible-columns
      "")
    'pixi-task (alist-get 'name task)))

(defun pixi--task-header-row ()
  "Render the dashboard's column-header row from `pixi-task-list-visible-columns'."
  (mapconcat
    (lambda (key)
      (let* ((spec  (pixi--column-spec key))
              (label (plist-get spec :header))
              (width (plist-get spec :width)))
        (propertize (pixi--pad-cell label width) 'face 'vui-muted)))
    pixi-task-list-visible-columns
    ""))

(vui-defcomponent pixi--task-overview ()
  "Dashboard component: column header followed by one row per grouped task."
  :render
  (vui-vstack
    (vui-text (pixi--task-header-row))
    (mapcar (pcase-lambda (`(,_key ,task . ,envs))
              (vui-text (pixi--task-row-title task envs)))
      (pixi--task-list-grouped))))

(defun pixi-refresh ()
  "Invalidate the `pixi info' cache, then re-render the dashboard."
  (declare (modes pixi-mode))
  (interactive)
  (pixi-info-invalidate)
  (vui-refresh))

(defun pixi--task-names ()
  "Return all unique task names."
  (mapcar (lambda (row) (cdr (car row)))
    (pixi--task-list-grouped)))

(defun pixi-run-task (name)
  "Run pixi task NAME in a `*pixi:NAME*' compile buffer.
When called from the `pixi' dashboard with point on a row, NAME defaults
to that row's task (read from the `pixi-task' text property).  Otherwise
prompt with completion.  The output buffer is displayed but does not
steal focus from the current window."
  (declare (modes pixi-mode))
  (interactive
    (list (or (get-text-property (point) 'pixi-task)
            (completing-read "Task: " (pixi--task-names) nil t))))
  (save-selected-window
    (pixi--compile name (list "run" name))))

(defvar pixi-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "g") #'pixi-refresh)
    (define-key map (kbd "r") #'pixi-run-task)
    map)
  "Keymap for `pixi-mode' buffers.")

(declare-function evil-define-key "evil-core")
(with-eval-after-load 'evil
  (evil-define-key 'normal pixi-mode-map
    (kbd "g") #'pixi-refresh
    (kbd "r") #'pixi-run-task))

(define-derived-mode pixi-mode vui-mode "pixi"
  "Major mode for the `pixi' dashboard.")
(put 'pixi-mode 'completion-predicate #'ignore)

(defun pixi--buffer-name ()
  "Return `*pixi:NAME@VERSION*' when in a workspace, falling back to `*pixi*'."
  (let* ((info     (ignore-errors (pixi-info)))
          (project  (alist-get 'project_info info))
          (name     (alist-get 'name project))
          (version  (alist-get 'version project)))
    (if (and name version)
      (format "*pixi:%s@%s*" name version)
      "*pixi*")))

(defun pixi--task-list-set-mode-line ()
  "Set `mode-name' to a colored CLI version + env/task counts + platform line."
  (when-let ((info (ignore-errors (pixi-info))))
    (let* ((cli-ver    (alist-get 'version info))
            (platform   (alist-get 'platform info))
            (env-count  (length (alist-get 'environments_info info)))
            (task-count (length (pixi-tasks))))
      (setq mode-name
        (list " "
          (propertize (format "v%s" (or cli-ver "?"))
            'face 'vui-success)
          "  "
          (nerd-icons-codicon "nf-cod-json" :face 'vui-heading-5)
          " "
          (propertize (number-to-string env-count) 'face 'vui-muted)
          "  "
          (nerd-icons-codicon "nf-cod-play" :face 'vui-warning)
          " "
          (propertize (number-to-string task-count) 'face 'vui-muted)
          "  "
          (pixi--platform-icon platform 'vui-heading-2)
          " "
          (propertize (or platform "?") 'face 'vui-muted))))))

(defun pixi ()
  "Open the `*pixi:NAME@VERSION*' dashboard for the current workspace."
  (interactive)
  (let* ((buffer-name (pixi--buffer-name))
          (buffer (get-buffer-create buffer-name)))
    (with-current-buffer buffer
      (unless (derived-mode-p 'pixi-mode)
        (pixi-mode)))
    (vui-mount (vui-component 'pixi--task-overview) buffer-name)
    (with-current-buffer buffer
      (pixi--task-list-set-mode-line))))

(provide 'pixi)

;;; pixi.el ends here
