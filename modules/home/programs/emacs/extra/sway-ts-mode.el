;;; sway-ts-mode.el --- tree-sitter support for Sway  -*- lexical-binding: t; -*-

;; Copyright (C) 2022-2025 Free Software Foundation, Inc.

;; Author     : Morgan Smith <Morgan.J.Smith@outlook.com>
;; Maintainer : Morgan Smith <Morgan.J.Smith@outlook.com>
;; Created    : December 2022
;; Keywords   : sway languages tree-sitter

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Tree-sitter language versions
;;
;; sway-ts-mode is known to work with the following languages and version:
;; - tree-sitter-sway: v1.0.0
;;
;; We try our best to make builtin modes work with latest grammar
;; versions, so a more recent grammar version has a good chance to work.
;; Send us a bug report if it doesn't.

;;; Commentary:
;;
;; This is based off of `rust-ts-mode' originally written by Randy Taylor
;; <dev@rjt.dev>.

;;; Code:

(require 'treesit)
(eval-when-compile (require 'rx))
(require 'c-ts-common) ; For comment indent and filling.
(treesit-declare-unavailable-functions)

(add-to-list
 'treesit-language-source-alist
 '(sway "https://github.com/FuelLabs/tree-sitter-sway" "v1.0.0")
 t)

(defcustom sway-ts-mode-indent-offset 4
  "Number of spaces for each indentation step in `sway-ts-mode'."
  :version "29.1"
  :type 'integer
  :safe 'integerp
  :group 'sway)

(defcustom sway-ts-mode-fontify-number-suffix-as-type nil
  "If non-nil, suffixes of number literals are fontified as types.
In Sway, number literals can possess an optional type suffix.  When this
variable is non-nil, these suffixes are fontified using
`font-lock-type-face' instead of `font-lock-number-face'."
  :version "31.1"
  :type 'boolean
  :group 'sway)

(defvar sway-ts-mode-prettify-symbols-alist
  '(("&&" . ?∧) ("||" . ?∨)
    ("<=" . ?≤)  (">=" . ?≥) ("!=" . ?≠)
    ("INFINITY" . ?∞) ("->" . ?→) ("=>" . ?⇒))
  "Value for `prettify-symbols-alist' in `sway-ts-mode'.")

(defvar sway-ts-mode--syntax-table
  (let ((table (make-syntax-table)))
    (modify-syntax-entry ?+   "."      table)
    (modify-syntax-entry ?-   "."      table)
    (modify-syntax-entry ?=   "."      table)
    (modify-syntax-entry ?%   "."      table)
    (modify-syntax-entry ?&   "."      table)
    (modify-syntax-entry ?|   "."      table)
    (modify-syntax-entry ?^   "."      table)
    (modify-syntax-entry ?!   "."      table)
    (modify-syntax-entry ?@   "."      table)
    (modify-syntax-entry ?~   "."      table)
    (modify-syntax-entry ?<   "."      table)
    (modify-syntax-entry ?>   "."      table)
    (modify-syntax-entry ?/   ". 124b" table)
    (modify-syntax-entry ?*   ". 23"   table)
    (modify-syntax-entry ?\n  "> b"    table)
    (modify-syntax-entry ?\^m "> b"    table)
    table)
  "Syntax table for `sway-ts-mode'.")

(defvar sway-ts-mode--indent-rules
  `((sway
     ((parent-is "source_file") column-0 0)
     ((node-is ")") parent-bol 0)
     ((node-is "]") parent-bol 0)
     ((node-is "}") (and parent parent-bol) 0)
     ((and (parent-is "comment") c-ts-common-looking-at-star)
      c-ts-common-comment-start-after-first-star -1)
     ((parent-is "comment") prev-adaptive-prefix 0)
     ((parent-is "arguments") parent-bol sway-ts-mode-indent-offset)
     ((parent-is "array_expression") parent-bol sway-ts-mode-indent-offset)
     ((parent-is "binary_expression") parent-bol sway-ts-mode-indent-offset)
     ((parent-is "block") parent-bol sway-ts-mode-indent-offset)
     ((parent-is "declaration_list") parent-bol sway-ts-mode-indent-offset)
     ((parent-is "enum_variant_list") parent-bol sway-ts-mode-indent-offset)
     ((parent-is "field_declaration_list") parent-bol sway-ts-mode-indent-offset)
     ((parent-is "field_expression") parent-bol sway-ts-mode-indent-offset)
     ((parent-is "field_initializer_list") parent-bol sway-ts-mode-indent-offset)
     ((parent-is "let_declaration") parent-bol sway-ts-mode-indent-offset)
     ((parent-is "parameters") parent-bol sway-ts-mode-indent-offset)
     ((parent-is "struct_pattern") parent-bol sway-ts-mode-indent-offset)
     ((parent-is "token_tree") parent-bol sway-ts-mode-indent-offset)
     ((parent-is "use_list") parent-bol sway-ts-mode-indent-offset)))
  "Tree-sitter indent rules for `sway-ts-mode'.")

(defconst sway-ts-mode--number-types
  (regexp-opt '("u8" "i8" "u16" "i16" "u32" "i32" "u64"
                "i64" "u128" "i128" "usize" "isize" "f32" "f64"
                ;; Sway specific
                "u256" "i256" "b256"))
  "Regexp matching type suffixes of number literals.")

(defvar sway-ts-mode--keywords
  '("abi" "as" "break" "configurable" "const" "continue" "default" "else"
    "enum" "fn" "for" "if" "impl" "in" "let" "match"
    "move" "pub" "ref" "return" "storage" "struct" "trait"
    "use" "where" "while" (self)
    (mutable_specifier))
  "Sway keywords for tree-sitter font-locking.")

(defvar sway-ts-mode--operators
  '("!"  "!=" "%" "%=" "&" "&=" "&&" "*" "*=" "+" "+=" "," "-" "-="
    "->" "."  ".."  "..=" "..."  "/" "/=" ":" ";" "<<" "<<=" "<" "<="
    "=" "==" "=>" ">" ">=" ">>" ">>=" "@" "^" "^=" "|" "|=" "||" "?")
  "Sway operators for tree-sitter font-locking.")

(defvar sway-ts-mode--font-lock-settings
  (treesit-font-lock-rules
   :language 'sway
   :feature 'attribute
   '((attribute_item) @font-lock-preprocessor-face
     (inner_attribute_item) @font-lock-preprocessor-face)

   :language 'sway
   :feature 'bracket
   '((["(" ")" "[" "]" "{" "}"]) @font-lock-bracket-face)

   :language 'sway
   :feature 'comment
   '(([(block_comment) (line_comment)]) @sway-ts-mode--comment-docstring)

   :language 'sway
   :feature 'delimiter
   '((["," "." ";" ":" "::"]) @font-lock-delimiter-face)

   :language 'sway
   :feature 'definition
   '((function_item name: (identifier) @font-lock-function-name-face)
     (function_signature_item name: (identifier) @font-lock-function-name-face)
     (field_declaration name: (field_identifier) @font-lock-property-name-face)
     (parameter pattern: (_) @sway-ts-mode--fontify-pattern)
     (closure_parameters (_) @sway-ts-mode--fontify-pattern)
     (let_declaration pattern: (_) @sway-ts-mode--fontify-pattern)
     (for_expression pattern: (_) @sway-ts-mode--fontify-pattern)
     (let_condition pattern: (_) @sway-ts-mode--fontify-pattern)
     (match_arm pattern: (_) @sway-ts-mode--fontify-pattern))

   :language 'sway
   :feature 'assignment
   '((assignment_expression left: (_) @sway-ts-mode--fontify-pattern)
     (compound_assignment_expr left: (_) @sway-ts-mode--fontify-pattern))

   :language 'sway
   :feature 'function
   '((call_expression
      function:
      [(identifier) @font-lock-function-call-face
       (field_expression
        field: (field_identifier) @font-lock-function-call-face)
       (scoped_identifier
        name: (identifier) @font-lock-function-call-face)])
     (generic_function
      function: [(identifier) @font-lock-function-call-face
                 (field_expression
                  field: (field_identifier) @font-lock-function-call-face)
                 (scoped_identifier
                  name: (identifier) @font-lock-function-call-face)]))

   :language 'sway
   :feature 'keyword
   `([,@sway-ts-mode--keywords] @font-lock-keyword-face
     ;; If these keyword are in a macro body, they're marked as
     ;; identifiers.
     ((identifier) @font-lock-keyword-face
      (:match ,(rx bos (or "else" "in" "move") eos) @font-lock-keyword-face)))

   :language 'sway
   :feature 'number
   '([(float_literal) (integer_literal)]
     @sway-ts-mode--fontify-number-literal)

   :language 'sway
   :feature 'operator
   `([,@sway-ts-mode--operators] @font-lock-operator-face)

   :language 'sway
   :feature 'string
   '([(char_literal)
      (raw_string_literal)
      (string_literal)] @font-lock-string-face)

   :language 'sway
   :feature 'type
   `((scoped_use_list path: (identifier) @font-lock-constant-face)
     (scoped_use_list path: (scoped_identifier
                             name: (identifier) @font-lock-constant-face))
     ((use_as_clause alias: (identifier) @font-lock-type-face)
      (:match "\\`[A-Z]" @font-lock-type-face))
     ((use_as_clause path: (identifier) @font-lock-type-face)
      (:match "\\`[A-Z]" @font-lock-type-face))
     ((use_list (identifier) @font-lock-type-face)
      (:match "\\`[A-Z]" @font-lock-type-face))
     (use_wildcard [(identifier) @sway-ts-mode--fontify-scope
                    (scoped_identifier
                     name: (identifier) @sway-ts-mode--fontify-scope)])
     (enum_variant name: (identifier) @font-lock-type-face)
     (match_arm
      pattern: (match_pattern (_ type: (identifier) @font-lock-type-face)))
     (match_arm
      pattern: (match_pattern
                (_ type: (scoped_identifier
                          path: (identifier) @font-lock-type-face))))
     ((scoped_identifier name: (identifier) @sway-ts-mode--fontify-tail))
     ((scoped_identifier path: (identifier) @font-lock-type-face)
      (:match ,(rx bos
                   (or
                    (regexp sway-ts-mode--number-types)
                    "bool" "char" "str")
                   eos)
              @font-lock-type-face))
     ((scoped_identifier path: (identifier) @sway-ts-mode--fontify-scope))
     ((scoped_type_identifier path: (identifier) @sway-ts-mode--fontify-scope))
     ;; Sometimes the parser can't determine if an identifier is a type,
     ;; so we use this heuristic. See bug#69625 for the full discussion.
     ((identifier) @font-lock-type-face
      (:match ,(rx bos upper) @font-lock-type-face)))

   :language 'sway
   :feature 'property
   '((field_identifier) @font-lock-property-use-face
     (shorthand_field_initializer (identifier) @font-lock-property-use-face))

   ;; Must be under type, otherwise some imports can be highlighted as constants.
   :language 'sway
   :feature 'constant
   `((boolean_literal) @font-lock-constant-face
     ((identifier) @font-lock-constant-face
      (:match "\\`[A-Z][0-9A-Z_]*\\'" @font-lock-constant-face)))

   :language 'sway
   :feature 'variable
   '((arguments (identifier) @font-lock-variable-use-face)
     (array_expression (identifier) @font-lock-variable-use-face)
     (assignment_expression right: (identifier) @font-lock-variable-use-face)
     (binary_expression left: (identifier) @font-lock-variable-use-face)
     (binary_expression right: (identifier) @font-lock-variable-use-face)
     (block (identifier) @font-lock-variable-use-face)
     (compound_assignment_expr right: (identifier) @font-lock-variable-use-face)
     (field_expression value: (identifier) @font-lock-variable-use-face)
     (field_initializer value: (identifier) @font-lock-variable-use-face)
     (if_expression condition: (identifier) @font-lock-variable-use-face)
     (let_condition value: (identifier) @font-lock-variable-use-face)
     (let_declaration value: (identifier) @font-lock-variable-use-face)
     (match_arm value: (identifier) @font-lock-variable-use-face)
     (match_expression value: (identifier) @font-lock-variable-use-face)
     (reference_expression value: (identifier) @font-lock-variable-use-face)
     (return_expression (identifier) @font-lock-variable-use-face)
     (tuple_expression (identifier) @font-lock-variable-use-face)
     (unary_expression (identifier) @font-lock-variable-use-face)
     (while_expression condition: (identifier) @font-lock-variable-use-face)
     (metavariable) @font-lock-variable-use-face)

   :language 'sway
   :feature 'escape-sequence
   :override t
   '((escape_sequence) @font-lock-escape-face)

   :language 'sway
   :feature 'error
   :override t
   '((ERROR) @font-lock-warning-face))
  "Tree-sitter font-lock settings for `sway-ts-mode'.")

(defun sway-ts-mode--comment-docstring (node override start end &rest _args)
  "Use the comment or documentation face appropriately for comments."
  (let* ((beg (treesit-node-start node))
         (face (save-excursion
                 (goto-char beg)
                 (if (looking-at-p
                      "/\\(?:/\\(?:/[^/]\\|!\\)\\|\\*\\(?:\\*[^*/]\\|!\\)\\)")
                     'font-lock-doc-face
                   'font-lock-comment-face))))
    (treesit-fontify-with-override beg (treesit-node-end node)
                                   face override start end)))

(defun sway-ts-mode--fontify-scope (node override start end &optional tail-p)
  (let* ((case-fold-search nil)
         (face
          (cond
           ((string-match-p "^[A-Z]" (treesit-node-text node))
            'font-lock-type-face)
           ((and
             tail-p
             (string-match-p
              "\\`\\(?:use_list\\|call_expression\\|use_as_clause\\|use_declaration\\)\\'"
              (treesit-node-type (treesit-node-parent (treesit-node-parent node)))))
            nil)
           (t 'font-lock-constant-face))))
    (when face
      (treesit-fontify-with-override
       (treesit-node-start node) (treesit-node-end node)
       face
       override start end))))

(defun sway-ts-mode--fontify-tail (node override start end)
  (sway-ts-mode--fontify-scope node override start end t))

(defalias 'sway-ts-mode--fontify-pattern
  (and
   (treesit-available-p)
   `(lambda (node override start end &rest _)
      (let ((captures (treesit-query-capture
                       node
                       ,(treesit-query-compile 'sway '((identifier) @id
                                                       (shorthand_field_identifier) @id)))))
        (pcase-dolist (`(_name . ,id) captures)
          (unless (string-match-p "\\`scoped_\\(?:type_\\)?identifier\\'"
                                  (treesit-node-type
                                   (treesit-node-parent id)))
            (treesit-fontify-with-override
             (treesit-node-start id) (treesit-node-end id)
             'font-lock-variable-name-face override start end)))))))

(defun sway-ts-mode--fontify-number-literal (node override start stop &rest _)
  "Fontify number literals, highlighting the optional type suffix.
If `sway-ts-mode-fontify-number-suffix-as-type' is non-nil, use
`font-lock-type-face' to highlight the suffix."
  (let* ((beg (treesit-node-start node))
         (end (treesit-node-end node)))
    (save-excursion
      (goto-char end)
      (if (and sway-ts-mode-fontify-number-suffix-as-type
               (looking-back sway-ts-mode--number-types beg))
          (let* ((ty (match-beginning 0))
                 (nb (if (eq (char-before ty) ?_) (1- ty) ty)))
            (treesit-fontify-with-override
             ty end 'font-lock-type-face override start stop)
            (treesit-fontify-with-override
             beg nb 'font-lock-number-face override start stop))
        (treesit-fontify-with-override
         beg end 'font-lock-number-face override start stop)))))

(defun sway-ts-mode--defun-name (node)
  "Return the defun name of NODE.
Return nil if there is no name or if NODE is not a defun node."
  (pcase (treesit-node-type node)
    ("enum_item"
     (treesit-node-text
      (treesit-node-child-by-field-name node "name") t))
    ("function_item"
     (treesit-node-text
      (treesit-node-child-by-field-name node "name") t))
    ("impl_item"
     (let ((trait-node (treesit-node-child-by-field-name node "trait")))
       (concat
        (treesit-node-text trait-node t)
        (when trait-node " for ")
        (treesit-node-text
         (treesit-node-child-by-field-name node "type") t))))
    ("struct_item"
     (treesit-node-text
      (treesit-node-child-by-field-name node "name") t))
    ("type_item"
     (treesit-node-text
      (treesit-node-child-by-field-name node "name") t))))

(defun sway-ts-mode--syntax-propertize (beg end)
  "Apply syntax properties to special characters between BEG and END.

Apply syntax properties to various special characters with
contextual meaning between BEG and END.

The apostrophe \\=' should be treated as string when used for char literals.

< and > are usually punctuation, e.g., as greater/less-than.  But
when used for types, they should be considered pairs.

This function checks for < and > in the changed RANGES and apply
appropriate text property to alter the syntax of template
delimiters < and >'s."
  (goto-char beg)
  (while (search-forward "'" end t)
    (when (string-equal "char_literal"
                        (treesit-node-type
                         (treesit-node-at (match-beginning 0))))
      (put-text-property (match-beginning 0) (match-end 0)
                         'syntax-table (string-to-syntax "\""))))
  (goto-char beg)
  (while (re-search-forward (rx (or "<" ">")) end t)
    (pcase (treesit-node-type
            (treesit-node-parent
             (treesit-node-at (match-beginning 0))))
      ((or "type_arguments" "type_parameters")
       (put-text-property (match-beginning 0)
                          (match-end 0)
                          'syntax-table
                          (pcase (char-before)
                            (?< '(4 . ?>))
                            (?> '(5 . ?<))))))))

(defun sway-ts-mode--prettify-symbols-compose-p (start end match)
  "Return non-nil if the symbol MATCH should be composed.
See `prettify-symbols-compose-predicate'."
  (and (fboundp 'prettify-symbols-default-compose-p)
       (prettify-symbols-default-compose-p start end match)
       ;; Make sure || is not a closure with 0 arguments and && is not
       ;; a double reference.
       (pcase match
         ((or "||" "&&")
          (string= (treesit-node-field-name (treesit-node-at (point)))
                   "operator"))
         (_ t))))

;;;###autoload
(define-derived-mode sway-ts-mode prog-mode "Sway"
  "Major mode for editing Sway, powered by tree-sitter."
  :group 'sway
  :syntax-table sway-ts-mode--syntax-table

  (when (treesit-ensure-installed 'sway)
    (setq treesit-primary-parser (treesit-parser-create 'sway))

    ;; Syntax.
    (setq-local syntax-propertize-function
                #'sway-ts-mode--syntax-propertize)

    ;; Comments.
    (c-ts-common-comment-setup)

    ;; Font-lock.
    (setq-local treesit-font-lock-settings sway-ts-mode--font-lock-settings)
    (setq-local treesit-font-lock-feature-list
                '(( comment definition)
                  ( keyword string)
                  ( assignment attribute constant escape-sequence
                               number type)
                  ( bracket delimiter error function operator property variable)))

    ;; Prettify configuration
    (setq prettify-symbols-alist sway-ts-mode-prettify-symbols-alist)
    (setq prettify-symbols-compose-predicate
          #'sway-ts-mode--prettify-symbols-compose-p)

    ;; Imenu.
    (setq-local treesit-simple-imenu-settings
                `(("Module" "\\`mod_item\\'" nil nil)
                  ("Enum" "\\`enum_item\\'" nil nil)
                  ("Impl" "\\`impl_item\\'" nil nil)
                  ("Type" "\\`type_item\\'" nil nil)
                  ("Struct" "\\`struct_item\\'" nil nil)
                  ("Fn" "\\`function_item\\'" nil nil)))

    ;; Outline.
    (setq-local treesit-outline-predicate
                (rx bos (or "mod_item"
                            "enum_item"
                            "impl_item"
                            "type_item"
                            "struct_item"
                            "function_item"
                            "trait_item")
                    eos))
    ;; Indent.
    (setq-local indent-tabs-mode nil
                treesit-simple-indent-rules sway-ts-mode--indent-rules)

    ;; Electric.
    (setq-local electric-indent-chars
                (append "{}():;,#" electric-indent-chars))

    ;; Navigation.
    (setq-local treesit-defun-type-regexp
                (regexp-opt '("enum_item"
                              "function_item"
                              "impl_item"
                              "struct_item")))
    (setq-local treesit-defun-name-function #'sway-ts-mode--defun-name)

    (setq-local treesit-thing-settings
                `((sway
                   (list
                    ,(rx bos (or "token_tree"
                                 "attribute_item"
                                 "inner_attribute_item"
                                 "declaration_list"
                                 "enum_variant_list"
                                 "field_declaration_list"
                                 "ordered_field_declaration_list"
                                 "type_parameters"
                                 "use_list"
                                 "parameters"
                                 "bracketed_type"
                                 "array_type"
                                 "tuple_type"
                                 "unit_type"
                                 "use_bounds"
                                 "type_arguments"
                                 "delim_token_tree"
                                 "arguments"
                                 "array_expression"
                                 "parenthesized_expression"
                                 "tuple_expression"
                                 "unit_expression"
                                 "field_initializer_list"
                                 "match_block"
                                 "block"
                                 "tuple_pattern"
                                 "slice_pattern")
                         eos)))))

    (treesit-major-mode-setup)))

(derived-mode-add-parents 'sway-ts-mode '(sway-mode))

(if (treesit-ready-p 'sway)
    (add-to-list 'auto-mode-alist '("\\.sw\\'" . sway-ts-mode)))

(provide 'sway-ts-mode)

;;; sway-ts-mode.el ends here
