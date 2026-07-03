;;; microvisor.el --- Project task and service orchestration  -*- lexical-binding: t -*-

;; Copyright (C) 2026 Mumtahin Farabi

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; URL: https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/microvisor
;; Keywords: lisp, tools, convenience
;; Version: 0.0.1
;; Package-Requires: ((emacs "29.1") (compile-multi "0.7") (nerd-icons "0.1"))

;; This file is not part of GNU Emacs.

;;; Commentary:

;;; Code:

(require 'seq)
(require 'cl-lib)
(require 'subr-x)
(require 'compile-multi)
(require 'nerd-icons)

(let* ((this-dir   (file-name-directory (or load-file-name buffer-file-name)))
       (parent-dir (file-name-directory (directory-file-name this-dir))))
  (dolist (subdir '("pixi" "loco-rs" "dioxus" "west" "zephyr" "pio-mode" "mcumgr" "tailscale" "kanban" "ros2" "board" "process-compose"))
    (let ((sibling (expand-file-name subdir parent-dir)))
      (when (file-directory-p sibling)
        (add-to-list 'load-path sibling)))))

(load "pixi"       'noerror 'nomessage)
(load "west"       'noerror 'nomessage)
(load "kanban"     'noerror 'nomessage)
(load "zephyr"     'noerror 'nomessage)
(load "mcumgr"     'noerror 'nomessage)
(load "dioxus"     'noerror 'nomessage)
(load "loco-rs"    'noerror 'nomessage)
(load "pio-mode"   'noerror 'nomessage)
(load "tailscale"  'noerror 'nomessage)
(load "ros2" 'noerror 'nomessage)
(load "board"      'noerror 'nomessage)
(load "process-compose" 'noerror 'nomessage)

(declare-function process-compose-declare "process-compose" (declaration))
(declare-function process-compose-reconcile "process-compose" ())
(declare-function process-compose-state "process-compose" (name))

(defgroup microvisor ()
  "Project task and service orchestration."
  :prefix "microvisor-"
  :group 'tools)

(defcustom microvisor-icon-faces
  '(("emacs"      . nerd-icons-dpurple)
    ("dioxus"     . nerd-icons-blue)
    ("cargo"      . nerd-icons-orange)
    ("west"       . nerd-icons-purple)
    ("platformio" . nerd-icons-yellow)
    ("pulumi"     . nerd-icons-purple)
    ("pkg"        . nerd-icons-red)
    ("apt"        . nerd-icons-dred)
    ("pacman"     . nerd-icons-blue)
    ("guix"       . nerd-icons-yellow)
    ("pkg_add"    . nerd-icons-yellow)
    ("nix"        . nerd-icons-lblue))
  "Alist mapping `:annotation' prefix words to nerd-icons faces.
The prefix is the first whitespace-separated word of an entry's
`:annotation' string; the last word is taken as the user-provided
icon glyph and rendered in the looked-up face."
  :type '(alist :key-type string :value-type symbol)
  :group 'microvisor)

(defcustom microvisor-annotation-show-label nil
  "When non-nil, show the annotation label text beside its icon."
  :type 'boolean
  :group 'microvisor)

(defun microvisor-icon-face (prefix)
  "Return the face for annotation PREFIX, or nil if not registered."
  (alist-get prefix microvisor-icon-faces nil nil #'equal))

(setq compile-multi-annotate-cmds        t
      compile-multi-annotate-limit       10
      compile-multi-annotate-string-cmds nil
      compile-multi-group-cmds           'group-and-replace)

(defcustom microvisor-task-command-order
  '("update" "patch" "run" "test" "build" "flash")
  "Preferred ordering of `compile-multi' command verbs; unlisted sort last."
  :type '(repeat string)
  :group 'microvisor)

(defun microvisor--task-sort-key (candidate &optional recent recent-group)
  "Sort key for CANDIDATE.
Floats RECENT-GROUP first and the RECENT command atop it; otherwise orders by
group, `microvisor-task-command-order' verb, then target."
  (if (string-match "\\`\\(.*?:\\). \\([a-z][a-z-]*\\)\\(?: \\(.*\\)\\)?\\'" candidate)
      (let* ((group     (match-string 1 candidate))
             (verb      (match-string 2 candidate))
             (target    (or (match-string 3 candidate) ""))
             (rank      (or (cl-position verb microvisor-task-command-order :test #'equal)
                            (length microvisor-task-command-order)))
             (group-pri (if (and recent-group (equal group recent-group)) 0 1))
             (item-pri  (if (and recent (equal (substring-no-properties candidate) recent))
                          0 1)))
        (format "%d%s %d%d %s %s" group-pri group item-pri rank verb target))
    candidate))

(defun microvisor-sort-tasks (candidates)
  "Order CANDIDATES by group + command verb, floating the most recent run first.
The most recent `compile-multi-history' entry's group is placed first, with
that command atop it."
  (let* ((recent       (when compile-multi-history
                         (substring-no-properties (car compile-multi-history))))
         (recent-group (when (and recent (string-match "\\`\\(.*?:\\)" recent))
                         (match-string 1 recent))))
    (sort (copy-sequence candidates)
          (lambda (a b)
            (string-lessp (microvisor--task-sort-key a recent recent-group)
                          (microvisor--task-sort-key b recent recent-group))))))

(setf (alist-get 'display-sort-function
                 (alist-get 'compile-multi completion-category-overrides))
      #'microvisor-sort-tasks)

(defun microvisor--icon-glyph-p (word)
  "Non-nil when WORD is a single nerd-icons glyph (Private Use Area)."
  (and (= (length word) 1) (>= (aref word 0) #xE000)))

(defun microvisor--annotation-function (original-function task)
  "Right-align the `:annotation' of TASK as an optional label plus an icon.
An annotation of `LABEL... ICON' colors ICON via the LABEL face key; a lone
glyph renders icon-only (caller owns its face).  Else call ORIGINAL-FUNCTION."
  (if-let* ((annotation-text (plist-get (cdr task) :annotation))
            ((stringp annotation-text))
            ((fboundp 'nerd-icons-icon-for-file))
            (words (split-string (string-trim-right annotation-text)
                                 "[[:space:]]+" t))
            (spec (let ((face (and (> (length words) 1)
                                   (microvisor-icon-face (car words)))))
                    (cond
                     ((and (= (length words) 1)
                           (microvisor--icon-glyph-p (car words)))
                      (cons "" (car words)))
                     (face
                      (cons (string-join (butlast words) " ")
                            (propertize (car (last words)) 'face face)))))))
      (let* ((label (if microvisor-annotation-show-label (car spec) ""))
             (icon  (cdr spec))
             (truncated (if (and compile-multi-annotate-limit
                                 (> (length label) compile-multi-annotate-limit))
                            (concat (truncate-string-to-width
                                     label compile-multi-annotate-limit)
                                    "…")
                          label))
             (rendered (if (string-empty-p label)
                           icon
                         (concat (propertize truncated 'face 'completions-annotations)
                                 " " icon)))
             (width (string-width (substring-no-properties rendered))))
        (concat " "
                (propertize " " 'display
                            `(space :align-to (- right ,(+ 1 width))))
                rendered))
    (funcall original-function task)))

(defun microvisor--split-title (plain-title)
  "Split PLAIN-TITLE on the first colon into (GROUP . DISPLAY).
With no colon, both halves are PLAIN-TITLE."
  (if (string-match "\\`\\([^:]+\\):\\(.*\\)\\'" plain-title)
      (let ((group   (match-string 1 plain-title))
            (display (match-string 2 plain-title)))
        (cons (string-trim group) (string-trim display)))
    (cons plain-title plain-title)))

(defun microvisor--process-compose-slug (display-name)
  "Return DISPLAY-NAME as a handle segment: lowercase, punctuation to hyphens."
  (string-trim (replace-regexp-in-string "[^a-z0-9_]+" "-"
                                         (downcase display-name))
               "-" "-"))

(defun microvisor--plain-label (label)
  "Return LABEL with icon glyphs and padding stripped."
  (string-trim (replace-regexp-in-string "[^[:ascii:]]+" "" label)))

(defun microvisor--task-process-state (plain-title)
  "Return the process-compose state for the task titled PLAIN-TITLE, or nil."
  (when (fboundp 'process-compose-state)
    (let* ((split (microvisor--split-title plain-title))
           (namespace (microvisor--plain-label (car split)))
           (name (concat namespace "-"
                         (microvisor--process-compose-slug
                          (microvisor--plain-label (cdr split))))))
      (process-compose-state name))))

(defun microvisor--running-face-function (original-function tasks)
  "Around-advice for ORIGINAL-FUNCTION applied to TASKS.
Renders the title of any `:process-compose' task whose process is running
in the `success' face."
  (mapcar
   (lambda (task)
     (let* ((title       (car task))
            (plist       (cdr task))
            (plain-title (substring-no-properties title))
            (state       (and (plist-get plist :process-compose)
                              (microvisor--task-process-state plain-title))))
       (if (and state (gethash "is_running" state))
           (let ((title* (copy-sequence title)))
             (add-face-text-property 0 (length title*) 'success t title*)
             (cons title* plist))
         task)))
   (funcall original-function tasks)))

(defun microvisor--declare-process-compose-service (task)
  "Declare `compile-multi' TASK as a process-compose process."
  (let* ((title (car task))
         (plist (cdr task))
         (flag (plist-get plist :process-compose))
         (plain-title (substring-no-properties title))
         (command (or (get-text-property 0 'compile-multi--task title)
                      (plist-get plist :command)))
         (split (microvisor--split-title plain-title))
         (namespace (microvisor--plain-label (car split)))
         (display-name (microvisor--plain-label (cdr split))))
    (process-compose-declare
     (append (list :name (concat namespace "-"
                                 (microvisor--process-compose-slug display-name))
                   :namespace namespace
                   :display-name display-name
                   :command command)
             (and (listp flag) flag)))))

(defun microvisor-register-process-compose-services (&optional config)
  "Declare every `:process-compose' task in CONFIG, then reconcile.
CONFIG defaults to `compile-multi-dir-local-config'."
  (when (fboundp 'process-compose-declare)
    (let ((compile-multi-dir-local-config
           (or config compile-multi-dir-local-config)))
      (dolist (task (seq-filter
                     (lambda (task) (plist-get (cdr task) :process-compose))
                     (thread-first (compile-multi--config-tasks)
                                   (compile-multi--fill-tasks)
                                   (compile-multi--add-properties))))
        (microvisor--declare-process-compose-service task))
      (process-compose-reconcile))))

(defun microvisor--maybe-register-services ()
  "Register declared services when a dir-local compile-multi config is present.
Hook for `hack-local-variables-hook'."
  (when (bound-and-true-p compile-multi-dir-local-config)
    (microvisor-register-process-compose-services)))

(unless (advice-member-p #'microvisor--annotation-function
                         'compile-multi--annotation-function)
  (advice-add 'compile-multi--annotation-function
              :around #'microvisor--annotation-function))

(unless (advice-member-p #'microvisor--running-face-function
                         'compile-multi--add-properties)
  (advice-add 'compile-multi--add-properties
              :around #'microvisor--running-face-function))

(add-hook 'compilation-filter-hook #'ansi-color-compilation-filter)
(add-hook 'hack-local-variables-hook #'microvisor--maybe-register-services)

(provide 'microvisor)

;;; microvisor.el ends here
