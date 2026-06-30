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
  (it "follows the label with a dim box-drawing rule"
    (expect (substring-no-properties
              (kanban--header-cell-content '(:name "Todo" :items ((:title "a")))))
      :to-match (concat "\\`" (regexp-quote "TODO (1) ") "─+"))))

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
    (expect (length (kanban--rows
                      '((:name "A" :items ((:title "a1") (:title "a2")))
                         (:name "B" :items ((:title "b1"))))))
      :to-equal 2))

  (it "is empty when no column has cards"
    (expect (kanban--rows '((:name "A" :items nil) (:name "B" :items nil)))
      :to-equal nil)))

(describe "kanban--card"
  (it "renders the title inside a faced card tile"
    (with-temp-buffer
      (vui-render (kanban--card '(:title "Ship it")))
      (expect (buffer-string) :to-match "Ship it")
      (goto-char (point-min))
      (search-forward "Ship")
      (expect (get-text-property (match-beginning 0) 'face) :to-equal 'kanban-card)))

  (it "truncates an over-long title with an ellipsis and keeps the tile width"
    (let ((rendered (substring-no-properties
                      (kanban-tests--render
                        (kanban--card '(:title "This is an extremely long card title"))))))
      (expect rendered :to-match "…")
      (expect (string-width rendered) :to-equal (- kanban-column-width 2)))))

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
    (expect (length (kanban--rows '((:name "Todo" :items ((:title "a") (:title "b")))) 2))
      :to-equal 3)))

(describe "kanban--board fill"
  (it "fills the board to TOTAL-LINES"
    (expect (length (split-string
                      (kanban-tests--render
                        (kanban--board '((:name "Todo" :items ((:title "a")))) 6))
                      "\n"))
      :to-equal 6)))

(describe "kanban (interactive entry point)"
  (before-each (spy-on 'switch-to-buffer))
  (after-each
    (when (get-buffer kanban-buffer-name)
      (let (kill-buffer-query-functions)
        (kill-buffer kanban-buffer-name))))

  (it "mounts the board into the *kanban* buffer"
    (kanban)
    (let ((buffer (get-buffer kanban-buffer-name)))
      (expect (buffer-live-p buffer))
      (with-current-buffer buffer
        (expect (buffer-string) :to-match "My first card")))))

;;; kanban-tests.el ends here
