;;; kanban.el --- Kanban board  -*- lexical-binding: t -*-

;; Copyright © 2025-2026 Mumtahin Farabi <mfarabi619@gmail.com>

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; URL: https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/kanban
;; Keywords: tools, convenience
;; Version: 0.0.1
;; Package-Requires: ((emacs "29.1") (nerd-icons "0.1"))

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

(require 'org)
(require 'org-agenda)
(require 'org-clock)
(require 'nerd-icons)
(require 'seq)
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
  "Demo board columns, each a plist of (:name :items).
Each item in :items is a card plist of (:title).  Used when
`kanban-org-files' is nil."
  :type '(repeat sexp))

(defcustom kanban-org-files t
  "Source for the board's columns and cards.
t (the default) reads your Org agenda \\=`(org-agenda-files)' as the
source of truth, falling back to the demo `kanban-columns' only
when no agenda files are configured.  nil always uses the demo
board.  A list of files reads TODO entries from those Org files."
  :type '(choice (const :tag "Org agenda files (source of truth)" t)
           (const :tag "Demo board" nil)
           (repeat :tag "Specific Org files" file)))

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

(defcustom kanban-due-soon-days 2
  "A deadline within this many days is shown with `kanban-due-soon'."
  :type 'natnum)

(defcustom kanban-header-rule-lead 2
  "Number of leading rule characters before a column header label."
  :type 'natnum)

(defcustom kanban-header-rule-char ?─
  "Character used to draw the column header rule."
  :type 'character)

(defcustom kanban-priority-pill-caps '("" . "")
  "Cons (LEFT . RIGHT) of cap strings wrapping the priority pill.
Defaults to powerline rounded half-circles \\='\\ue0b6 / \\='\\ue0b4
\(needs a Nerd/powerline font).  Use \\='(\"[\" . \"]\") for brackets,
or \\='(\"\" . \"\") for a plain filled block."
  :type '(cons string string))

(defcustom kanban-tag-pill-caps '("" . "")
  "Cons (LEFT . RIGHT) of cap strings for `caps'-style tag pills."
  :type '(cons string string))

(defcustom kanban-tag-pill-style 'box
  "How each tag is outlined: `box' border, `caps' end glyphs, or `plain'."
  :type '(choice (const box) (const caps) (const plain)))

(defcustom kanban-card-padding-rows 0
  "Blank card rows above and below each card's content."
  :type 'natnum)

(defcustom kanban-card-gap 1
  "Blank column rows between cards in a lane."
  :type 'natnum)

(defcustom kanban-progress-bar-width 3
  "Width in cells of a card's checkbox progress bar."
  :type 'natnum)

(defcustom kanban-deadline-icon (nerd-icons-mdicon "nf-md-calendar_alert")
  "Glyph shown before the deadline badge."
  :type 'string)

(defcustom kanban-scheduled-icon (nerd-icons-mdicon "nf-md-calendar_start")
  "Glyph shown before the scheduled badge."
  :type 'string)

(defcustom kanban-closed-icon (nerd-icons-mdicon "nf-md-check")
  "Glyph shown before a card's CLOSED badge."
  :type 'string)

(defcustom kanban-repeat-icon (nerd-icons-mdicon "nf-md-repeat")
  "Glyph marking a repeating task."
  :type 'string)

(defcustom kanban-blocked-icon (nerd-icons-mdicon "nf-md-lock")
  "Glyph marking a dependency-blocked task."
  :type 'string)

(defcustom kanban-clock-active-icon (nerd-icons-mdicon "nf-md-timer_play")
  "Glyph marking the actively clocked task."
  :type 'string)

(defcustom kanban-breadcrumb-separator " › "
  "String joining ancestor headings in a card's breadcrumb."
  :type 'string)

(defface kanban-column '((t :inherit hl-line))
  "Background face for a column lane.
Inherits `hl-line' so the lane picks up a subtle theme color."
  :group 'kanban)

(defface kanban-card '((t :inherit region))
  "Face for a card tile.
Inherits `region' so the tile picks up a theme color a shade
stronger than the lane."
  :group 'kanban)

(defface kanban-card-meta '((t :inherit shadow))
  "Face for a card's secondary meta row (deadline, tags)."
  :group 'kanban)

(defface kanban-card-tag '((t :inherit shadow))
  "Face for card tags on the meta row."
  :group 'kanban)

(defface kanban-due-soon '((t :inherit warning))
  "Face for a deadline due within `kanban-due-soon-days'."
  :group 'kanban)

(defface kanban-overdue '((t :inherit error))
  "Face for an overdue deadline."
  :group 'kanban)

(defface kanban-band '((t :inherit bold))
  "Face for a swimlane band header."
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

(defun kanban-card-scheduled (card)
  "Return CARD's SCHEDULED timestamp string, or nil."
  (plist-get card :scheduled))

(defun kanban-card-closed (card)
  "Return CARD's CLOSED timestamp string, or nil."
  (plist-get card :closed))

(defun kanban-card-id (card)
  "Return CARD's Org ID, or nil."
  (plist-get card :id))

(defun kanban-card-outline-path (card)
  "Return CARD's ancestor outline path (a list of headings), or nil."
  (plist-get card :outline-path))

(defun kanban-card-progress (card)
  "Return CARD's checkbox progress as (DONE . TOTAL), or nil."
  (plist-get card :progress))

(defun kanban-card-clocked (card)
  "Return minutes clocked on CARD, or nil."
  (plist-get card :clocked))

(defun kanban-card-property (card name)
  "Return CARD's Org property NAME (a string), or nil."
  (cdr (assoc name (plist-get card :properties))))

;;; Org source

(defun kanban--todo-keywords (files)
  "Return the ordered TODO keywords declared by FILES.
Reads `org-todo-keywords-1' from the first file's Org buffer, so
per-file `#+TODO:' lines are honored."
  (when files
    (with-current-buffer (find-file-noselect (car files))
      (copy-sequence org-todo-keywords-1))))

(defcustom kanban-group-by nil
  "Field to group cards into swimlanes, or nil for a single board.
- `category' groups by each heading's Org category.
- `priority' groups by the priority cookie (A/B/C).
- a string groups by that Org property (e.g. \"ASSIGNEE\")."
  :type '(choice (const :tag "No swimlanes" nil)
           (const :tag "Org category" category)
           (const :tag "Priority" priority)
           (string :tag "Org property name")))

(defun kanban--entry-group ()
  "Return the swimlane group key for the Org entry at point.
Dispatches on `kanban-group-by'; nil means ungrouped."
  (pcase kanban-group-by
    ('nil nil)
    ('category (org-get-category))
    ('priority (let ((priority (nth 3 (org-heading-components))))
                 (if priority (char-to-string priority) "No priority")))
    ((and (pred stringp) property)
      (or (org-entry-get nil property) (format "No %s" property)))
    (_ nil)))

(defun kanban--parse-progress (heading)
  "Return (DONE . TOTAL) from a [N/M] statistics cookie in HEADING, or nil."
  (when (and heading (string-match "\\[\\([0-9]+\\)/\\([0-9]+\\)\\]" heading))
    (cons (string-to-number (match-string 1 heading))
      (string-to-number (match-string 2 heading)))))

(defun kanban--entry->card ()
  "Build a card plist for the Org entry at point."
  (let ((components (org-heading-components)))
    (list :title (nth 4 components)
      :state (nth 2 components)
      :priority (nth 3 components)
      :deadline (org-entry-get nil "DEADLINE")
      :scheduled (org-entry-get nil "SCHEDULED")
      :closed (org-entry-get nil "CLOSED")
      :tags (org-get-tags nil t)
      :effort (org-entry-get nil "Effort")
      :category (org-get-category)
      :id (org-entry-get nil "ID")
      :outline-path (org-get-outline-path)
      :progress (kanban--parse-progress (nth 4 components))
      :clocked (let ((minutes (org-clock-sum-current-item))) (and (> minutes 0) minutes))
      :repeat (org-get-repeat)
      :blocked (org-entry-blocked-p)
      :clock-active (and (bound-and-true-p org-clock-hd-marker)
                      (eq (marker-buffer org-clock-hd-marker) (current-buffer))
                      (= (marker-position org-clock-hd-marker) (point)))
      :properties (org-entry-properties nil 'standard)
      :group (kanban--entry-group)
      :marker (point-marker))))

(defun kanban--card-group (card)
  "Return CARD's swimlane group key (captured at read time), or nil."
  (plist-get card :group))

(defun kanban--priority-rank (card)
  "Return CARD's priority sort key; lower sorts higher (A < B < C).
Cards with no priority cookie sort as `org-priority-default'."
  (or (plist-get card :priority) org-priority-default))

(defun kanban--read-board (&optional files)
  "Return columns and cards read from Org TODO entries in FILES.
FILES defaults to `(org-agenda-files)'.  Each TODO keyword becomes
a column in `#+TODO' order, holding the entries in that state,
highest priority first.  The result matches the shape
`kanban--board' consumes."
  (let* ((files (or files (org-agenda-files)))
          (keywords (kanban--todo-keywords files)))
    (mapcar (lambda (keyword)
              (list :name keyword
                :items (sort (org-map-entries #'kanban--entry->card
                               (concat "/" keyword) files)
                         (lambda (a b)
                           (< (kanban--priority-rank a) (kanban--priority-rank b))))))
      keywords)))

(defun kanban--distinct-groups (columns)
  "Return the distinct card group keys across COLUMNS, in first-seen order."
  (let ((seen nil))
    (dolist (column columns (nreverse seen))
      (dolist (card (kanban-column-items column))
        (let ((group (kanban--card-group card)))
          (unless (member group seen)
            (push group seen)))))))

(defun kanban--group-into-bands (columns)
  "Split COLUMNS into swimlane bands by each card's group.
Returns a list of (GROUP . COLUMNS) where COLUMNS holds only that
group's cards.  When grouping is off, returns one (nil . COLUMNS)."
  (if (null kanban-group-by)
    (list (cons nil columns))
    (mapcar (lambda (group)
              (cons group
                (mapcar (lambda (column)
                          (list :name (kanban-column-name column)
                            :items (seq-filter
                                     (lambda (card) (equal (kanban--card-group card) group))
                                     (kanban-column-items column))))
                  columns)))
      (kanban--distinct-groups columns))))

(defun kanban--board-columns ()
  "Return the board's columns from Org or demo data per `kanban-org-files'."
  (pcase kanban-org-files
    ('nil kanban-columns)
    ('t (or (kanban--read-board) kanban-columns))
    (files (kanban--read-board files))))

;;; Rendering

(defun kanban--priority-color (priority)
  "Return the foreground color of PRIORITY's Org face, as a color string."
  (let ((face (org-get-priority-face priority)))
    (cond ((and (listp face) (plist-get face :foreground)))
      ((facep face) (face-foreground face nil t))
      (t (face-foreground 'default nil t)))))

(defun kanban--priority-pill (priority)
  "Return PRIORITY as a rounded pill badge, or nil when there is no priority."
  (when priority
    (let ((color (kanban--priority-color priority))
           (bg (face-attribute 'default :background nil t)))
      (concat (propertize (car kanban-priority-pill-caps) 'face (list :foreground color))
        (propertize (char-to-string priority)
          'face (list :background color :foreground bg :weight 'bold))
        (propertize (cdr kanban-priority-pill-caps) 'face (list :foreground color))))))

(defun kanban--compact-effort (effort)
  "Compact an Org EFFORT like \"2:00\"/\"0:30\"/\"1:30\" to \"2h\"/\"30m\"/\"1h30\"."
  (if (string-match "\\`\\([0-9]+\\):\\([0-9]+\\)\\'" effort)
    (let ((hours (string-to-number (match-string 1 effort)))
           (minutes (string-to-number (match-string 2 effort))))
      (cond ((zerop hours) (format "%dm" minutes))
        ((zerop minutes) (format "%dh" hours))
        (t (format "%dh%02d" hours minutes))))
    effort))

(defun kanban--compact-minutes (minutes)
  "Compact a duration in MINUTES to \"2h\"/\"30m\"/\"1h30\"."
  (let ((hours (/ minutes 60))
         (mins (% minutes 60)))
    (cond ((zerop hours) (format "%dm" mins))
      ((zerop mins) (format "%dh" hours))
      (t (format "%dh%02d" hours mins)))))

(defun kanban--effort-badge (card)
  "Return CARD's time badge: clocked/effort ratio, either alone, or nil."
  (let* ((effort (plist-get card :effort))
          (clocked (kanban-card-clocked card))
          (estimate (and effort (kanban--compact-effort effort)))
          (spent (and clocked (kanban--compact-minutes clocked)))
          (label (cond ((and spent estimate) (format "%s/%s" spent estimate))
                   (spent spent)
                   (estimate estimate))))
    (and label (propertize label 'face 'kanban-card-meta))))

(defun kanban--progress-bar (progress)
  "Return a compact faced bar for PROGRESS (DONE . TOTAL), or nil."
  (when progress
    (let* ((done (car progress))
            (total (max 1 (cdr progress)))
            (width kanban-progress-bar-width)
            (filled (min width (max 0 (round (* width (/ done (float total))))))))
      (propertize (concat (make-string filled ?▰) (make-string (- width filled) ?▱))
        'face 'kanban-card-meta))))

(defun kanban--card-inner-width ()
  "Return the usable text width inside a card tile (after both paddings)."
  (max 1 (- kanban-column-width 4)))

(defun kanban--card-line (content)
  "Wrap the single-line string CONTENT in a card tile box."
  (vui-box (vui-text content)
    :width (max 1 (- kanban-column-width 2))
    :padding-left 1
    :padding-right 1
    :face 'kanban-card))

(defun kanban--strip-cookie (title)
  "Return TITLE without a trailing/embedded [N/M] or [P%] statistics cookie."
  (string-trim
    (replace-regexp-in-string "[ \t]*\\[[0-9]*\\(?:%\\|/[0-9]*\\)\\]" "" title)))

(defun kanban--card-breadcrumb-cell (card)
  "Return CARD's parent outline-path row, or nil at top level."
  (when-let* ((path (kanban-card-outline-path card)))
    (kanban--card-line
      (propertize (truncate-string-to-width
                    (string-join path kanban-breadcrumb-separator)
                    (kanban--card-inner-width) nil nil "…")
        'face 'kanban-card-meta))))

(defun kanban--card-title-cell (card)
  "Return CARD's title row: the (cookie-stripped) title left, effort right."
  (let* ((inner (kanban--card-inner-width))
          (effort (kanban--effort-badge card))
          (effort-width (if effort (string-width effort) 0))
          (title-width (max 1 (- inner effort-width (if effort 1 0))))
          (title (truncate-string-to-width (kanban--strip-cookie (kanban-card-title card))
                   title-width nil nil "…"))
          (pad (max 0 (- inner (string-width title) effort-width))))
    (kanban--card-line (concat title (make-string pad ?\s) (or effort "")))))

(defun kanban--deadline-face (days)
  "Return the urgency face for a deadline DAYS from now.
Overdue (negative) uses `kanban-overdue'; within
`kanban-due-soon-days' uses `kanban-due-soon'; otherwise
`kanban-card-meta'."
  (cond ((< days 0) 'kanban-overdue)
    ((<= days kanban-due-soon-days) 'kanban-due-soon)
    (t 'kanban-card-meta)))

(defun kanban--relative-deadline (days)
  "Return a faced relative deadline label for DAYS from now."
  (propertize (if (zerop days) "today" (format "%dd" days))
    'face (kanban--deadline-face days)))

(defun kanban--icon (glyph face)
  "Return nerd-icons GLYPH with FACE merged over its font family."
  (let ((icon (copy-sequence glyph)))
    (add-face-text-property 0 (length icon) face nil icon)
    icon))

(defun kanban--deadline-badge (card)
  "Return CARD's deadline badge: a due icon + relative day label, or nil.
Urgency-colored (overdue/soon/far)."
  (when-let* ((deadline (plist-get card :deadline)))
    (let* ((label (kanban--relative-deadline (org-time-stamp-to-now deadline)))
            (face (get-text-property 0 'face label)))
      (concat (kanban--icon kanban-deadline-icon face) " " label))))

(defun kanban--scheduled-badge (card)
  "Return CARD's scheduled badge: a start icon + relative day label, or nil.
Scheduled is a start date, so it stays dim rather than urgency-colored."
  (when-let* ((scheduled (kanban-card-scheduled card)))
    (let ((days (org-time-stamp-to-now scheduled)))
      (concat (kanban--icon kanban-scheduled-icon 'kanban-card-meta)
        " "
        (propertize (if (zerop days) "today" (format "%dd" days)) 'face 'kanban-card-meta)))))

(defun kanban--tag-pill-extra-width ()
  "Extra columns a tag pill adds around its text (cap widths, or 0)."
  (if (eq kanban-tag-pill-style 'caps)
    (+ (string-width (car kanban-tag-pill-caps))
      (string-width (cdr kanban-tag-pill-caps)))
    0))

(defun kanban--tag-face (tag)
  "Return TAG's configured Org face, or `kanban-card-tag'."
  (if (and (boundp 'org-tag-faces) (assoc tag org-tag-faces))
    (org-get-tag-face tag)
    'kanban-card-tag))

(defun kanban--tag-pill (tag)
  "Return TAG as a pill per `kanban-tag-pill-style', in its Org tag color."
  (let ((face (kanban--tag-face tag)))
    (pcase kanban-tag-pill-style
      ('box (let ((s (copy-sequence tag)))
              (add-face-text-property 0 (length s) face nil s)
              (add-face-text-property 0 (length s) '(:box (:line-width (1 . -1))) nil s)
              s))
      ('caps (propertize (concat (car kanban-tag-pill-caps) tag (cdr kanban-tag-pill-caps))
               'face face))
      (_ (propertize tag 'face face)))))

(defun kanban--card-tags-string (tags max-width)
  "Return TAGS as space-separated pills within MAX-WIDTH, overflow as \"+N\"."
  (if (or (null tags) (<= max-width 0))
    ""
    (let ((caps (kanban--tag-pill-extra-width))
           (shown nil) (rest tags) (used 0))
      (while (and rest
               (<= (+ used (string-width (car rest)) caps (if shown 1 0)) max-width))
        (setq used (+ used (string-width (car rest)) caps (if shown 1 0)))
        (push (pop rest) shown))
      (let ((marker (and rest (format "+%d" (length rest)))))
        (when marker
          (while (and shown (> (+ used 1 (string-width marker)) max-width))
            (setq used (- used (string-width (car shown)) caps 1))
            (pop shown)))
        (string-join
          (append (mapcar #'kanban--tag-pill (nreverse shown))
            (and marker (list (propertize marker 'face 'kanban-card-tag))))
          " ")))))

(defun kanban--card-classify-cell (card)
  "Return CARD's classification row (priority pill + tags), or nil when empty."
  (let* ((inner (kanban--card-inner-width))
          (pill (kanban--priority-pill (plist-get card :priority)))
          (pill-width (if pill (string-width pill) 0))
          (tags-budget (max 0 (- inner pill-width (if pill 1 0))))
          (tags (kanban--card-tags-string (plist-get card :tags) tags-budget))
          (parts (delq nil (list pill (unless (string= tags "") tags)))))
    (when parts
      (kanban--card-line (truncate-string-to-width (string-join parts " ") inner nil nil "…")))))

(defun kanban--closed-badge (card)
  "Return CARD's CLOSED badge (check icon + \"N ago\"), or nil."
  (when-let* ((closed (kanban-card-closed card)))
    (let* ((ago (- (org-time-stamp-to-now closed)))
            (label (cond ((<= ago 0) "today")
                     ((= ago 1) "1d ago")
                     (t (format "%dd ago" ago)))))
      (concat (kanban--icon kanban-closed-icon 'kanban-card-meta) " "
        (propertize label 'face 'kanban-card-meta)))))

(defun kanban--combined-dates-badge (deadline scheduled)
  "Return a compact DEADLINE/SCHEDULED badge, deadline colored by urgency."
  (let* ((dl (org-time-stamp-to-now deadline))
          (sch (org-time-stamp-to-now scheduled))
          (dl-face (kanban--deadline-face dl)))
    (concat (kanban--icon kanban-deadline-icon dl-face) " "
      (propertize (number-to-string dl) 'face dl-face)
      (propertize (format "/%dd" sch) 'face 'kanban-card-meta))))

(defun kanban--dates-cluster (card)
  "Return CARD's date badge: combined deadline/scheduled, or whichever exists."
  (let ((deadline (plist-get card :deadline))
         (scheduled (kanban-card-scheduled card)))
    (if (and deadline scheduled)
      (kanban--combined-dates-badge deadline scheduled)
      (string-join (delq nil (list (kanban--deadline-badge card)
                               (kanban--scheduled-badge card)))
        " "))))

(defun kanban--card-markers (card)
  "Return CARD's active-clock and blocked marker glyphs, or nil."
  (let ((parts (delq nil
                 (list (and (plist-get card :clock-active)
                         (kanban--icon kanban-clock-active-icon 'kanban-due-soon))
                   (and (plist-get card :blocked)
                     (kanban--icon kanban-blocked-icon 'kanban-card-meta))))))
    (and parts (string-join parts " "))))

(defun kanban--card-bottom-cell (card)
  "Return CARD's bottom row: markers/progress left, dates right, or nil."
  (let* ((inner (kanban--card-inner-width))
          (dates (kanban--dates-cluster card))
          (left (string-join
                  (delq nil (list (kanban--card-markers card)
                              (kanban--progress-bar (kanban-card-progress card))))
                  " "))
          (right (string-join
                   (delq nil (list (or (kanban--closed-badge card)
                                     (and (not (string= dates "")) dates))
                               (and (plist-get card :repeat)
                                 (kanban--icon kanban-repeat-icon 'kanban-card-meta))))
                   " ")))
    (unless (and (string= left "") (string= right ""))
      (let ((pad (max (if (and (> (string-width left) 0) (> (string-width right) 0)) 1 0)
                   (- inner (string-width left) (string-width right)))))
        (kanban--card-line (truncate-string-to-width
                             (concat left (make-string pad ?\s) right)
                             inner nil nil "…"))))))

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
  "Return COLUMN's header: a short lead rule, the bold label, then a
trailing rule filling the lane.  Both rules share the label's color
\(the column's keyword face), without bold or underline."
  (let* ((color (kanban--header-face column))
          (label (propertize (kanban--column-header-label column)
                   'face (list '(:weight bold :underline nil) color)))
          (rule-face (list '(:underline nil) color))
          (inner-width (max 0 (- kanban-column-width 2)))
          (lead-n (min kanban-header-rule-lead inner-width))
          (lead (propertize (make-string lead-n kanban-header-rule-char) 'face rule-face))
          (fill (- inner-width lead-n 1 (string-width label) 1)))
    (concat lead " " label
      (if (> fill 0)
        (concat " " (propertize (make-string fill kanban-header-rule-char) 'face rule-face))
        ""))))

(defun kanban--header-row (columns)
  "Return the board's header row: one lane cell per column."
  (mapcar (lambda (column)
            (kanban--lane-cell (vui-text (kanban--header-cell-content column))))
    columns))

(defun kanban--empty-row (columns)
  "Return a board row of blank lane cells, one per column in COLUMNS."
  (mapcar (lambda (_column) (kanban--lane-cell "")) columns))

(defun kanban--tile-blank ()
  "Return a blank card-faced tile row, for a card's internal vertical padding."
  (vui-box "" :width (max 1 (- kanban-column-width 2)) :face 'kanban-card))

(defun kanban--rows (columns &optional min-rows)
  "Transpose COLUMNS' cards into table rows.
Each card spans a breadcrumb, title, classification, and bottom row (all
but the title optional), padded by `kanban-card-padding-rows' and
separated by `kanban-card-gap'.  Fill up to MIN-ROWS."
  (let ((depth (apply #'max 0 (mapcar #'kanban-column-count columns)))
         (rows nil))
    (dotimes (row depth)
      (when (> row 0)
        (dotimes (_ kanban-card-gap) (push (kanban--empty-row columns) rows)))
      (let* ((cards (mapcar (lambda (column) (nth row (kanban-column-items column)))
                      columns))
              (pad-row (lambda ()
                         (mapcar (lambda (card)
                                   (kanban--lane-cell (if card (kanban--tile-blank) "")))
                           cards)))
              (content-row (lambda (cell-fn)
                             (let ((cells (mapcar (lambda (card)
                                                    (and card (funcall cell-fn card)))
                                            cards)))
                               (when (seq-some #'identity cells)
                                 (mapcar (lambda (cell) (kanban--lane-cell (or cell ""))) cells))))))
        (dotimes (_ kanban-card-padding-rows) (push (funcall pad-row) rows))
        (when-let* ((r (funcall content-row #'kanban--card-breadcrumb-cell))) (push r rows))
        (push (funcall content-row #'kanban--card-title-cell) rows)
        (when-let* ((r (funcall content-row #'kanban--card-classify-cell))) (push r rows))
        (when-let* ((r (funcall content-row #'kanban--card-bottom-cell))) (push r rows))
        (dotimes (_ kanban-card-padding-rows) (push (funcall pad-row) rows))))
    (setq rows (nreverse rows))
    (while (< (length rows) (or min-rows 0))
      (setq rows (nconc rows (list (kanban--empty-row columns)))))
    rows))

(defun kanban--window-body-rows ()
  "Body lines in the window showing the board, or nil when undisplayed."
  (when-let* ((window (get-buffer-window kanban-buffer-name)))
    (window-body-height window)))

(defun kanban--columns-spec (columns)
  "Return the `vui-table' :columns spec for COLUMNS (width + gutter, grow)."
  (mapcar (lambda (_column)
            (list :width (+ kanban-column-width kanban-column-gutter) :grow t))
    columns))

(defun kanban--render-flat (columns total-lines)
  "Render COLUMNS as one table: header, spacer, then card rows.
When TOTAL-LINES is non-nil, pad the rows to fill that many lines."
  (vui-table
    :columns (kanban--columns-spec columns)
    :rows (append (list (kanban--header-row columns)
                    (kanban--empty-row columns))
            (kanban--rows columns (and total-lines (max 0 (- total-lines 2)))))))

(defun kanban--band-header (group columns)
  "Return a full-width band-header line for GROUP across COLUMNS."
  (let ((width (* (length columns) (+ kanban-column-width kanban-column-gutter)))
         (count (apply #'+ (mapcar #'kanban-column-count columns))))
    (vui-box (vui-text (format "%s  %d" (or group "Ungrouped") count) :face 'kanban-band)
      :width (max 1 width)
      :padding-left 1
      :face 'kanban-band)))

(defun kanban--render-bands (columns)
  "Render COLUMNS as swimlane bands: column headers once, then each band."
  (apply #'vui-vstack :spacing 1
    (vui-table :columns (kanban--columns-spec columns)
      :rows (list (kanban--header-row columns)))
    (mapcan (pcase-lambda (`(,group . ,band-columns))
              (list (kanban--band-header group band-columns)
                (vui-table :columns (kanban--columns-spec columns)
                  :rows (kanban--rows band-columns))))
      (kanban--group-into-bands columns))))

(defun kanban--board (columns &optional total-lines)
  "Render COLUMNS as a board: swimlane bands when `kanban-group-by' is
set, otherwise a single flat board filled to TOTAL-LINES."
  (if kanban-group-by
    (kanban--render-bands columns)
    (kanban--render-flat columns total-lines)))

;;; Component

(vui-defcomponent kanban-board ()
  :state ((columns (kanban--board-columns)))
  :render (kanban--board columns (kanban--window-body-rows)))

;;; Entry point

;;;###autoload
(defun kanban ()
  "Open the kanban board."
  (interactive)
  (let ((instance (vui-mount (vui-component 'kanban-board) kanban-buffer-name)))
    (with-current-buffer kanban-buffer-name
      (setq-local mode-name "kanban-mode")
      (vui-rerender-on-resize)
      (vui-rerender instance))))

(provide 'kanban)

;;; kanban.el ends here
