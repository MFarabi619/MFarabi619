;;; kanban.el --- Kanban board  -*- lexical-binding: t -*-

;; Copyright © 2025-2026 Mumtahin Farabi <mfarabi619@gmail.com>

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; URL: https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/kanban
;; Keywords: tools, convenience
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
;;; Code:

(require 'vui)
(require 'vui-components)

;;; Customization

(defgroup kanban ()
  "Kanban board for Emacs."
  :prefix "kanban-"
  :group 'tools
  :group 'convenience
  :link '(url-link :tag "GitHub" "https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/kanban"))

(defconst kanban-buffer-name "*kanban*"
  "Name of the kanban board buffer.")

(defcustom kanban-columns
  '((:name "Todo" :items ((:title "My first card")
                           (:title "My second card")))
     (:name "Done" :items nil))
  "Board columns, each a plist of (:name :items).
Each item in :items is a card plist of (:title)."
  :type '(repeat sexp))

(defcustom kanban-column-width 26
  "Width in characters of each board column, including the gutter."
  :type 'natnum)

(defcustom kanban-header-face 'vui-heading-2
  "Fallback face for a column header.
Used when the column name does not map to an Org TODO keyword (or
Org is not loaded); otherwise the keyword's Org face is used."
  :type 'face)

(defcustom kanban-column-gutter 2
  "Blank columns of page background between lanes."
  :type 'natnum)

(defface kanban-column '((t :inherit hl-line))
  "Background face for a column lane.
Inherits `hl-line' so the lane picks up a subtle theme color."
  :group 'kanban)

(defface kanban-card '((t :inherit region))
  "Face for a card tile.
Inherits `region' so the tile picks up a theme color a shade
stronger than the lane."
  :group 'kanban)

;;; Model

(defun kanban-column-name (column)
  "Return COLUMN's display name."
  (plist-get column :name))

(defun kanban-column-items (column)
  "Return COLUMN's list of card plists."
  (plist-get column :items))

(defun kanban-column-count (column)
  "Return the number of cards in COLUMN."
  (length (kanban-column-items column)))

(defun kanban-card-title (card)
  "Return CARD's title string."
  (plist-get card :title))

;;; Rendering

(defun kanban--card (card)
  "Render CARD as a width-filling tile vnode, truncating long titles."
  (let ((width (max 1 (- kanban-column-width 2))))
    (vui-box (vui-text (truncate-string-to-width (kanban-card-title card)
                         (max 1 (1- width)) nil nil "…"))
      :width width
      :padding-left 1
      :face 'kanban-card)))

(defun kanban--lane-cell (content)
  "Wrap CONTENT in a full-width lane cell carrying the column background."
  (vui-box content
    :width kanban-column-width
    :padding-left 1
    :padding-right 1
    :face 'kanban-column))

(defun kanban--header-face (column)
  "Return the face for COLUMN's header.
When Org is loaded and COLUMN's name maps to a TODO keyword
\(upcased, spaces removed), use that keyword's Org face; otherwise
fall back to `kanban-header-face'."
  (or (and (fboundp 'org-get-todo-face)
           (boundp 'org-todo-keyword-faces)
           (let ((keyword (upcase (string-replace " " "" (kanban-column-name column)))))
             (and (assoc keyword org-todo-keyword-faces)
                  (ignore-errors (org-get-todo-face keyword)))))
      kanban-header-face))

(defun kanban--column-header-label (column)
  "Return COLUMN's header as an upcased \"NAME (COUNT)\" string."
  (format "%s (%d)" (upcase (kanban-column-name column)) (kanban-column-count column)))

(defun kanban--header-cell-content (column)
  "Return COLUMN's header line: a bold label then a dim rule.
The rule (box-drawing ─) fills the rest of the lane width as a
section divider, without underlining the label."
  (let* ((label (propertize (kanban--column-header-label column)
                  'face (list '(:weight bold :underline nil)
                          (kanban--header-face column))))
          (inner-width (max 0 (- kanban-column-width 2)))
          (fill (- inner-width (string-width label) 1)))
    (if (> fill 0)
      (concat label " " (propertize (make-string fill ?─) 'face 'shadow))
      label)))

(defun kanban--header-row (columns)
  "Return the board's header row: one lane cell per column."
  (mapcar (lambda (column)
            (kanban--lane-cell (vui-text (kanban--header-cell-content column))))
    columns))

(defun kanban--empty-row (columns)
  "Return a board row of blank lane cells, one per column in COLUMNS."
  (mapcar (lambda (_column) (kanban--lane-cell "")) columns))

(defun kanban--rows (columns &optional min-rows)
  "Transpose COLUMNS' cards into table rows, with a blank row between cards.
Row N holds each column's Nth card tile, or an empty cell where a
column has no Nth card.  A blank spacer row separates consecutive
cards so the tiles read as discrete units.  Pad with blank lane rows
up to MIN-ROWS so the lanes fill down the buffer."
  (let ((depth (apply #'max 0 (mapcar #'kanban-column-count columns)))
         (rows nil))
    (dotimes (row depth)
      (when (> row 0)
        (push (kanban--empty-row columns) rows))
      (push (mapcar (lambda (column)
                      (let ((card (nth row (kanban-column-items column))))
                        (kanban--lane-cell (if card (kanban--card card) ""))))
              columns)
        rows))
    (setq rows (nreverse rows))
    (while (< (length rows) (or min-rows 0))
      (setq rows (nconc rows (list (kanban--empty-row columns)))))
    rows))

(defun kanban--window-body-rows ()
  "Body lines in the window showing the board, or nil when undisplayed."
  (when-let* ((window (get-buffer-window kanban-buffer-name)))
    (window-body-height window)))

(defun kanban--board (columns &optional total-lines)
  "Render COLUMNS side by side as colored lanes in a `vui-table'.
When TOTAL-LINES is non-nil, lanes are padded with blank rows to
fill that many lines (the header row included)."
  (vui-table
    :columns (mapcar (lambda (_column)
                       (list :width (+ kanban-column-width kanban-column-gutter)
                         :grow t))
               columns)
    :rows (append (list (kanban--header-row columns)
                    (kanban--empty-row columns))
            (kanban--rows columns (and total-lines (max 0 (- total-lines 2)))))))

;;; Component

(vui-defcomponent kanban-board ()
  :state ((columns kanban-columns))
  :render (kanban--board columns (kanban--window-body-rows)))

;;; Entry point

;;;###autoload
(defun kanban ()
  "Open the kanban board."
  (interactive)
  (let ((instance (vui-mount (vui-component 'kanban-board) kanban-buffer-name)))
    (with-current-buffer kanban-buffer-name
      (vui-rerender-on-resize)
      (vui-rerender instance))))

(provide 'kanban)

;;; kanban.el ends here
