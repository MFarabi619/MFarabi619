;;; microvisor.el --- Project task registry  -*- lexical-binding: t -*-

;; Copyright (C) 2026 Mumtahin Farabi

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; URL: https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/microvisor
;; Keywords: lisp, tools, convenience
;; Version: 0.0.1
;; Package-Requires: ((emacs "29.1") (compile-multi "0.7") (nerd-icons "0.1"))

;; This file is not part of GNU Emacs.

;;; Commentary:
;; Loader and shared slug; producers self-register through `microvisor-task'.
;;; Code:

(require 'seq)
(require 'subr-x)

(let* ((this-dir   (file-name-directory (or load-file-name buffer-file-name)))
       (parent-dir (file-name-directory (directory-file-name this-dir))))
  (add-to-list 'load-path this-dir)
  (dolist (subdir '("pixi" "loco-rs" "dioxus" "west" "zephyr" "pio-mode" "mcumgr" "tailscale" "kanban" "ros2" "board" "process-compose" "glb-mode"))
    (let ((sibling (expand-file-name subdir parent-dir)))
      (when (file-directory-p sibling)
        (add-to-list 'load-path sibling)))))

(load "west"       'noerror 'nomessage)
(load "kanban"     'noerror 'nomessage)
(load "zephyr"     'noerror 'nomessage)
(load "mcumgr"     'noerror 'nomessage)
(load "dioxus"     'noerror 'nomessage)
(load "loco-rs"    'noerror 'nomessage)
(load "pio-mode"   'noerror 'nomessage)
(load "tailscale"  'noerror 'nomessage)
(load "ros2"       'noerror 'nomessage)
(load "board"      'noerror 'nomessage)
(load "process-compose" 'noerror 'nomessage)
(load "glb-mode"        'noerror 'nomessage)

(defgroup microvisor ()
  "Project task and service orchestration."
  :prefix "microvisor-"
  :group 'tools)

;;; Task identity

(defun microvisor--slug (name)
  "Return NAME as a handle segment: lowercase, punctuation to hyphens."
  (string-trim (replace-regexp-in-string "[^a-z0-9_]+" "-" (downcase name))
               "-" "-"))

(provide 'microvisor)

(require 'microvisor-process-compose)
(require 'microvisor-compile-multi)

;;; microvisor.el ends here
