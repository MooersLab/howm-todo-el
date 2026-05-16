# howm-todo

![Version](https://img.shields.io/static/v1?label=howm-todo-el&message=0.1.0&color=brightcolor)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Emacs](https://img.shields.io/badge/Emacs-27.1%2B-purple.svg)](https://www.gnu.org/software/emacs/)
[![Made with Org](https://img.shields.io/badge/Made_with-Emacs_Lisp-7F5AB6.svg)](https://www.gnu.org/software/emacs/manual/html_node/elisp/index.html)
[![howm](https://img.shields.io/badge/howm-1.4.x-green.svg)](https://kaorahi.github.io/howm/)

Cross-compatible TODO prioritization for [Howm](https://kaorahi.github.io/howm/) and Org-mode.

`howm-todo` lets you mark, sort, and tag TODO items with a priority cookie that both Org-mode and Howm recognize. The cookie has the form `TODO [XY]`, where `X` is an uppercase letter for the priority group and `Y` is a non-negative integer for the rank inside the group. A smaller `Y` means higher priority, so `[A1]` outranks `[A2]` which outranks `[A44]` which outranks `[B1]`.

The package also reads project names from a SQLite database you maintain for time tracking and appends them to the line as an Org-style `:project:` tag.

## Features

- Add `TODO [XY]` markers across a manually ordered region. Blank lines separate priority groups, so the first contiguous block of lines is labeled `A1`, `A2`, `A3`, the second block becomes `B1`, `B2`, and so on.
- Strip every `TODO [XY]` marker from a region so the items can be re-prioritized the next day.
- Sort a region by `[XY]` priority. Lines without a marker sink to the bottom and keep their relative order. The sort is stable among equal cookies and numerically aware, so `C2` precedes `C10` precedes `C100`.
- Prompt for a project name from a SQLite database and append it as an Org-style `:tag:` to the current line. When the line already ends with a tag block such as `:home:`, the new tag merges in as `:home:project:` rather than starting a second block.

## Requirements

- Emacs 27.1 or newer.
- One of:
  - Emacs compiled with the built-in `sqlite` library (Emacs 29 and newer with `--with-sqlite3`), or
  - The `sqlite3` command-line shell on `PATH`.
- GNU Make and `makeinfo` (from the `texinfo` package) to build documentation and install via the Makefile.

## Installation

### Manual install with the Makefile

```sh
git clone https://github.com/MooersLab/howm-todo-el
cd howm-todo-el
make compile
make info
sudo make install
```

The default install paths are:

- Elisp: `/usr/local/share/emacs/site-lisp/howm-todo-el`
- Info: `/usr/local/share/info`

Override `PREFIX`, `ELISPDIR`, or `INFODIR` to install elsewhere. For a per-user install:

```sh
make install PREFIX=$HOME/.local
```

After install, add the install directory to `load-path` and require the package:

```elisp
(add-to-list 'load-path "/usr/local/share/emacs/site-lisp/howm-todo-el")
(require 'howm-todo)
```

### straight.el

```elisp
(straight-use-package
 '(howm-todo :type git
             :host github
             :repo "MooersLab/howm-todo-el"))
```

### use-package with straight

```elisp
(use-package howm-todo
  :straight (howm-todo :type git
                       :host github
                       :repo "MooersLab/howm-todo-el")
  :commands (howm-todo-prioritize-region
             howm-todo-strip-region
             howm-todo-sort-region
             howm-todo-add-project-tag
             howm-todo-tag-region)
  :custom
  (howm-todo-db-path "~/6003TimeTracking/cb/tenKprojects.db"))
```

## Configuration

```elisp
(setq howm-todo-db-path "~/60003TimeTracking/cb/tenKprojects.db")
;; Optional: pin the table name if auto-detection picks the wrong one.
;; (setq howm-todo-db-table "projects")
;; Optional: change the project column.
;; (setq howm-todo-db-column "ProjectDirectory")
```

| Variable | Default | Purpose |
| --- | --- | --- |
| `howm-todo-db-path` | `~/60003TimeTracking/cb/tenKprojects.db` | Path to the SQLite database |
| `howm-todo-db-table` | `nil` (auto-detect) | Table holding project rows |
| `howm-todo-db-column` | `ProjectDirectory` | Column holding project names |
| `howm-todo-keyword` | `TODO` | Leading keyword on a prioritized line |
| `howm-todo-tag-use-basename` | `t` | Use the basename of the project path for the tag |

### Suggested keybindings

```elisp
(define-key global-map (kbd "C-c j p") #'howm-todo-prioritize-region)
(define-key global-map (kbd "C-c j s") #'howm-todo-strip-region)
(define-key global-map (kbd "C-c j o") #'howm-todo-sort-region)
(define-key global-map (kbd "C-c j t") #'howm-todo-add-project-tag)
(define-key global-map (kbd "C-c j T") #'howm-todo-tag-region)
```

## Usage

### Prioritize a region you have manually sorted

Type your items in declining-priority order. Use blank lines to separate priority groups. Select the region and run `M-x howm-todo-prioritize-region`.

Before:

```
finish grant draft
respond to reviewer email

water plants
unload dishwasher

read paper on DSDs
```

After:

```
TODO [A1] finish grant draft
TODO [A2] respond to reviewer email

TODO [B1] water plants
TODO [B2] unload dishwasher

TODO [C1] read paper on DSDs
```

The command is idempotent, so you can run it again without doubling the markers.

### Strip markers to re-prioritize tomorrow

Select the region and run `M-x howm-todo-strip-region`. All `TODO [XY]` cookies are removed and leading indentation is preserved.

### Sort a region by priority

Select a region of already-marked lines and run `M-x howm-todo-sort-region`. The lines re-order by `[XY]`. Unmarked lines sink to the bottom and keep their relative order.

### Add a project tag to a line

Place point on a line that already has a `TODO [XY]` marker and run `M-x howm-todo-add-project-tag`. The package reads the `ProjectDirectory` column from the SQLite database, presents the values via `completing-read`, and appends the selected project as an Org-style tag.

| Before | After (adding `garden`) |
| --- | --- |
| `TODO [A1] mow lawn` | `TODO [A1] mow lawn :garden:` |
| `TODO [A1] mow lawn :home:` | `TODO [A1] mow lawn :home:garden:` |
| `TODO [A1] mow lawn :home:outdoor:` | `TODO [A1] mow lawn :home:outdoor:garden:` |
| `TODO [A1] mow lawn :garden:` | `TODO [A1] mow lawn :garden:` (no change) |

To tag every marked line in a region, run `M-x howm-todo-tag-region`. The package prompts once per marked line and skips unmarked lines.

## SQLite database

The package expects a SQLite database with a column of project identifiers. The default schema is:

```sql
CREATE TABLE projects (
    id               INTEGER PRIMARY KEY,
    ProjectDirectory TEXT
);
```

The table name is not significant when `howm-todo-db-table` is `nil`. The package walks the schema and picks the first table whose columns include `howm-todo-db-column`. If you keep your projects in a different column, change `howm-todo-db-column`. If multiple tables contain that column, set `howm-todo-db-table` explicitly to pin detection.

Project names are de-duplicated and sorted before they are shown to `completing-read`.

## Documentation

A full Texinfo manual ships with the package. Build it with:

```sh
make info     # produces howm-todo.info
make html     # produces howm-todo.html
```

Inside Emacs the manual is reachable through `C-h i` once installed.

## Testing

The ERT suite covers prioritization, stripping, sorting, tag merging, SQLite project lookup, and marker safety. Run it with:

```sh
make test
```

The Makefile invokes Emacs in batch mode and runs `howm-todo-tests.el`. SQLite tests are skipped automatically when neither the built-in `sqlite` library nor the `sqlite3` shell is available.

## License

This package is licensed under the GNU General Public License, version 3 or later. See [LICENSE](LICENSE) for the full text.

The accompanying documentation is licensed under the GNU Free Documentation License, version 1.3 or later.

## Author

Blaine Mooers, Department of Biochemistry and Physiology, University of Oklahoma Health Campus.
Email: blaine-mooers@ou.edu

## Funding

- NIH: R01 CA242845, R01 AI088011
- NIH: P30 CA225520 (PI: R. Mannel); P30 GM145423 (PI: A. West)

