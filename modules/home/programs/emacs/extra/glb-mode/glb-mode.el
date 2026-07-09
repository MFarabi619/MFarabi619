;;; glb-mode.el --- Preview .glb models rendered with f3d  -*- lexical-binding: t -*-

;; Copyright © 2026 Mumtahin Farabi <mfarabi619@gmail.com>

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; URL: https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/glb-mode
;; Keywords: tools, graphics, 3d
;; Version: 0.0.1
;; Package-Requires: ((emacs "29.1"))

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
;; WIP
;;
;;; Code:

(require 'seq)
(require 'bindat)
(require 'json)
(require 'filenotify)
(require 'image)

(defgroup glb ()
  "Preview glTF binary (.glb) models."
  :prefix "glb-"
  :group 'tools)

(defcustom glb-command "f3d"
  "Executable used to render a .glb model to an image."
  :type 'string)

(defcustom glb-large-file-threshold nil
  "Value of `large-file-warning-threshold' when visiting a .glb file.
The default nil bypasses the large-file prompt, since .glb models
are expected to be large.  Set to a byte count to warn above that
size instead."
  :type '(choice (const :tag "Never warn" nil) integer))

(defcustom glb-show-metadata nil
  "When non-nil, show parsed glTF metadata below the rendered image."
  :type 'boolean)

(defface glb-title '((t :inherit bold :height 1.2))
  "Face for the model name heading.")

(defface glb-label '((t :inherit font-lock-keyword-face))
  "Face for dashboard field labels.")

(defvar-local glb--file nil
  "Absolute path of the .glb rendered in this buffer.")

(defvar-local glb--watch nil
  "File-notify descriptor watching `glb--file', or nil.")

(defvar-local glb--image-file nil
  "Temporary PNG currently displayed, or nil.")

(defvar-local glb--process nil
  "Running render process, or nil.")

;;;; glTF binary container

(defconst glb--magic #x46546C67
  "Little-endian u32 for the ASCII magic \"glTF\".")

(defconst glb--json-tag #x4E4F534A
  "Little-endian u32 for the ASCII chunk tag \"JSON\".")

(defconst glb--header-type
  (bindat-type (magic uint 32 t)
    (version uint 32 t)
    (total-length uint 32 t)
    (json-length uint 32 t)
    (json-tag uint 32 t))
  "Bindat spec for the glb header and the first chunk's length and tag.")

(defun glb--slurp-bytes (file from to)
  "Return raw bytes in range [FROM, TO) of FILE as a unibyte string."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file nil from to)
    (buffer-string)))

(defun glb-read-metadata (file)
  "Return the glTF JSON embedded in FILE parsed as an alist.
Signal a `user-error' when FILE is not a version 2 glTF binary.
Only the header and JSON chunk are read, never the mesh chunk."
  (let ((header-bytes (glb--slurp-bytes file 0 20)))
    (unless (= (length header-bytes) 20)
      (user-error "%s is too small to be a glTF binary (.glb) file"
        (file-name-nondirectory file)))
    (let ((header (bindat-unpack glb--header-type header-bytes)))
      (unless (and (= (bindat-get-field header 'magic) glb--magic)
                (= (bindat-get-field header 'json-tag) glb--json-tag))
        (user-error "%s is not a glTF binary (.glb) file"
          (file-name-nondirectory file)))
      (let ((json-length (bindat-get-field header 'json-length)))
        (json-parse-string
          (decode-coding-string (glb--slurp-bytes file 20 (+ 20 json-length)) 'utf-8)
          :object-type 'alist :array-type 'list)))))

;;;; Metadata display

(defun glb--count (gltf key)
  "Return the number of entries under KEY in parsed GLTF."
  (length (alist-get key gltf)))

(defun glb--insert-metadata ()
  "Insert the parsed glTF metadata of `glb--file'."
  (let* ((gltf (glb-read-metadata glb--file))
          (asset (alist-get 'asset gltf)))
    (insert (propertize (file-name-nondirectory glb--file) 'face 'glb-title) "\n")
    (insert (propertize
              (format "glTF %s · %s · %s\n\n"
                (or (alist-get 'version asset) "?")
                (or (alist-get 'generator asset) "unknown")
                (file-size-human-readable
                  (file-attribute-size (file-attributes glb--file))))
              'face 'font-lock-comment-face))
    (dolist (row `(("Nodes"      ,(glb--count gltf 'nodes))
                    ("Meshes"     ,(glb--count gltf 'meshes))
                    ("Materials"  ,(glb--count gltf 'materials))
                    ("Textures"   ,(glb--count gltf 'textures))
                    ("Images"     ,(glb--count gltf 'images))
                    ("Animations" ,(glb--count gltf 'animations))
                    ("Accessors"  ,(glb--count gltf 'accessors))))
      (insert (format "  %s %s\n"
                (propertize (string-pad (car row) 12) 'face 'glb-label)
                (cadr row))))
    (let ((names (delq nil (mapcar (lambda (node) (alist-get 'name node))
                            (alist-get 'nodes gltf)))))
      (when names
        (insert "\n" (propertize "  Scene\n" 'face 'glb-label))
        (dolist (name names) (insert (format "    %s\n" name)))))))

;;;; Rendering

(defun glb--image-width ()
  "Return the render width in pixels, sized to the window."
  (max 400 (- (window-body-width nil t) (frame-char-width))))

(defun glb--delete-image ()
  "Delete the temporary PNG displayed in this buffer, if any."
  (when (and glb--image-file (file-exists-p glb--image-file))
    (delete-file glb--image-file))
  (setq glb--image-file nil))

(defun glb--kill-render ()
  "Kill any in-flight render process."
  (when (process-live-p glb--process)
    (delete-process glb--process))
  (setq glb--process nil))

(defun glb--layout (png &optional failed)
  "Lay out the buffer with the render PNG, plus metadata when enabled.
With no PNG show a failure note when FAILED is non-nil."
  (let ((inhibit-read-only t))
    (erase-buffer)
    (cond
     (png (insert-image (create-image png nil nil :max-width (glb--image-width)))
          (insert "\n\n"))
     (failed (insert (propertize
                      (format "  %s: render failed\n\n"
                        (file-name-nondirectory glb--file))
                      'face 'error))))
    (when glb-show-metadata
      (condition-case err
        (glb--insert-metadata)
        (error (insert (format "Cannot read %s:\n  %s"
                         glb--file (error-message-string err))))))
    (set-buffer-modified-p nil)
    (goto-char (point-min))))

(defun glb--render-sentinel (png buffer)
  "Return a sentinel to display PNG in BUFFER after the render exits."
  (lambda (process _event)
    (when (and (memq (process-status process) '(exit signal))
            (buffer-live-p buffer))
      (with-current-buffer buffer
        (setq glb--process nil)
        (if (and (eq (process-exit-status process) 0)
              (file-exists-p png)
              (> (file-attribute-size (file-attributes png)) 0))
          (progn
            (glb--delete-image)
            (setq glb--image-file png)
            (glb--layout png))
          (ignore-errors (delete-file png))
          (glb--layout nil t))))))

(defun glb--start-render ()
  "Render `glb--file' asynchronously, or lay out directly when it cannot."
  (glb--kill-render)
  (cond
   ((not (display-graphic-p)) (glb--layout nil))
   ((not (executable-find glb-command)) (glb--layout nil t))
   (t (let* ((width (glb--image-width))
              (png (make-temp-file "glb-render-" nil ".png")))
        (setq glb--process
          (make-process
            :name "glb-render"
            :noquery t
            :command (list glb-command glb--file "--output" png
                       (format "--resolution=%d,%d" width (round (* width 0.7))))
            :sentinel (glb--render-sentinel png (current-buffer))))))))

(defun glb--render ()
  "Render `glb--file', keeping any current image on screen until it is ready."
  (unless (and glb--image-file (file-exists-p glb--image-file))
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (propertize "  Rendering…\n\n" 'face 'font-lock-comment-face))
      (when glb-show-metadata (ignore-errors (glb--insert-metadata)))
      (set-buffer-modified-p nil)
      (goto-char (point-min))))
  (glb--start-render))

;;;; Live reload

(defun glb-refresh (&rest _)
  "Re-render `glb--file'."
  (interactive nil glb-mode)
  (when (and glb--file (file-exists-p glb--file))
    (glb--render)))

(defun glb--watch-file ()
  "Watch `glb--file' and refresh when the model is rewritten."
  (glb--unwatch)
  (when (and glb--file (file-exists-p glb--file))
    (let ((buffer (current-buffer)))
      (setq glb--watch
        (file-notify-add-watch
          glb--file '(change)
          (lambda (event)
            (when (and (buffer-live-p buffer)
                    (memq (nth 1 event) '(changed created renamed)))
              (with-current-buffer buffer (glb-refresh)))))))))

(defun glb--unwatch ()
  "Stop watching `glb--file'."
  (when glb--watch
    (file-notify-rm-watch glb--watch)
    (setq glb--watch nil)))

;;;; Mode

(defvar-keymap glb-mode-map
  :doc "Keymap for `glb-mode'."
  "g" #'glb-refresh)

;;;###autoload
(define-derived-mode glb-mode special-mode "glb-mode"
  "Preview the visited glTF binary model, rendered by `glb-command'."
  (buffer-disable-undo)
  (setq-local undo-tree-auto-save-history nil)
  (setq glb--file buffer-file-name)
  (setq-local revert-buffer-function #'glb-refresh)
  (add-hook 'kill-buffer-hook #'glb--kill-render nil t)
  (add-hook 'kill-buffer-hook #'glb--unwatch nil t)
  (add-hook 'kill-buffer-hook #'glb--delete-image nil t)
  (glb--render)
  (glb--watch-file))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.glb\\'" . glb-mode))

(defun glb--bypass-large-file-warning (wrapped-function size op-type filename &rest args)
  "Apply `glb-large-file-threshold' when FILENAME is a .glb.
SIZE, OP-TYPE, FILENAME and ARGS are the arguments to
WRAPPED-FUNCTION, which is `abort-if-file-too-large'."
  (let ((large-file-warning-threshold
         (if (and filename (string-suffix-p ".glb" filename t))
             glb-large-file-threshold
           large-file-warning-threshold)))
    (apply wrapped-function size op-type filename args)))

;;;###autoload
(advice-add 'abort-if-file-too-large :around #'glb--bypass-large-file-warning)

(provide 'glb-mode)

;;; glb-mode.el ends here
