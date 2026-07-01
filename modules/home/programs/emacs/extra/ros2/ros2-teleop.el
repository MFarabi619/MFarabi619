;;; ros2-teleop.el --- Teleop control grid for ros2 -*- lexical-binding: t -*-

;; Copyright © 2026 Mumtahin Farabi <mfarabi619@gmail.com>

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; URL: https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/ros2
;; Keywords: tools, robotics
;; Version: 0.0.1
;; Package-Requires: ((emacs "29.1") (vui "0.1"))

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
;; The teleop grid rendered in its own window: a 3x3 key layout
;; (u i o / j k l / m , .) where each key holds the (linear . angular) velocity
;; weights it publishes as a velocity command.  It is a `vui-table' vnode, so
;; vui measures each cell and keeps the wide arrow glyphs aligned.
;;
;; Emacs delivers key presses but no key releases, so there is no hold-to-move:
;; each press engages one key momentarily and `k' is the explicit stop.
;; Publishing is not wired up yet -- the grid highlights but does not drive.
;;
;;; Code:

(require 'vui)

(defgroup ros2-teleop ()
  "In-dashboard teleop control grid."
  :prefix "ros2-teleop-"
  :group 'tools)

(defface ros2-teleop-arrow '((t :inherit default))
  "Face for an idle direction arrow in the teleop grid."
  :group 'ros2-teleop)

(defface ros2-teleop-active '((t :inherit success :weight bold))
  "Face for the arrow of the currently engaged key."
  :group 'ros2-teleop)

(defface ros2-teleop-key '((t :inherit shadow))
  "Face for the key letter beside each arrow."
  :group 'ros2-teleop)

(defface ros2-teleop-border '((t :inherit shadow))
  "Face for the teleop grid's cell borders."
  :group 'ros2-teleop)

(defconst ros2-teleop--cells
  '(("u" "🢄"  0.7  0.7) ("i" "🢁"  1.0  0.0) ("o" "🢅"  0.7 -0.7)
     ("j" "🢀"  0.0  1.0) ("k" "○"   0.0  0.0) ("l" "🢂"  0.0 -1.0)
     ("m" "🢇" -0.7  0.7) ("," "🢃" -1.0  0.0) ("." "🢆" -0.7 -0.7))
  "The 3x3 teleop grid in row-major order.
Each cell is (KEY ARROW LINEAR ANGULAR): the key, its arrow glyph, and the
linear/angular velocity weights it contributes.")

(defun ros2-teleop--rows ()
  "Return `ros2-teleop--cells' grouped into three rows of three."
  (list (seq-subseq ros2-teleop--cells 0 3)
    (seq-subseq ros2-teleop--cells 3 6)
    (seq-subseq ros2-teleop--cells 6 9)))

(defun ros2-teleop--cell-for-key (key)
  "Return the grid cell bound to KEY, or nil."
  (assoc key ros2-teleop--cells))

(defun ros2-teleop--cell-active-p (cell active-key)
  "Non-nil when CELL is the engaged ACTIVE-KEY (and ACTIVE-KEY is set)."
  (and active-key (equal (nth 0 cell) active-key)))

(defun ros2-teleop--cell-label (cell active-key)
  "Return CELL as a single-line \"ARROW KEY\" label, lit when it is the ACTIVE-KEY.
A single line keeps the cell inside one `vui-table' row; a two-line cell
would overflow the row and shear the grid."
  (concat
    (propertize (nth 1 cell) 'face
      (if (ros2-teleop--cell-active-p cell active-key)
        'ros2-teleop-active
        'ros2-teleop-arrow))
    " "
    (propertize (nth 0 cell) 'face 'ros2-teleop-key)))

(defun ros2-teleop--table (active-key)
  "Return the teleop grid as a unicode-bordered `vui-table' vnode.
The cell bound to ACTIVE-KEY renders its arrow highlighted."
  (vui-table
    :border :unicode
    :border-face 'ros2-teleop-border
    :columns '((:align :center) (:align :center) (:align :center))
    :rows (mapcar
            (lambda (row)
              (mapcar (lambda (cell) (ros2-teleop--cell-label cell active-key))
                row))
            (ros2-teleop--rows))))

(defun ros2-teleop-publish (linear angular)
  "Publish a velocity command with LINEAR and ANGULAR weights.
Not wired up yet."
  (ignore linear angular))


;;; Teleop panel: its own buffer, window, and isolated keymap

(defcustom ros2-teleop-topic "/cmd_vel"
  "Topic the teleop grid publishes to."
  :type 'string
  :group 'ros2-teleop)

(defcustom ros2-teleop-publish-rate 5
  "Rate, in hertz, the engaged motion republishes at."
  :type 'integer
  :group 'ros2-teleop)

(defcustom ros2-teleop-show-mode-line nil
  "When non-nil, show the mode-line in the *ros2:teleop* window."
  :type 'boolean
  :group 'ros2-teleop)

(defvar-local ros2-teleop--active nil
  "The teleop key currently engaged in this buffer, or nil.")

(defun ros2-teleop--status-line ()
  "Return the teleop status line naming the target topic and publish rate."
  (propertize (format "  → %s   %d Hz" ros2-teleop-topic ros2-teleop-publish-rate)
    'face 'shadow))

(vui-defcomponent ros2-teleop--panel ()
  "The teleop panel: the 3x3 drive grid above its target-topic status line."
  :render
  (vui-vstack
    (ros2-teleop--table ros2-teleop--active)
    (vui-text "")
    (vui-text (ros2-teleop--status-line))))

(defun ros2-teleop--drive (key)
  "Engage teleop KEY: publish its velocity weights and re-light the grid."
  (setq ros2-teleop--active key)
  (when-let ((cell (ros2-teleop--cell-for-key key)))
    (ros2-teleop-publish (nth 2 cell) (nth 3 cell)))
  (vui-refresh))

(defun ros2-teleop-stop ()
  "Emergency-stop: publish zero velocity and centre the grid on `k'."
  (declare (modes ros2-teleop-mode))
  (interactive)
  (ros2-teleop--drive "k"))

(defvar ros2-teleop-mode-map
  (let ((map (make-sparse-keymap)))
    (dolist (cell ros2-teleop--cells)
      (define-key map (nth 0 cell)
        (let ((key (nth 0 cell)))
          (lambda () (interactive) (ros2-teleop--drive key)))))
    (define-key map (kbd "SPC") #'ros2-teleop-stop)
    (define-key map "q" #'quit-window)
    map)
  "Keymap for `ros2-teleop-mode', local to the *ros2:teleop* window.")

(declare-function evil-set-initial-state "evil-core")
(with-eval-after-load 'evil
  (evil-set-initial-state 'ros2-teleop-mode 'emacs))

(define-derived-mode ros2-teleop-mode vui-mode "ros2-teleop-mode"
  "Major mode for the *ros2:teleop* drive panel."
  (unless ros2-teleop-show-mode-line
    (setq-local mode-line-format nil)))
(put 'ros2-teleop-mode 'completion-predicate #'ignore)

(with-eval-after-load 'nerd-icons
  (add-to-list 'nerd-icons-mode-icon-alist
               '(ros2-teleop-mode nerd-icons-devicon "nf-dev-ros" :face nerd-icons-blue)))

(defun ros2-teleop--buffer ()
  "Return the *ros2:teleop* buffer, creating and mounting its panel if needed.
Mounts without stealing the selected window, so the caller controls layout."
  (let ((buffer (get-buffer-create "*ros2:teleop*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'ros2-teleop-mode)
        (ros2-teleop-mode)))
    (save-window-excursion
      (vui-mount (vui-component 'ros2-teleop--panel) "*ros2:teleop*"))
    buffer))

(provide 'ros2-teleop)

;;; ros2-teleop.el ends here
