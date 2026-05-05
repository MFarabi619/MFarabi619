;;; init.el -*- lexical-binding: t; -*-
;;
;; Doom modules manifest. Kept minimal: just enough to render
;; org-mode beautifully and let visitors navigate. No tools that
;; could escape the sandbox (no shell, no vterm, no eshell).

(doom! :ui
       doom
       doom-dashboard
       hl-todo
       indent-guides
       modeline
       ophints
       (popup +defaults)
       vc-gutter
       workspaces

       :editor
       (evil +everywhere)
       file-templates
       fold

       :emacs
       dired
       undo
       vc

       :checkers
       syntax

       :lang
       (org +pretty)
       markdown
       emacs-lisp)
