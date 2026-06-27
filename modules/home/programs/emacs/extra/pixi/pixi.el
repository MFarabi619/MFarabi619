;;; pixi.el --- Pixi workspace integration for GNU Emacs  -*- lexical-binding: t -*-

;; Copyright (C) 2026 Mumtahin Farabi

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; Keywords: lisp, tools

;; This file is not part of GNU Emacs.

;;; Code:

(require 'json)
(require 'map)
(require 'pcase)
(require 'nerd-icons)
(require 'vui-components)

(defgroup pixi ()
  "Pixi workspace integration."
  :prefix "pixi-"
  :group 'tools)

(defface pixi-task-list-task
  '((t :inherit vui-heading-1))
  "Face for the TASK column in `pixi-task-list'."
  :group 'pixi)

(defface pixi-task-list-env
  '((t :inherit vui-muted :box (:line-width -1 :color nil :style nil)))
  "Pill face for the ENV column in `pixi-task-list'."
  :group 'pixi)

(defface pixi-task-list-dep
  '((t :inherit vui-muted :box (:line-width -1 :color nil :style nil)))
  "Pill face for entries in the DEPS column of `pixi-task-list'."
  :group 'pixi)

(defun pixi--pill (text face)
  (propertize (format " %s " text) 'face face))

(defcustom pixi-task-list-hide-envs '("default")
  "Environment names to hide from the ENVS column in `pixi-task-list'.
The default environment is implicit in the TUI, so suppress it as visual noise."
  :type '(repeat string)
  :group 'pixi)

(defconst pixi--platform-icons
  '(("osx"   . ("nf-fa-apple"   . nerd-icons-faicon))
    ("linux" . ("nf-fa-linux"   . nerd-icons-faicon))
    ("win"   . ("nf-fa-windows" . nerd-icons-faicon))))

(defun pixi--platform-icon (platform face)
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
  (or pixi-executable (executable-find "pixi") "pixi"))

(defun pixi-p (&optional directory)
  (let ((dir (or directory default-directory)))
    (or (file-exists-p (expand-file-name "pixi.toml" dir))
        (pixi--pyproject-has-pixi-p
         (expand-file-name "pyproject.toml" dir)))))

(defun pixi--pyproject-has-pixi-p (path)
  (and (file-exists-p path)
       (with-temp-buffer
         (insert-file-contents path)
         (goto-char (point-min))
         (re-search-forward "^\\[tool\\.pixi\\(\\.\\|\\]\\)" nil t))))

(defun pixi-root (&optional directory)
  (locate-dominating-file (or directory default-directory) #'pixi-p))

(defun pixi-in-project-p (&optional directory)
  (and (pixi-root directory) t))

(defun pixi-manifest-file (&optional project-root)
  (when-let ((root (or project-root (pixi-root))))
    (let ((pixi-toml (expand-file-name "pixi.toml" root))
          (pyproject (expand-file-name "pyproject.toml" root)))
      (cond
       ((file-exists-p pixi-toml) pixi-toml)
       ((pixi--pyproject-has-pixi-p pyproject) pyproject)))))

(defun pixi--manifest-args (&optional project-root)
  (when-let ((manifest (pixi-manifest-file project-root)))
    (list "--manifest-path" manifest)))

(defun pixi--call (args &optional project-root)
  (with-temp-buffer
    (let* ((full-args (append args (pixi--manifest-args project-root)))
           (exit (apply #'call-process (pixi--executable) nil t nil full-args)))
      (unless (zerop exit)
        (error "pixi %s failed (exit %d): %s"
               (string-join args " ") exit (buffer-string)))
      (buffer-string))))

(defun pixi--json-call (args &optional project-root)
  (json-parse-string (pixi--call args project-root)
                     :object-type 'alist
                     :array-type 'list
                     :null-object nil
                     :false-object nil))

(defvar pixi--info-cache (make-hash-table :test 'equal))

(defun pixi-info (&optional project-root)
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
  (interactive)
  (if project-root
      (remhash project-root pixi--info-cache)
    (clrhash pixi--info-cache)))

(defun pixi-platform        (&optional project-root) (alist-get 'platform     (pixi-info project-root)))
(defun pixi-cli-version     (&optional project-root) (alist-get 'version      (pixi-info project-root)))
(defun pixi-cache-dir       (&optional project-root) (alist-get 'cache_dir    (pixi-info project-root)))
(defun pixi-auth-dir        (&optional project-root) (alist-get 'auth_dir     (pixi-info project-root)))
(defun pixi-virtual-packages (&optional project-root) (alist-get 'virtual_packages (pixi-info project-root)))

(defun pixi--project (&optional project-root)
  (alist-get 'project_info (pixi-info project-root)))

(defun pixi-name         (&optional project-root) (alist-get 'name          (pixi--project project-root)))
(defun pixi-version      (&optional project-root) (alist-get 'version       (pixi--project project-root)))
(defun pixi-manifest-path (&optional project-root) (alist-get 'manifest_path (pixi--project project-root)))
(defun pixi-last-updated (&optional project-root) (alist-get 'last_updated  (pixi--project project-root)))

(defun pixi-environments (&optional project-root)
  (alist-get 'environments_info (pixi-info project-root)))

(defun pixi-environment-names (&optional project-root)
  (mapcar (lambda (env) (alist-get 'name env))
          (pixi-environments project-root)))

(defun pixi-environment (name &optional project-root)
  (seq-find (lambda (env) (equal name (alist-get 'name env)))
            (pixi-environments project-root)))

(defun pixi-tasks (&optional project-root)
  (seq-uniq
   (mapcan (lambda (env) (copy-sequence (alist-get 'tasks env)))
           (pixi-environments project-root))
   #'equal))

(defun pixi-environment-tasks (name &optional project-root)
  (alist-get 'tasks (pixi-environment name project-root)))

(defun pixi-task-list-raw (&optional project-root environment)
  (pixi--json-call
   (append '("task" "list" "--json")
           (when environment (list "-e" environment)))
   project-root))

(defun pixi-tasks-detailed (&optional project-root environment)
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
  (seq-find (lambda (task)
              (and (equal name (alist-get 'name task))
                   (or (null environment)
                       (equal environment (alist-get 'environment task)))))
            (pixi-tasks-detailed project-root environment)))

(defun pixi-packages (&optional environment project-root)
  (pixi--json-call
   (append '("list" "--json")
           (when environment (list "-e" environment)))
   project-root))

(defun pixi--task-depends-on (task)
  (mapcar (lambda (dep) (alist-get 'task_name dep))
          (alist-get 'depends_on task)))

(defun pixi--compile (label args &optional project-root)
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

(defun pixi--task-list-entries ()
  (mapcar
   (pcase-lambda (`(,key ,task . ,envs))
     (let ((name    (alist-get 'name    task))
           (feature (alist-get 'feature task))
           (deps    (pixi--task-depends-on task))
           (cmd     (or (alist-get 'cmd task) "")))
       (list key
             (vector
              (propertize name 'face 'pixi-task-list-task)
              (propertize feature 'face 'vui-muted)
              (mapconcat (lambda (env) (pixi--pill env 'pixi-task-list-env))
                         (sort (seq-remove
                                (lambda (env)
                                  (member env pixi-task-list-hide-envs))
                                envs)
                               #'string<)
                         " ")
              (if deps
                  (mapconcat (lambda (dep) (pixi--pill dep 'pixi-task-list-dep))
                             deps " ")
                "")
              (propertize (string-clean-whitespace cmd) 'face 'default)))))
   (pixi--task-list-grouped)))

(defun pixi--task-list-set-mode-line ()
  (when-let ((info (ignore-errors (pixi-info))))
    (let* ((cli-ver    (alist-get 'version info))
           (project    (alist-get 'project_info info))
           (proj-name  (alist-get 'name project))
           (proj-ver   (alist-get 'version project))
           (platform   (alist-get 'platform info))
           (env-count  (length (alist-get 'environments_info info)))
           (task-count (length (pixi-tasks))))
      (setq mode-name
            (list " "
                  (nerd-icons-mdicon "nf-md-package_variant_closed"
                                     :face 'vui-success)
                  " "  (propertize (or cli-ver "?") 'face 'vui-muted)
                  "  " (propertize (or proj-name "?") 'face 'vui-heading-1)
                  (propertize "@" 'face 'vui-muted)
                  (propertize (or proj-ver "?") 'face 'vui-muted)
                  "  "
                  (nerd-icons-mdicon "nf-md-cube_outline" :face 'vui-muted)
                  " "  (propertize (number-to-string env-count)  'face 'vui-muted)
                  "  "
                  (nerd-icons-mdicon "nf-md-lightning_bolt" :face 'vui-muted)
                  " "  (propertize (number-to-string task-count) 'face 'vui-muted)
                  "  "
                  (pixi--platform-icon platform 'vui-muted)
                  " "  (propertize (or platform "?") 'face 'vui-muted))))))

(defun pixi--task-list-refresh ()
  (setq tabulated-list-entries (pixi--task-list-entries))
  (pixi--task-list-set-mode-line))

(defvar pixi-task-list-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map tabulated-list-mode-map)
    (define-key map (kbd "r") #'revert-buffer)
    map))

(with-eval-after-load 'evil
  (evil-define-key 'normal pixi-task-list-mode-map
    (kbd "r") #'revert-buffer))

(define-derived-mode pixi-task-list-mode tabulated-list-mode "pixi-task-list"
  "Major mode for the `pixi-task-list' buffer."
  (setq tabulated-list-format
        [("TASK"    14 t)
         ("FEATURE" 12 t)
         ("ENVS"    22 t)
         ("DEPS"    16 t)
         ("CMD"      0 t)]
        tabulated-list-sort-key (cons "TASK" nil))
  (add-hook 'tabulated-list-revert-hook #'pixi--task-list-refresh nil t)
  (tabulated-list-init-header))
(put 'pixi-task-list-mode 'completion-predicate #'ignore)

(defun pixi-task-list ()
  "Show all tasks across pixi environments."
  (interactive)
  (let ((buffer (get-buffer-create "*pixi-task-list*")))
    (with-current-buffer buffer
      (pixi-task-list-mode)
      (pixi--task-list-refresh)
      (tabulated-list-print))
    (pop-to-buffer buffer)))

(provide 'pixi)

;;; pixi.el ends here
