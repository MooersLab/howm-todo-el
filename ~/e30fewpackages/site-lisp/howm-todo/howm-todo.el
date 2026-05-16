;;; howm-todo.el --- Prioritized TODO items for Howm and Org-mode -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Blaine Mooers

;; Author: Blaine Mooers <blaine-mooers@ou.edu>
;; Maintainer: Blaine Mooers <blaine-mooers@ou.edu>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: outlines, convenience, tools
;; URL: https://github.com/blaine-mooers/howm-todo

;; This file is not part of GNU Emacs.

;;; Commentary:

;; This package provides cross-compatible TODO management that works
;; in both Howm notes and Org-mode files.  The TODO marker takes the
;; form `TODO [XY]', where X is a letter that names a priority group
;; and Y is a non-negative integer that ranks the item inside the
;; group.  A larger Y indicates lower priority, so [A1] outranks
;; [A2] which outranks [A44].  Org-mode picks up the literal `TODO'
;; keyword in the agenda, and Howm leaves the line alone.
;;
;; Features:
;;   - `howm-todo-prioritize-region' adds `TODO [XY]' to each
;;     non-empty line in the selected region.  Blank lines separate
;;     priority groups, so the first contiguous block of lines is
;;     labeled A1, A2, A3..., the second block becomes B1, B2..., and
;;     so on.  Existing markers are stripped first, so the operation
;;     is idempotent.
;;   - `howm-todo-strip-region' removes every `TODO [XY]' marker from
;;     the selected region.  Use it before re-prioritizing the next
;;     day.
;;   - `howm-todo-sort-region' sorts the lines in the region by their
;;     `TODO [XY]' priority.  Unmarked lines sink to the bottom and
;;     keep their relative order.
;;   - `howm-todo-add-project-tag' reads the project name from the
;;     SQLite database referenced by `howm-todo-db-path' through
;;     `completing-read', then appends an Org-style `:project:' tag
;;     to the end of the current TODO line.
;;   - `howm-todo-tag-region' walks the selected region and prompts
;;     for a project tag once per TODO line.
;;
;; Quick start:
;;
;;   (require 'howm-todo)
;;   ;; Optionally bind keys.
;;   (define-key global-map (kbd "C-c j p") #'howm-todo-prioritize-region)
;;   (define-key global-map (kbd "C-c j s") #'howm-todo-strip-region)
;;   (define-key global-map (kbd "C-c j o") #'howm-todo-sort-region)
;;   (define-key global-map (kbd "C-c j t") #'howm-todo-add-project-tag)
;;   (define-key global-map (kbd "C-c j T") #'howm-todo-tag-region)
;;
;; SQLite backends:
;;   The package prefers the built-in sqlite library (Emacs 29 or
;;   newer compiled with --with-sqlite3).  When that library is not
;;   available it falls back to the `sqlite3' command-line shell.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(eval-when-compile (require 'rx))

;;; Customization

(defgroup howm-todo nil
  "Cross-compatible TODO prioritization for Howm and Org-mode."
  :group 'convenience
  :prefix "howm-todo-")

(defcustom howm-todo-db-path
  (expand-file-name "60003TimeTracking/cb/tenKprojects.db"
                    (or (getenv "HOME") "~"))
  "Absolute path to the SQLite database that holds project metadata."
  :type 'file
  :group 'howm-todo)

(defcustom howm-todo-db-table nil
  "Table inside `howm-todo-db-path' that holds project rows.
When nil, the package looks at every table in the database and
chooses the first one that has a column named by
`howm-todo-db-column'."
  :type '(choice (const :tag "Auto-detect" nil) string)
  :group 'howm-todo)

(defcustom howm-todo-db-column "ProjectDirectory"
  "Column in the projects table that holds the project identifier."
  :type 'string
  :group 'howm-todo)

(defcustom howm-todo-keyword "TODO"
  "Leading keyword on a prioritized line.
Both Howm and Org-mode accept the literal text TODO at the start
of a line.  Changing this value lets you adopt a different word
without forking the package."
  :type 'string
  :group 'howm-todo)

(defcustom howm-todo-tag-use-basename t
  "When non-nil, use the basename of the project path as the Org tag.
When nil, sanitize the full path.  Org tag characters are limited
to letters, digits, underscore, at-sign, and percent.  Other
characters are replaced with an underscore."
  :type 'boolean
  :group 'howm-todo)

;;; Internal regex helpers

(defun howm-todo--priority-rx ()
  "Return a regex string that matches a [XY] priority cookie."
  "\\[\\([A-Z]\\)\\([0-9]+\\)\\]")

(defun howm-todo--marker-rx ()
  "Return a regex that matches a TODO [XY] prefix on a line.
Group 1 captures any leading whitespace.  Group 2 captures the
priority letter.  Group 3 captures the priority integer."
  (concat "\\([ \t]*\\)"
          (regexp-quote howm-todo-keyword)
          "[ \t]+"
          (howm-todo--priority-rx)
          "[ \t]+"))

;;; Region prioritization

;;;###autoload
(defun howm-todo-strip-region (beg end)
  "Strip `TODO [XY]' markers from each line between BEG and END.
Leading whitespace is preserved so list indentation is unaffected."
  (interactive "r")
  (let ((end-marker (copy-marker end t))
        (rx (howm-todo--marker-rx)))
    (save-excursion
      (goto-char beg)
      (while (< (point) (marker-position end-marker))
        (beginning-of-line)
        (when (looking-at rx)
          (replace-match "\\1"))
        (forward-line 1))
      (set-marker end-marker nil))))

;;;###autoload
(defun howm-todo-prioritize-region (beg end)
  "Add `TODO [XY]' prefixes to each non-empty line between BEG and END.
Blank lines start a new priority group.  The first group is
labeled A, the second B, and so on.  Inside each group Y starts
at 1 and increments by 1 for every non-empty line.  Any pre-existing
`TODO [XY]' markers in the region are stripped first, making the
command idempotent and safe to repeat."
  (interactive "r")
  (let ((end-marker (copy-marker end t)))
    (howm-todo-strip-region beg end-marker)
    (save-excursion
      (save-restriction
        (narrow-to-region beg (marker-position end-marker))
        (goto-char (point-min))
        (let ((group-index 0)
              (item-index 0)
              (in-group nil))
          (while (not (eobp))
            (cond
             ((looking-at "^[ \t]*$")
              (when in-group
                (setq group-index (1+ group-index))
                (setq item-index 0)
                (setq in-group nil)))
             (t
              (setq item-index (1+ item-index))
              (setq in-group t)
              (let* ((letter (char-to-string (+ ?A group-index)))
                     (marker (format "%s [%s%d] "
                                     howm-todo-keyword
                                     letter
                                     item-index)))
                (beginning-of-line)
                (skip-chars-forward " \t")
                (insert marker))))
            (forward-line 1))))
      (set-marker end-marker nil))))

;;; Sorting

(defun howm-todo--line-priority ()
  "Return cons (LETTER . NUMBER) for the current line, or nil.
LETTER is a single-character string and NUMBER is an integer.
Returns nil when the line has no TODO [XY] marker."
  (save-excursion
    (beginning-of-line)
    (when (looking-at (concat "[ \t]*"
                              (regexp-quote howm-todo-keyword)
                              "[ \t]+"
                              (howm-todo--priority-rx)))
      (cons (match-string-no-properties 1)
            (string-to-number (match-string-no-properties 2))))))

(defun howm-todo--priority-less-p (a b)
  "Return non-nil when priority cons A sorts before B."
  (cond
   ((string< (car a) (car b)) t)
   ((string= (car a) (car b)) (< (cdr a) (cdr b)))
   (t nil)))

;;;###autoload
(defun howm-todo-sort-region (beg end)
  "Sort lines between BEG and END by `TODO [XY]' priority.
Lines without a marker sort to the end and keep their original
relative order."
  (interactive "r")
  (save-excursion
    (save-restriction
      (narrow-to-region beg end)
      (goto-char (point-min))
      (let ((records nil)
            (line-num 0))
        (while (not (eobp))
          (let* ((bol (line-beginning-position))
                 (eol (line-end-position))
                 (text (buffer-substring-no-properties bol eol))
                 (prio (howm-todo--line-priority)))
            (push (list prio line-num text) records)
            (setq line-num (1+ line-num))
            (forward-line 1)))
        (setq records (nreverse records))
        (setq records
              (sort records
                    (lambda (x y)
                      (let ((pa (nth 0 x)) (pb (nth 0 y)))
                        (cond
                         ((and pa pb) (howm-todo--priority-less-p pa pb))
                         (pa t)
                         (pb nil)
                         (t (< (nth 1 x) (nth 1 y))))))))
        (delete-region (point-min) (point-max))
        (let ((first t))
          (dolist (r records)
            (unless first (insert "\n"))
            (insert (nth 2 r))
            (setq first nil)))))))

;;; SQLite project lookup

(defun howm-todo--sqlite-builtin-rows (sql)
  "Run SQL through the built-in sqlite library.
Return a list of rows, each row a list of strings."
  (let ((db (sqlite-open howm-todo-db-path)))
    (unwind-protect
        (mapcar
         (lambda (row)
           (mapcar (lambda (v) (if v (format "%s" v) "")) row))
         (sqlite-select db sql))
      (sqlite-close db))))

(defun howm-todo--sqlite-shell-rows (sql)
  "Run SQL through the sqlite3 shell.
Return a list of rows, each row a list of strings."
  (with-temp-buffer
    (let ((status (call-process "sqlite3" nil t nil
                                "-readonly"
                                "-noheader"
                                "-list"
                                "-separator" "\x1f"
                                (expand-file-name howm-todo-db-path)
                                sql)))
      (unless (eq status 0)
        (user-error "sqlite3 query failed (status %s) for %s"
                    status howm-todo-db-path)))
    (mapcar (lambda (line) (split-string line "\x1f"))
            (split-string (string-trim (buffer-string)) "\n" t))))

(defun howm-todo--sqlite-rows (sql)
  "Run SQL against `howm-todo-db-path' and return rows as lists of strings."
  (unless (file-readable-p howm-todo-db-path)
    (user-error "SQLite database not readable: %s" howm-todo-db-path))
  (cond
   ((and (fboundp 'sqlite-available-p)
         (sqlite-available-p)
         (fboundp 'sqlite-open))
    (howm-todo--sqlite-builtin-rows sql))
   ((executable-find "sqlite3")
    (howm-todo--sqlite-shell-rows sql))
   (t (user-error
       "No SQLite backend available; install sqlite3 or use Emacs with sqlite support"))))

(defun howm-todo--safe-identifier (name)
  "Return NAME stripped of any character that is unsafe in a SQL identifier."
  (replace-regexp-in-string "[^A-Za-z0-9_]" "" name))

(defun howm-todo--detect-table ()
  "Return the name of a table in the database that has the project column."
  (let* ((tables (mapcar #'car
                         (howm-todo--sqlite-rows
                          "SELECT name FROM sqlite_master WHERE type='table';")))
         (col howm-todo-db-column)
         (match (cl-find-if
                 (lambda (tbl)
                   (let* ((safe (howm-todo--safe-identifier tbl))
                          (rows (howm-todo--sqlite-rows
                                 (format "PRAGMA table_info(\"%s\");" safe))))
                     (cl-some (lambda (r) (string= (nth 1 r) col)) rows)))
                 tables)))
    (or match
        (user-error
         "No table in %s has a column named %s"
         howm-todo-db-path howm-todo-db-column))))

(defun howm-todo--project-names ()
  "Return a sorted, de-duplicated list of project names from the database."
  (let* ((table (or howm-todo-db-table (howm-todo--detect-table)))
         (safe-table (howm-todo--safe-identifier table))
         (safe-col (howm-todo--safe-identifier howm-todo-db-column))
         (sql (format
               (concat "SELECT DISTINCT \"%s\" FROM \"%s\" "
                       "WHERE \"%s\" IS NOT NULL AND \"%s\" <> '' "
                       "ORDER BY \"%s\";")
               safe-col safe-table safe-col safe-col safe-col)))
    (mapcar #'car (howm-todo--sqlite-rows sql))))

(defun howm-todo--read-project ()
  "Read a project name with `completing-read'."
  (let ((names (howm-todo--project-names)))
    (unless names
      (user-error "No projects found in %s" howm-todo-db-path))
    (completing-read "Project: " names nil t)))

;;; Tagging

(defun howm-todo--sanitize-tag (name)
  "Sanitize NAME so it can be used inside an Org tag."
  (replace-regexp-in-string "[^A-Za-z0-9_@%]" "_" name))

(defun howm-todo--project-to-tag (project)
  "Convert PROJECT into a safe Org tag.
When `howm-todo-tag-use-basename' is non-nil, only the file-name
portion of PROJECT is used."
  (let ((raw (if howm-todo-tag-use-basename
                 (file-name-nondirectory (directory-file-name project))
               project)))
    (howm-todo--sanitize-tag raw)))

(defun howm-todo--line-has-marker-p ()
  "Return non-nil when the current line has a TODO [XY] marker."
  (save-excursion
    (beginning-of-line)
    (looking-at (concat "[ \t]*"
                        (regexp-quote howm-todo-keyword)
                        "[ \t]+"
                        (howm-todo--priority-rx)))))

(defconst howm-todo--existing-tags-rx
  "\\([ \t]+\\)\\(:\\(?:[A-Za-z0-9_@%]+:\\)+\\)\\'"
  "Regex matching a trailing Org-style tag block at the end of a string.
Group 1 captures the separator whitespace.  Group 2 captures the
entire `:tag1:tag2:' block including the surrounding colons.")

(defun howm-todo--append-tag-to-line (line tag)
  "Return LINE with TAG appended as an Org-style tag.
If LINE already ends with one or more `:foo:bar:' tags, TAG is
inserted into that block.  If TAG is already present in the block
the line is returned unchanged."
  (let* ((trimmed (string-trim-right line)))
    (if (string-match howm-todo--existing-tags-rx trimmed)
        (let* ((prefix (substring trimmed 0 (match-beginning 1)))
               (sep (match-string 1 trimmed))
               (tags (match-string 2 trimmed)))
          (if (string-match-p
               (concat ":" (regexp-quote tag) ":") tags)
              trimmed
            ;; tags looks like ":a:b:" so chop the final colon, append the
            ;; new tag and its trailing colon.
            (concat prefix sep (substring tags 0 -1) ":" tag ":")))
      (concat trimmed " :" tag ":"))))

;;;###autoload
(defun howm-todo-add-project-tag ()
  "Append `:project:' to the end of the current TODO line.
The project name is read from the SQLite database referenced by
`howm-todo-db-path' using `completing-read'.  When the line
already ends with one or more Org tags, the new tag is merged
into that trailing block instead of starting a new one."
  (interactive)
  (unless (howm-todo--line-has-marker-p)
    (user-error "Current line has no TODO [XY] marker"))
  (let* ((project (howm-todo--read-project))
         (tag (and project
                   (not (string-empty-p project))
                   (howm-todo--project-to-tag project))))
    (when (and tag (not (string-empty-p tag)))
      (let* ((bol (line-beginning-position))
             (eol (line-end-position))
             (line (buffer-substring-no-properties bol eol))
             (new-line (howm-todo--append-tag-to-line line tag)))
        (unless (string= line new-line)
          (delete-region bol eol)
          (insert new-line))))))

;;;###autoload
(defun howm-todo-tag-region (beg end)
  "Walk BEG..END and prompt for a project tag once per TODO line."
  (interactive "r")
  (let ((end-marker (copy-marker end t)))
    (save-excursion
      (goto-char beg)
      (while (< (point) (marker-position end-marker))
        (when (howm-todo--line-has-marker-p)
          (howm-todo-add-project-tag))
        (forward-line 1)))
    (set-marker end-marker nil)))

(provide 'howm-todo)
;;; howm-todo.el ends here
