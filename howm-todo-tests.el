;;; howm-todo-tests.el --- ERT tests for howm-todo  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Blaine Mooers

;; Author: Blaine Mooers <blaine-mooers@ou.edu>
;; Keywords: tests
;; Package-Requires: ((emacs "27.1") (ert "0"))

;;; Commentary:

;; Comprehensive ERT tests for howm-todo.  Run with:
;;
;;   make test
;;
;; or directly:
;;
;;   emacs -Q --batch -L . \
;;       -l howm-todo.el -l howm-todo-tests.el \
;;       -f ert-run-tests-batch-and-exit
;;
;; The SQLite tests are skipped automatically when neither the
;; built-in sqlite library nor the sqlite3 command-line shell is
;; available on the host.

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "." dir)))

(require 'howm-todo)

;;; Helpers

(defmacro howm-todo-tests--with-buffer (input &rest body)
  "Insert INPUT into a temp buffer, run BODY, return the buffer string."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (insert ,input)
     (goto-char (point-min))
     ,@body
     (buffer-substring-no-properties (point-min) (point-max))))

(defun howm-todo-tests--full-region (fn)
  "Return a function that applies FN to the whole buffer region."
  (lambda () (funcall fn (point-min) (point-max))))

(defun howm-todo-tests--sqlite-available-p ()
  "Return non-nil when any SQLite backend can be used."
  (or (and (fboundp 'sqlite-available-p)
           (sqlite-available-p)
           (fboundp 'sqlite-open))
      (executable-find "sqlite3")))

;;; ---------------------------------------------------------------------------
;;; howm-todo-prioritize-region
;;; ---------------------------------------------------------------------------

(ert-deftest howm-todo-test-prioritize-single-group ()
  "Single contiguous block gets letter A and incrementing Y."
  (should
   (equal
    (howm-todo-tests--with-buffer
        "first item\nsecond item\nthird item"
      (howm-todo-prioritize-region (point-min) (point-max)))
    (concat "TODO [A1] first item\n"
            "TODO [A2] second item\n"
            "TODO [A3] third item"))))

(ert-deftest howm-todo-test-prioritize-multiple-groups ()
  "Blank lines start a new priority group."
  (should
   (equal
    (howm-todo-tests--with-buffer
        (concat "alpha one\nalpha two\n\n"
                "beta one\n\n"
                "gamma one\ngamma two\ngamma three")
      (howm-todo-prioritize-region (point-min) (point-max)))
    (concat "TODO [A1] alpha one\n"
            "TODO [A2] alpha two\n"
            "\n"
            "TODO [B1] beta one\n"
            "\n"
            "TODO [C1] gamma one\n"
            "TODO [C2] gamma two\n"
            "TODO [C3] gamma three"))))

(ert-deftest howm-todo-test-prioritize-is-idempotent ()
  "Running prioritize twice yields the same result as once."
  (let* ((input "first\nsecond\n\nthird")
         (once (howm-todo-tests--with-buffer input
                 (howm-todo-prioritize-region (point-min) (point-max))))
         (twice (howm-todo-tests--with-buffer once
                  (howm-todo-prioritize-region (point-min) (point-max)))))
    (should (equal once twice))))

(ert-deftest howm-todo-test-prioritize-preserves-indent ()
  "Leading indentation is preserved when the marker is inserted."
  (should
   (equal
    (howm-todo-tests--with-buffer
        "  indented item\n  another\n    deeper"
      (howm-todo-prioritize-region (point-min) (point-max)))
    (concat "  TODO [A1] indented item\n"
            "  TODO [A2] another\n"
            "    TODO [A3] deeper"))))

(ert-deftest howm-todo-test-prioritize-leading-blanks-do-not-consume-groups ()
  "Leading blank lines do not advance the group counter."
  (should
   (equal
    (howm-todo-tests--with-buffer
        "\n\nfirst\nsecond"
      (howm-todo-prioritize-region (point-min) (point-max)))
    (concat "\n"
            "\n"
            "TODO [A1] first\n"
            "TODO [A2] second"))))

(ert-deftest howm-todo-test-prioritize-only-blanks ()
  "A region of only blank lines is left untouched."
  (should
   (equal
    (howm-todo-tests--with-buffer
        "\n\n\n"
      (howm-todo-prioritize-region (point-min) (point-max)))
    "\n\n\n")))

(ert-deftest howm-todo-test-prioritize-empty-buffer ()
  "An empty region is a no-op."
  (should
   (equal
    (howm-todo-tests--with-buffer ""
      (howm-todo-prioritize-region (point-min) (point-max)))
    "")))

(ert-deftest howm-todo-test-prioritize-strips-old-markers-first ()
  "Existing markers are removed before fresh ones are added."
  (should
   (equal
    (howm-todo-tests--with-buffer
        (concat "TODO [B7] stale one\n"
                "TODO [B8] stale two\n"
                "\n"
                "TODO [Z99] stale three")
      (howm-todo-prioritize-region (point-min) (point-max)))
    (concat "TODO [A1] stale one\n"
            "TODO [A2] stale two\n"
            "\n"
            "TODO [B1] stale three"))))

;;; ---------------------------------------------------------------------------
;;; howm-todo-strip-region
;;; ---------------------------------------------------------------------------

(ert-deftest howm-todo-test-strip-basic ()
  (should
   (equal
    (howm-todo-tests--with-buffer
        (concat "TODO [A1] first\n"
                "TODO [A2] second\n"
                "\n"
                "TODO [B1] third")
      (howm-todo-strip-region (point-min) (point-max)))
    "first\nsecond\n\nthird")))

(ert-deftest howm-todo-test-strip-handles-multi-digit-y ()
  (should
   (equal
    (howm-todo-tests--with-buffer
        "TODO [C44] something\nTODO [C100] another\nTODO [Z9999] huge"
      (howm-todo-strip-region (point-min) (point-max)))
    "something\nanother\nhuge")))

(ert-deftest howm-todo-test-strip-preserves-indent ()
  (should
   (equal
    (howm-todo-tests--with-buffer
        "  TODO [A1] indented\n    TODO [A2] deeper"
      (howm-todo-strip-region (point-min) (point-max)))
    "  indented\n    deeper")))

(ert-deftest howm-todo-test-strip-on-already-stripped ()
  "Strip is a no-op on lines that have no marker."
  (let ((input "plain line one\nplain line two"))
    (should
     (equal
      (howm-todo-tests--with-buffer input
        (howm-todo-strip-region (point-min) (point-max)))
      input))))

(ert-deftest howm-todo-test-strip-empty-region ()
  (should
   (equal
    (howm-todo-tests--with-buffer ""
      (howm-todo-strip-region (point-min) (point-max)))
    "")))

(ert-deftest howm-todo-test-strip-marker-safety ()
  "An end-position marker is honored even after deletions shorten the region."
  (with-temp-buffer
    (insert "TODO [A1] one\nTODO [A2] two\nuntouched\n")
    (let ((beg (point-min))
          (end-of-second (save-excursion
                           (goto-char (point-min))
                           (forward-line 2)
                           (point))))
      (howm-todo-strip-region beg end-of-second)
      (should (equal (buffer-string)
                     "one\ntwo\nuntouched\n")))))

;;; ---------------------------------------------------------------------------
;;; howm-todo-sort-region
;;; ---------------------------------------------------------------------------

(ert-deftest howm-todo-test-sort-orders-by-priority ()
  (should
   (equal
    (howm-todo-tests--with-buffer
        (concat "TODO [B1] beta one\n"
                "TODO [A2] alpha two\n"
                "TODO [A1] alpha one\n"
                "TODO [C10] gamma ten\n"
                "TODO [C2] gamma two")
      (howm-todo-sort-region (point-min) (point-max)))
    (concat "TODO [A1] alpha one\n"
            "TODO [A2] alpha two\n"
            "TODO [B1] beta one\n"
            "TODO [C2] gamma two\n"
            "TODO [C10] gamma ten"))))

(ert-deftest howm-todo-test-sort-unmarked-go-last ()
  (should
   (equal
    (howm-todo-tests--with-buffer
        (concat "no marker line\n"
                "TODO [A2] second\n"
                "TODO [A1] first\n"
                "another bare line")
      (howm-todo-sort-region (point-min) (point-max)))
    (concat "TODO [A1] first\n"
            "TODO [A2] second\n"
            "no marker line\n"
            "another bare line"))))

(ert-deftest howm-todo-test-sort-stable-among-equal ()
  "Equal-priority lines keep their original relative order."
  (should
   (equal
    (howm-todo-tests--with-buffer
        (concat "TODO [A1] first inserted A1\n"
                "TODO [A1] second inserted A1\n"
                "TODO [A1] third inserted A1")
      (howm-todo-sort-region (point-min) (point-max)))
    (concat "TODO [A1] first inserted A1\n"
            "TODO [A1] second inserted A1\n"
            "TODO [A1] third inserted A1"))))

(ert-deftest howm-todo-test-sort-handles-multi-digit-y ()
  "C2 sorts before C10 numerically, not alphabetically."
  (should
   (equal
    (howm-todo-tests--with-buffer
        "TODO [C10] ten\nTODO [C2] two\nTODO [C100] hundred"
      (howm-todo-sort-region (point-min) (point-max)))
    "TODO [C2] two\nTODO [C10] ten\nTODO [C100] hundred")))

(ert-deftest howm-todo-test-sort-single-line ()
  (let ((input "TODO [A1] only"))
    (should
     (equal
      (howm-todo-tests--with-buffer input
        (howm-todo-sort-region (point-min) (point-max)))
      input))))

;;; ---------------------------------------------------------------------------
;;; Line priority parsing
;;; ---------------------------------------------------------------------------

(ert-deftest howm-todo-test-line-priority-parses ()
  (with-temp-buffer
    (insert "TODO [C44] hello world")
    (goto-char (point-min))
    (let ((p (howm-todo--line-priority)))
      (should (equal (car p) "C"))
      (should (= (cdr p) 44)))))

(ert-deftest howm-todo-test-line-priority-no-marker ()
  (with-temp-buffer
    (insert "just a line")
    (goto-char (point-min))
    (should (null (howm-todo--line-priority)))))

(ert-deftest howm-todo-test-line-priority-indented ()
  "Leading whitespace does not prevent recognition."
  (with-temp-buffer
    (insert "    TODO [B7] indented item")
    (goto-char (point-min))
    (let ((p (howm-todo--line-priority)))
      (should (equal (car p) "B"))
      (should (= (cdr p) 7)))))

(ert-deftest howm-todo-test-priority-less-p ()
  (should (howm-todo--priority-less-p '("A" . 1) '("A" . 2)))
  (should (howm-todo--priority-less-p '("A" . 1) '("B" . 1)))
  (should (howm-todo--priority-less-p '("A" . 99) '("B" . 1)))
  (should-not (howm-todo--priority-less-p '("A" . 2) '("A" . 1)))
  (should-not (howm-todo--priority-less-p '("B" . 1) '("A" . 99))))

;;; ---------------------------------------------------------------------------
;;; Tag sanitization and project-to-tag
;;; ---------------------------------------------------------------------------

(ert-deftest howm-todo-test-sanitize-tag ()
  (should (equal (howm-todo--sanitize-tag "my-project") "my_project"))
  (should (equal (howm-todo--sanitize-tag "fine_tag_42") "fine_tag_42"))
  (should (equal (howm-todo--sanitize-tag "spaces and / slashes")
                 "spaces_and___slashes"))
  (should (equal (howm-todo--sanitize-tag "ümläut") "_ml_ut"))
  (should (equal (howm-todo--sanitize-tag "ok@user%name") "ok@user%name")))

(ert-deftest howm-todo-test-project-to-tag-basename ()
  (let ((howm-todo-tag-use-basename t))
    (should (equal (howm-todo--project-to-tag "/home/blaine/4581autoslipHowm")
                   "4581autoslipHowm"))
    (should (equal (howm-todo--project-to-tag "/home/blaine/4581autoslipHowm/")
                   "4581autoslipHowm"))
    (should (equal (howm-todo--project-to-tag "/path/with spaces/proj")
                   "proj"))))

(ert-deftest howm-todo-test-project-to-tag-full-path ()
  (let ((howm-todo-tag-use-basename nil))
    (should (equal (howm-todo--project-to-tag "/home/blaine/projA")
                   "_home_blaine_projA"))))

;;; ---------------------------------------------------------------------------
;;; Tag merging helper
;;; ---------------------------------------------------------------------------

(ert-deftest howm-todo-test-append-tag-bare-line ()
  (should
   (equal (howm-todo--append-tag-to-line "TODO [A1] water plants" "garden")
          "TODO [A1] water plants :garden:")))

(ert-deftest howm-todo-test-append-tag-merge-block ()
  (should
   (equal (howm-todo--append-tag-to-line
           "TODO [A1] water plants :home:" "garden")
          "TODO [A1] water plants :home:garden:")))

(ert-deftest howm-todo-test-append-tag-multi-tag-merge ()
  (should
   (equal (howm-todo--append-tag-to-line
           "TODO [A1] water plants :home:outdoor:" "garden")
          "TODO [A1] water plants :home:outdoor:garden:")))

(ert-deftest howm-todo-test-append-tag-duplicate-noop ()
  (should
   (equal (howm-todo--append-tag-to-line
           "TODO [A1] water plants :garden:" "garden")
          "TODO [A1] water plants :garden:")))

(ert-deftest howm-todo-test-append-tag-duplicate-in-block ()
  (should
   (equal (howm-todo--append-tag-to-line
           "TODO [A1] water plants :home:garden:" "garden")
          "TODO [A1] water plants :home:garden:")))

(ert-deftest howm-todo-test-append-tag-trims-trailing-whitespace ()
  (should
   (equal (howm-todo--append-tag-to-line
           "TODO [A1] water plants   " "garden")
          "TODO [A1] water plants :garden:")))

;;; ---------------------------------------------------------------------------
;;; howm-todo-add-project-tag and howm-todo-tag-region
;;; ---------------------------------------------------------------------------

(ert-deftest howm-todo-test-add-project-tag-without-marker ()
  "Calling the tag command on a line without TODO [XY] signals an error."
  (with-temp-buffer
    (insert "no marker here")
    (goto-char (point-min))
    (cl-letf (((symbol-function 'howm-todo--read-project)
               (lambda () "/tmp/proj")))
      (should-error (howm-todo-add-project-tag) :type 'user-error))))

(ert-deftest howm-todo-test-add-project-tag-appends ()
  "On a marked line, the chosen tag is appended."
  (with-temp-buffer
    (insert "TODO [A1] do the dishes")
    (goto-char (point-min))
    (cl-letf (((symbol-function 'howm-todo--read-project)
               (lambda () "/home/blaine/kitchen")))
      (howm-todo-add-project-tag))
    (should (equal (buffer-string)
                   "TODO [A1] do the dishes :kitchen:"))))

(ert-deftest howm-todo-test-add-project-tag-merges ()
  "On a marked line that already has tags, the new tag merges in."
  (with-temp-buffer
    (insert "TODO [A1] mow lawn :home:")
    (goto-char (point-min))
    (cl-letf (((symbol-function 'howm-todo--read-project)
               (lambda () "/home/blaine/garden")))
      (howm-todo-add-project-tag))
    (should (equal (buffer-string)
                   "TODO [A1] mow lawn :home:garden:"))))

(ert-deftest howm-todo-test-tag-region-prompts-per-line ()
  "Tag region prompts once per TODO line, skipping unmarked lines."
  (with-temp-buffer
    (insert (concat "TODO [A1] one\n"
                    "no marker line\n"
                    "TODO [A2] two\n"))
    (let ((calls 0)
          (projects '("/p/alpha" "/p/beta")))
      (cl-letf (((symbol-function 'howm-todo--read-project)
                 (lambda ()
                   (let ((p (nth calls projects)))
                     (setq calls (1+ calls))
                     p))))
        (howm-todo-tag-region (point-min) (point-max)))
      (should (= calls 2))
      (should (equal (buffer-string)
                     (concat "TODO [A1] one :alpha:\n"
                             "no marker line\n"
                             "TODO [A2] two :beta:\n"))))))

;;; ---------------------------------------------------------------------------
;;; SQLite project lookup
;;; ---------------------------------------------------------------------------

(defun howm-todo-tests--make-project-db (path)
  "Create a tiny projects database at PATH."
  (when (file-exists-p path) (delete-file path))
  (cond
   ((and (fboundp 'sqlite-available-p)
         (sqlite-available-p)
         (fboundp 'sqlite-open))
    (let ((db (sqlite-open path)))
      (unwind-protect
          (progn
            (sqlite-execute
             db
             (concat "CREATE TABLE projects ("
                     "id INTEGER PRIMARY KEY, "
                     "ProjectDirectory TEXT);"))
            (dolist (val '("/p/zeta" "/p/alpha" "/p/beta" "/p/alpha"))
              (sqlite-execute
               db
               "INSERT INTO projects(ProjectDirectory) VALUES (?);"
               (list val))))
        (sqlite-close db))))
   ((executable-find "sqlite3")
    (call-process
     "sqlite3" nil nil nil path
     (concat "CREATE TABLE projects ("
             "id INTEGER PRIMARY KEY, "
             "ProjectDirectory TEXT);"
             "INSERT INTO projects(ProjectDirectory) VALUES "
             "('/p/zeta'),"
             "('/p/alpha'),"
             "('/p/beta'),"
             "('/p/alpha');")))
   (t (error "No SQLite backend"))))

(ert-deftest howm-todo-test-sqlite-project-names-sorted-and-deduped ()
  (skip-unless (howm-todo-tests--sqlite-available-p))
  (let ((db (make-temp-file "howm-todo-test-" nil ".db")))
    (unwind-protect
        (progn
          (howm-todo-tests--make-project-db db)
          (let ((howm-todo-db-path db)
                (howm-todo-db-table nil)
                (howm-todo-db-column "ProjectDirectory"))
            (should (equal (howm-todo--project-names)
                           '("/p/alpha" "/p/beta" "/p/zeta")))))
      (when (file-exists-p db) (delete-file db)))))

(ert-deftest howm-todo-test-sqlite-detect-table ()
  (skip-unless (howm-todo-tests--sqlite-available-p))
  (let ((db (make-temp-file "howm-todo-test-" nil ".db")))
    (unwind-protect
        (progn
          (howm-todo-tests--make-project-db db)
          (let ((howm-todo-db-path db)
                (howm-todo-db-table nil)
                (howm-todo-db-column "ProjectDirectory"))
            (should (equal (howm-todo--detect-table) "projects"))))
      (when (file-exists-p db) (delete-file db)))))

(ert-deftest howm-todo-test-sqlite-explicit-table-overrides-detection ()
  (skip-unless (howm-todo-tests--sqlite-available-p))
  (let ((db (make-temp-file "howm-todo-test-" nil ".db")))
    (unwind-protect
        (progn
          (howm-todo-tests--make-project-db db)
          (let ((howm-todo-db-path db)
                (howm-todo-db-table "projects")
                (howm-todo-db-column "ProjectDirectory"))
            (should (equal (howm-todo--project-names)
                           '("/p/alpha" "/p/beta" "/p/zeta")))))
      (when (file-exists-p db) (delete-file db)))))

(ert-deftest howm-todo-test-sqlite-missing-database-signals ()
  (let ((howm-todo-db-path "/nonexistent/path/howm-todo-missing.db"))
    (should-error (howm-todo--project-names) :type 'user-error)))

(provide 'howm-todo-tests)
;;; howm-todo-tests.el ends here
