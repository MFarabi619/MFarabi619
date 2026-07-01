;;; kanban-tests.el --- Buttercup tests for kanban.el  -*- lexical-binding: t; -*-

;;; Code:

(require 'buttercup)
(require 'cl-lib)
(require 'seq)
(require 'kanban)

(buttercup-error-on-stale-elc)
(setq buttercup-stack-frame-style 'pretty)

(defun kanban-tests--render (vnode)
  "Render VNODE into a temp buffer and return the resulting string."
  (with-temp-buffer
    (vui-render vnode)
    (buffer-string)))

(defconst kanban-tests--fixtures-dir
  (expand-file-name "fixtures/"
    (file-name-directory (or load-file-name buffer-file-name)))
  "Directory holding test fixture files.")

(defun kanban-tests--fixture (name)
  "Return the absolute path of `fixtures/NAME'."
  (expand-file-name name kanban-tests--fixtures-dir))

(defun kanban-tests--column (name board)
  "Return the column named NAME from BOARD."
  (seq-find (lambda (column) (equal (kanban-column-name column) name)) board))

(defun kanban-tests--first-card (fixture column)
  "Return the first card of COLUMN after reading FIXTURE."
  (car (kanban-column-items
         (kanban-tests--column column
           (kanban--read-board (list (kanban-tests--fixture fixture)))))))

(buttercup-define-matcher :to-render-substrings (rendered substrings)
  "Match a rendered string when every entry in SUBSTRINGS appears in it."
  (let ((text (funcall rendered))
         (subs (funcall substrings)))
    (let ((missing (seq-remove (lambda (s) (string-match-p (regexp-quote s) text)) subs)))
      (if (null missing)
        (cons t  (format "Expected rendered string NOT to contain all of %S" subs))
        (cons nil (format "Expected rendered string to contain %S, missing %S" subs missing))))))

(describe "kanban-columns (default board)"
  (it "has Todo and Done columns in order"
    (expect (mapcar #'kanban-column-name kanban-columns)
      :to-equal '("Todo" "Done")))

  (it "seeds the Todo column with two cards"
    (expect (kanban-column-count (car kanban-columns)) :to-equal 2))

  (it "starts the Done column empty"
    (expect (kanban-column-count (nth 1 kanban-columns)) :to-equal 0)))

(describe "model accessors"
  (it "reads a column's name"
    (expect (kanban-column-name '(:name "Done" :items nil)) :to-equal "Done"))

  (it "reads a column's cards"
    (expect (kanban-column-items '(:name "Todo" :items ((:title "a"))))
      :to-equal '((:title "a"))))

  (it "counts the cards in a column"
    (expect (kanban-column-count '(:name "Todo" :items nil)) :to-equal 0)
    (expect (kanban-column-count '(:name "Todo" :items ((:title "a") (:title "b"))))
      :to-equal 2))

  (it "reads a card's title"
    (expect (kanban-card-title '(:title "Ship it")) :to-equal "Ship it")))

(describe "kanban--column-header-label"
  (it "upcases the name and parenthesizes the count"
    (expect (kanban--column-header-label '(:name "Todo" :items ((:title "a"))))
      :to-equal "TODO (1)")))

(describe "kanban--header-cell-content"
  (it "brackets the label with a lead rule and a trailing rule"
    (expect (substring-no-properties
              (kanban--header-cell-content '(:name "Todo" :items ((:title "a")))))
      :to-match (concat "\\`─+ " (regexp-quote "TODO (1)") " ─+")))

  (it "draws the rule in the label's color, not a fixed dim face"
    (let ((content (kanban--header-cell-content '(:name "Todo" :items ((:title "a"))))))
      (expect (get-text-property 0 'face content)
        :to-equal (list '(:underline nil) (kanban--header-face '(:name "Todo")))))))

(describe "kanban--header-face"
  (it "falls back to kanban-header-face for a non-keyword column"
    (expect (kanban--header-face '(:name "Whatever")) :to-equal kanban-header-face))

  (it "uses the org keyword face when the column name maps to a TODO keyword"
    (let ((org-todo-keyword-faces '(("TODO" . ignored))))
      (cl-letf (((symbol-function 'org-get-todo-face)
                  (lambda (keyword) (intern (concat "org-face-" keyword)))))
        (expect (kanban--header-face '(:name "Todo")) :to-equal 'org-face-TODO))))

  (it "maps a spaced column name to its keyword (In progress -> INPROGRESS)"
    (let ((org-todo-keyword-faces '(("INPROGRESS" . ignored))))
      (cl-letf (((symbol-function 'org-get-todo-face)
                  (lambda (keyword) (intern (concat "org-face-" keyword)))))
        (expect (kanban--header-face '(:name "In progress")) :to-equal 'org-face-INPROGRESS)))))

(describe "kanban--rows (cards transposed into table rows)"
  (it "produces one row per card in the deepest column"
    (let ((kanban-card-padding-rows 0)
           (kanban-card-gap 0))
      (expect (length (kanban--rows
                        '((:name "A" :items ((:title "a1") (:title "a2")))
                           (:name "B" :items ((:title "b1"))))))
        :to-equal 2)))

  (it "is empty when no column has cards"
    (expect (kanban--rows '((:name "A" :items nil) (:name "B" :items nil)))
      :to-equal nil)))

(describe "kanban--card-title-cell"
  (it "renders the title inside a faced card tile"
    (with-temp-buffer
      (vui-render (kanban--card-title-cell '(:title "Ship it")))
      (expect (buffer-string) :to-match "Ship it")
      (goto-char (point-min))
      (search-forward "Ship")
      (expect (get-text-property (match-beginning 0) 'face) :to-equal 'kanban-card)))

  (it "truncates an over-long title with an ellipsis and keeps the tile width"
    (let ((rendered (substring-no-properties
                      (kanban-tests--render
                        (kanban--card-title-cell '(:title "This is an extremely long card title"))))))
      (expect rendered :to-match "…")
      (expect (string-width rendered) :to-equal (- kanban-column-width 2))
      (expect (substring rendered -1) :to-equal " ")))

  (it "strips the [N/M] statistics cookie from the displayed title"
    (expect (substring-no-properties
              (kanban-tests--render (kanban--card-title-cell '(:title "Build lander [1/3]"))))
      :not :to-match "\\[1/3\\]"))

  (it "right-aligns the effort badge on the title row"
    (let ((rendered (substring-no-properties
                      (kanban-tests--render (kanban--card-title-cell '(:title "Task" :effort "2:00"))))))
      (expect rendered :to-match "Task")
      (expect rendered :to-match "2h "))))

(describe "kanban--strip-cookie"
  (it "removes [N/M] and [P%] cookies"
    (expect (kanban--strip-cookie "Build lander [1/3]") :to-equal "Build lander")
    (expect (kanban--strip-cookie "Task [50%]") :to-equal "Task"))
  (it "leaves a cookie-free title unchanged"
    (expect (kanban--strip-cookie "Plain title") :to-equal "Plain title")))

(describe "kanban--compact-effort"
  (it "compacts whole hours, minutes, and mixed efforts"
    (expect (kanban--compact-effort "2:00") :to-equal "2h")
    (expect (kanban--compact-effort "0:30") :to-equal "30m")
    (expect (kanban--compact-effort "1:30") :to-equal "1h30"))

  (it "passes through a non H:MM string unchanged"
    (expect (kanban--compact-effort "soon") :to-equal "soon")))

(describe "kanban--compact-minutes"
  (it "compacts whole hours, minutes, and mixed durations"
    (expect (kanban--compact-minutes 120) :to-equal "2h")
    (expect (kanban--compact-minutes 30) :to-equal "30m")
    (expect (kanban--compact-minutes 90) :to-equal "1h30")))

(describe "kanban--effort-badge"
  (it "is nil when the card tracks no time"
    (expect (kanban--effort-badge '(:title "x")) :to-be nil))

  (it "shows the effort estimate alone when nothing is clocked"
    (expect (substring-no-properties (kanban--effort-badge '(:effort "2:00"))) :to-equal "2h"))

  (it "shows clocked time alone when there is no estimate"
    (expect (substring-no-properties (kanban--effort-badge '(:clocked 45))) :to-equal "45m"))

  (it "shows a clocked/effort ratio when both are present"
    (expect (substring-no-properties (kanban--effort-badge '(:effort "4:00" :clocked 90)))
      :to-equal "1h30/4h")))

(describe "kanban--closed-badge"
  (it "is nil when the card has no CLOSED date"
    (expect (kanban--closed-badge '(:title "x")) :to-be nil))

  (it "renders a dim \"N ago\" badge with a check icon"
    (let* ((closed (format-time-string "[%Y-%m-%d %a %H:%M]"
                     (time-subtract (current-time) (days-to-time 3))))
            (badge (kanban--closed-badge (list :closed closed))))
      (expect (substring-no-properties badge) :to-match "3d ago")
      (expect (get-text-property (string-match "3" (substring-no-properties badge)) 'face badge)
        :to-equal 'kanban-card-meta))))

(describe "kanban--card-breadcrumb-cell"
  (it "is nil for a top-level card (no parent)"
    (expect (kanban--card-breadcrumb-cell '(:title "x")) :to-be nil))

  (it "renders the parent outline path, dim"
    (with-temp-buffer
      (vui-render (kanban--card-breadcrumb-cell '(:title "Build lander"
                                                   :outline-path ("Project Apollo"))))
      (goto-char (point-min))
      (expect (buffer-string) :to-match "Project Apollo")
      (search-forward "Project")
      (let ((face (get-text-property (match-beginning 0) 'face)))
        (expect (memq 'kanban-card-meta (if (listp face) face (list face))) :to-be-truthy)))))

(describe "kanban--relative-deadline"
  (it "labels overdue, today, and future days"
    (expect (substring-no-properties (kanban--relative-deadline -1)) :to-equal "-1d")
    (expect (substring-no-properties (kanban--relative-deadline 0)) :to-equal "today")
    (expect (substring-no-properties (kanban--relative-deadline 3)) :to-equal "3d"))

  (it "faces overdue, due-soon, and later deadlines distinctly"
    (expect (get-text-property 0 'face (kanban--relative-deadline -1)) :to-equal 'kanban-overdue)
    (expect (get-text-property 0 'face (kanban--relative-deadline 1)) :to-equal 'kanban-due-soon)
    (expect (get-text-property 0 'face (kanban--relative-deadline 9)) :to-equal 'kanban-card-meta)))

(describe "kanban--card-tags-string"
  (it "is empty for no tags"
    (expect (kanban--card-tags-string nil 20) :to-equal ""))

  (it "boxes each fitting tag (default style), faced dim, space-separated"
    (let* ((kanban-tag-pill-style 'box)
            (s (kanban--card-tags-string '("work" "api") 20)))
      ;; the box is a face attribute, so it adds no columns
      (expect (substring-no-properties s) :to-equal "work api")
      (let ((face (get-text-property 0 'face s)))
        (expect (memq 'kanban-card-tag (if (listp face) face (list face))) :to-be-truthy)
        (expect (assq :box (if (listp face) face nil)) :not :to-be nil))))

  (it "flanks each tag with caps when style is `caps'"
    (let* ((kanban-tag-pill-style 'caps)
            (left (car kanban-tag-pill-caps))
            (right (cdr kanban-tag-pill-caps))
            (s (kanban--card-tags-string '("work" "api") 20)))
      (expect (substring-no-properties s)
        :to-equal (concat left "work" right " " left "api" right))
      (expect (get-text-property 0 'face s) :to-equal 'kanban-card-tag)))

  (it "summarizes overflow as a trailing +N"
    (expect (substring-no-properties
              (kanban--card-tags-string '("alpha" "beta" "gamma" "delta") 12))
      :to-match "\\+[0-9]+\\'")))

(describe "kanban--progress-bar"
  (it "is nil with no progress"
    (expect (kanban--progress-bar nil) :to-be nil))

  (it "fills proportionally to DONE/TOTAL (faced)"
    (let ((kanban-progress-bar-width 3))
      (expect (substring-no-properties (kanban--progress-bar '(0 . 3))) :to-equal "▱▱▱")
      (expect (substring-no-properties (kanban--progress-bar '(1 . 3))) :to-equal "▰▱▱")
      (expect (substring-no-properties (kanban--progress-bar '(3 . 3))) :to-equal "▰▰▰")
      (expect (get-text-property 0 'face (kanban--progress-bar '(1 . 3)))
        :to-equal 'kanban-card-meta))))

(describe "kanban--deadline-badge"
  (it "is nil with no deadline"
    (expect (kanban--deadline-badge '(:title "x")) :to-be nil))

  (it "includes a due icon and the relative day label"
    (let ((badge (kanban--deadline-badge (list :deadline (format-time-string "<%Y-%m-%d %a>")))))
      (expect (substring-no-properties badge) :to-match "today"))))

(describe "kanban--scheduled-badge"
  (it "is nil with no scheduled date"
    (expect (kanban--scheduled-badge '(:title "x")) :to-be nil))

  (it "renders a dim relative badge with a start icon (no arrow)"
    (let ((badge (kanban--scheduled-badge
                   (list :scheduled (format-time-string "<%Y-%m-%d %a>"
                                      (time-add (current-time) (days-to-time 3)))))))
      (expect (substring-no-properties badge) :to-match "[0-9]d")
      (expect (substring-no-properties badge) :not :to-match "→")
      (let ((pos (string-match "[0-9]" badge)))
        (expect (get-text-property pos 'face badge) :to-equal 'kanban-card-meta)))))

(describe "kanban--dates-cluster"
  (it "shows a single badge when only one date is present"
    (expect (substring-no-properties
              (kanban--dates-cluster (list :deadline (format-time-string "<%Y-%m-%d %a>"))))
      :to-match "today"))

  (it "collapses both dates into one compact DL/SCHd badge"
    (let* ((dl (format-time-string "<%Y-%m-%d %a>" (time-add (current-time) (days-to-time 1))))
            (sch (format-time-string "<%Y-%m-%d %a>" (time-add (current-time) (days-to-time 3))))
            (badge (kanban--dates-cluster (list :deadline dl :scheduled sch))))
      (expect (substring-no-properties badge) :to-match "1/3d")))

  (it "colors the deadline part by urgency and dims the scheduled part"
    (let* ((dl (format-time-string "<%Y-%m-%d %a>")) ; today -> due-soon
            (sch (format-time-string "<%Y-%m-%d %a>" (time-add (current-time) (days-to-time 3))))
            (badge (kanban--dates-cluster (list :deadline dl :scheduled sch)))
            (raw (substring-no-properties badge)))
      ;; deadline digit "0" is urgency-colored
      (expect (get-text-property (string-match "0" raw) 'face badge) :to-equal 'kanban-due-soon)
      ;; the "/" that opens the scheduled part is dim
      (expect (get-text-property (string-match "/" raw) 'face badge) :to-equal 'kanban-card-meta))))

(describe "kanban--card-classify-cell"
  (it "is nil when the card has no priority or tags"
    (expect (kanban--card-classify-cell '(:title "x")) :to-be nil))

  (it "renders the priority pill when present"
    (let ((org-priority-faces '((?A :foreground "#ff0000"))))
      (expect (kanban--card-classify-cell '(:title "x" :priority ?A)) :not :to-be nil)))

  (it "renders tags when present"
    (expect (substring-no-properties
              (kanban-tests--render (kanban--card-classify-cell '(:title "x" :tags ("work")))))
      :to-match "work")))

(describe "kanban--card-bottom-cell"
  (it "is nil when the card has no progress, deadline, or scheduled date"
    (expect (kanban--card-bottom-cell '(:title "x")) :to-be nil))

  (it "puts the progress bar (left) and dates (right) on one row"
    (let ((kanban-progress-bar-width 3))
      (let ((rendered (substring-no-properties
                        (kanban-tests--render
                          (kanban--card-bottom-cell
                            (list :title "x" :progress '(1 . 3)
                              :deadline (format-time-string "<%Y-%m-%d %a>")))))))
        (expect rendered :to-match "▰▱▱")
        (expect rendered :to-match "today"))))

  (it "shows the CLOSED badge in the right slot for done cards"
    (let* ((closed (format-time-string "[%Y-%m-%d %a %H:%M]"
                     (time-subtract (current-time) (days-to-time 2))))
            (rendered (substring-no-properties
                        (kanban-tests--render
                          (kanban--card-bottom-cell (list :title "x" :closed closed))))))
      (expect rendered :to-match "2d ago")))

  (it "appends the repeat glyph when the task repeats"
    (let ((rendered (substring-no-properties
                      (kanban-tests--render
                        (kanban--card-bottom-cell
                          (list :title "x" :deadline (format-time-string "<%Y-%m-%d %a>")
                            :repeat "+1w"))))))
      (expect rendered :to-match (regexp-quote kanban-repeat-icon))))

  (it "shows the blocked marker on the left"
    (let ((rendered (substring-no-properties
                      (kanban-tests--render
                        (kanban--card-bottom-cell '(:title "x" :blocked t))))))
      (expect rendered :to-match (regexp-quote kanban-blocked-icon)))))

(describe "kanban--tag-face"
  (it "returns the configured Org face for a tag in `org-tag-faces'"
    (let ((org-tag-faces '(("api" . "#ff8800"))))
      (expect (kanban--tag-face "api") :to-equal '(:inherit org-tag :foreground "#ff8800"))))

  (it "falls back to `kanban-card-tag' for an unconfigured tag"
    (let ((org-tag-faces '(("api" . "#ff8800"))))
      (expect (kanban--tag-face "frontend") :to-equal 'kanban-card-tag))))

(describe "kanban--card-markers"
  (it "is nil with no active clock or block"
    (expect (kanban--card-markers '(:title "x")) :to-be nil))

  (it "renders active-clock and blocked glyphs"
    (let ((m (substring-no-properties (kanban--card-markers '(:clock-active t :blocked t)))))
      (expect m :to-match (regexp-quote kanban-clock-active-icon))
      (expect m :to-match (regexp-quote kanban-blocked-icon)))))

(describe "kanban--priority-pill"
  (it "is nil when there is no priority"
    (expect (kanban--priority-pill nil) :to-be nil))

  (it "renders the priority letter on a colored pill"
    (let ((org-priority-faces '((?A :foreground "#ff0000"))))
      (let* ((pill (kanban--priority-pill ?A))
              (pos (string-match "A" pill)))
        (expect pos :to-be-truthy)
        (expect (plist-get (get-text-property pos 'face pill) :background)
          :to-equal "#ff0000")))))

(describe "kanban--board render"
  (it "renders the default Todo and Done columns with the seeded cards"
    (expect (kanban-tests--render (kanban--board kanban-columns))
      :to-render-substrings '("TODO" "DONE" "My first card" "My second card")))

  (it "renders headers bold and without an underline"
    (with-temp-buffer
      (vui-render (kanban--board kanban-columns))
      (goto-char (point-min))
      (search-forward "TODO")
      (let ((face (get-text-property (match-beginning 0) 'face)))
        (expect (member '(:weight bold :underline nil)
                  (if (listp face) face (list face)))
          :to-be-truthy))))

  (it "separates the header from the first card with a blank row"
    (let ((lines (split-string (kanban-tests--render (kanban--board kanban-columns)) "\n")))
      (expect (string-match-p "My first card" (nth 1 lines)) :to-be nil)))

  (it "stacks multiple cards as distinct rows in a column"
    (let* ((rendered (kanban-tests--render
                       (kanban--board '((:name "Todo"
                                          :items ((:title "Card A") (:title "Card B")))))))
            (lines (split-string rendered "\n")))
      (expect (seq-find (lambda (line) (string-match-p "Card A" line)) lines) :to-be-truthy)
      (expect (seq-find (lambda (line) (string-match-p "Card B" line)) lines) :to-be-truthy)
      (expect (seq-find (lambda (line) (and (string-match-p "Card A" line)
                                         (string-match-p "Card B" line)))
                lines)
        :to-be nil)))

  (it "lays the columns out side by side (both headers on one line)"
    (let* ((rendered (kanban-tests--render (kanban--board kanban-columns)))
            (header-line (seq-find (lambda (line) (string-match-p "TODO" line))
                           (split-string rendered "\n"))))
      (expect header-line :to-match "TODO")
      (expect header-line :to-match "DONE")))

  (it "renders without table grid lines (kanban lanes, not a spreadsheet)"
    (expect (kanban-tests--render (kanban--board kanban-columns))
      :not :to-match "│"))

  (it "faces the column lanes with kanban-column"
    (with-temp-buffer
      (vui-render (kanban--board kanban-columns))
      (goto-char (point-min))
      (let ((face (get-text-property (point) 'face)))
        (expect (memq 'kanban-column (if (listp face) face (list face)))
          :to-be-truthy)))))

(describe "kanban--rows fill"
  (it "pads with empty lane rows up to MIN-ROWS"
    (expect (length (kanban--rows '((:name "Todo" :items ((:title "a")))) 5))
      :to-equal 5))

  (it "never shrinks content below its card rows"
    (let ((kanban-card-padding-rows 0))
      (expect (length (kanban--rows '((:name "Todo" :items ((:title "a") (:title "b")))) 2))
        :to-equal 3))))

(describe "kanban-card-padding-rows"
  (it "wraps content with blank card rows above and below (symmetric)"
    (let ((kanban-card-padding-rows 1))
      ;; one bare card: pad-above + title + pad-below = 3 rows
      (expect (length (kanban--rows '((:name "Todo" :items ((:title "a")))))) :to-equal 3)))

  (it "renders just the content rows when 0"
    (let ((kanban-card-padding-rows 0))
      (expect (length (kanban--rows '((:name "Todo" :items ((:title "a")))))) :to-equal 1))))

(describe "kanban-card-gap"
  (it "separates cards by exactly kanban-card-gap blank rows (independent of padding)"
    (let ((kanban-card-padding-rows 0)
           (kanban-card-gap 2))
      ;; two 1-row cards + a 2-row gap between them
      (expect (length (kanban--rows '((:name "Todo" :items ((:title "a") (:title "b"))))))
        :to-equal 4))))

(describe "kanban--board fill"
  (it "fills the board to TOTAL-LINES"
    (expect (length (split-string
                      (kanban-tests--render
                        (kanban--board '((:name "Todo" :items ((:title "a")))) 6))
                      "\n"))
      :to-equal 6)))

(describe "kanban--read-board (org-agenda-backed)"
  (it "derives columns from the file's TODO keywords, in order"
    (expect (mapcar #'kanban-column-name
              (kanban--read-board (list (kanban-tests--fixture "board.org"))))
      :to-equal '("TODO" "NEXT" "WAIT" "DONE" "CANCELLED")))

  (it "buckets each entry into its TODO-state column"
    (let ((board (kanban--read-board (list (kanban-tests--fixture "board.org")))))
      (expect (mapcar #'kanban-card-title (kanban-column-items (kanban-tests--column "TODO" board)))
        :to-equal '("Buy milk"))
      (expect (mapcar #'kanban-card-title (kanban-column-items (kanban-tests--column "NEXT" board)))
        :to-equal '("Ship release"))
      (expect (kanban-column-count (kanban-tests--column "WAIT" board)) :to-equal 0)
      (expect (mapcar #'kanban-card-title (kanban-column-items (kanban-tests--column "DONE" board)))
        :to-equal '("Old thing"))))

  (it "orders cards within a column by priority, highest first"
    (let* ((board (kanban--read-board (list (kanban-tests--fixture "priorities.org"))))
            (todo (kanban-tests--column "TODO" board)))
      (expect (mapcar #'kanban-card-title (kanban-column-items todo))
        :to-equal '("High one" "Middle one" "Low one"))))

  (it "records each card's TODO state and a marker for write-back"
    (let* ((board (kanban--read-board (list (kanban-tests--fixture "board.org"))))
            (card (car (kanban-column-items (kanban-tests--column "TODO" board)))))
      (expect (plist-get card :state) :to-equal "TODO")
      (expect (plist-get card :priority) :to-equal ?A)
      (expect (markerp (plist-get card :marker)) :to-be-truthy)))

  (it "captures a deadline when the entry has one"
    (let* ((board (kanban--read-board (list (kanban-tests--fixture "board.org"))))
            (card (car (kanban-column-items (kanban-tests--column "NEXT" board)))))
      (expect (plist-get card :deadline) :to-match "2026-07-01")))

  (it "captures local tags when the entry has them"
    (let* ((board (kanban--read-board (list (kanban-tests--fixture "board.org"))))
            (card (car (kanban-column-items (kanban-tests--column "NEXT" board)))))
      (expect (plist-get card :tags) :to-equal '("work" "urgent"))))

  (it "captures an effort estimate when the entry has one"
    (let* ((board (kanban--read-board (list (kanban-tests--fixture "board.org"))))
            (card (car (kanban-column-items (kanban-tests--column "NEXT" board)))))
      (expect (plist-get card :effort) :to-equal "2:00")))

  (it "captures the Org category"
    (let* ((board (kanban--read-board (list (kanban-tests--fixture "board.org"))))
            (card (car (kanban-column-items (kanban-tests--column "NEXT" board)))))
      (expect (plist-get card :category) :to-equal "Demo"))))

(describe "kanban--parse-progress"
  (it "parses an [N/M] cookie into (DONE . TOTAL)"
    (expect (kanban--parse-progress "Build lander [1/3]") :to-equal '(1 . 3)))
  (it "is nil without a cookie"
    (expect (kanban--parse-progress "Plain title") :to-be nil)))

(describe "enriched card capture (rich.org)"
  (it "captures scheduled, id, outline path, progress, clocked time, and properties"
    (let ((card (kanban-tests--first-card "rich.org" "TODO")))
      (expect (kanban-card-scheduled card) :to-match "2026-07-02")
      (expect (kanban-card-id card) :to-equal "lander-1")
      (expect (kanban-card-outline-path card) :to-equal '("Project Apollo"))
      (expect (kanban-card-progress card) :to-equal '(1 . 3))
      (expect (kanban-card-clocked card) :to-equal 90)
      (expect (kanban-card-property card "ASSIGNEE") :to-equal "Mei")))

  (it "captures the CLOSED timestamp on a done card"
    (let ((card (kanban-tests--first-card "rich.org" "DONE")))
      (expect (kanban-card-closed card) :to-match "2026-06-29"))))

(describe "kanban--entry-group (read-time :group capture)"
  (it "captures no group when grouping is off"
    (let ((kanban-group-by nil))
      (expect (plist-get (kanban-tests--first-card "board.org" "NEXT") :group) :to-be nil)))

  (it "captures the category when grouping by category"
    (let ((kanban-group-by 'category))
      (expect (plist-get (kanban-tests--first-card "board.org" "NEXT") :group) :to-equal "Demo")))

  (it "captures an Org property when grouping by a property name"
    (let ((kanban-group-by "Effort"))
      (expect (plist-get (kanban-tests--first-card "board.org" "NEXT") :group) :to-equal "2:00")))

  (it "captures the priority (or a placeholder) when grouping by priority"
    (let ((kanban-group-by 'priority))
      (expect (plist-get (kanban-tests--first-card "board.org" "NEXT") :group) :to-equal "No priority"))))

(describe "kanban--group-into-bands"
  (it "is a single nil band when grouping is off"
    (let ((kanban-group-by nil))
      (let ((bands (kanban--group-into-bands '((:name "T" :items ((:title "a")))))))
        (expect (length bands) :to-equal 1)
        (expect (caar bands) :to-be nil))))

  (it "splits cards into bands by category, in first-seen order"
    (let ((kanban-group-by 'category))
      (let* ((board (kanban--read-board (list (kanban-tests--fixture "swimlanes.org"))))
              (bands (kanban--group-into-bands board)))
        (expect (mapcar #'car bands) :to-equal '("Backend" "Frontend")))))

  (it "filters each band's columns to that group's cards"
    (let ((kanban-group-by 'category))
      (let* ((board (kanban--read-board (list (kanban-tests--fixture "swimlanes.org"))))
              (bands (kanban--group-into-bands board))
              (backend (cdr (assoc "Backend" bands))))
        (expect (mapcar #'kanban-card-title (kanban-column-items (kanban-tests--column "TODO" backend)))
          :to-equal '("Alpha task"))
        (expect (mapcar #'kanban-card-title (kanban-column-items (kanban-tests--column "DONE" backend)))
          :to-equal '("Gamma task"))))))

(describe "kanban--board swimlanes render"
  (it "renders a band header per category with its cards beneath"
    (let ((kanban-group-by 'category))
      (let ((rendered (kanban-tests--render
                        (kanban--board (kanban--read-board
                                         (list (kanban-tests--fixture "swimlanes.org")))))))
        (expect rendered :to-match "Backend")
        (expect rendered :to-match "Frontend")
        (expect rendered :to-match "Alpha task")))))

(describe "kanban--board-columns (source dispatch)"
  (it "uses the demo columns when kanban-org-files is nil"
    (let ((kanban-org-files nil))
      (expect (kanban--board-columns) :to-equal kanban-columns)))

  (it "reads the given Org files when kanban-org-files is a list"
    (let ((kanban-org-files (list (kanban-tests--fixture "board.org"))))
      (expect (mapcar #'kanban-column-name (kanban--board-columns))
        :to-equal '("TODO" "NEXT" "WAIT" "DONE" "CANCELLED"))))

  (it "defaults to reading the Org agenda files"
    (expect (default-value 'kanban-org-files) :to-equal t))

  (it "reads the agenda files when t, falling back to the demo board when empty"
    (let ((kanban-org-files t))
      (spy-on 'kanban--read-board :and-return-value nil)
      (expect (kanban--board-columns) :to-equal kanban-columns)
      (expect 'kanban--read-board :to-have-been-called))))

(describe "kanban (interactive entry point)"
  (before-each (spy-on 'switch-to-buffer))
  (after-each
    (when (get-buffer kanban-buffer-name)
      (let (kill-buffer-query-functions)
        (kill-buffer kanban-buffer-name))))

  (it "mounts the board into the *kanban* buffer"
    ;; Pin off vui's deferred render so the mount paint is synchronous.
    (let ((vui-render-delay nil))
      (kanban)
      (let ((buffer (get-buffer kanban-buffer-name)))
        (expect (buffer-live-p buffer))
        (with-current-buffer buffer
          (expect (buffer-string) :to-match "My first card")))))

  (it "labels the modeline \"kanban-mode\" without renaming the shared vui-mode"
    (kanban)
    (with-current-buffer kanban-buffer-name
      (expect mode-name :to-equal "kanban-mode"))))

;;; kanban-tests.el ends here
