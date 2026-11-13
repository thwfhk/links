(lang dune 2.7)
;; dune language version (NOTE this comment applies to the above line; it is intentionally placed here!)
(using menhir 2.0)                 ;; enable use of menhir
(name links)                       ;; package name
(implicit_transitive_deps false)   ;; hides transitive dependencies in libraries/executables/tests
(generate_opam_files true)         ;; generate .opam package files using the descriptions defined in this file


;;
;; Project metainformation
;;

(source
 (github links-lang/links))
(homepage
  https://links-lang.org)
(authors
  "The Links Team <links-dev@inf.ed.ac.uk>")
(maintainers
  "Daniel Hillerström <daniel.hillerstrom@ed.ac.uk>")
(license
  GPL-3.0-only)
(documentation
  "https://links-lang.org/quick-help.html")

;;
;; The Links Programmming System
;;

(package
 (name links)
 (synopsis "The SmallLinks Programming Language")
 (description "SmallLinks is a native interpreter for a subset of Links.")
 (depends (ocaml (>= 5.3.0))
           ppx_deriving
           linenoise
           ANSITerminal
          (lwt (>= 5.0.0))
           safepass
          (menhir (>= 20210419))
          (calendar (>= 2.0.4)))
 (tags
  ("effect handlers" "effect typing" "extensible data types")))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/dune-files.html#dune-project

