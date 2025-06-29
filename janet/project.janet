(declare-project
  :name "recall"
  :description "a spaced repetition command line tool"
  :dependencies [
    {:url "https://github.com/ianthehenry/cmd.git"
     :tag "v1.1.0"}
    "https://github.com/janet-lang/sqlite3.git"
  ])

(declare-executable
  :name "recall"
  :entry "main.janet")
