# Command line tool with 2 subcommands. For each subcommand/the command as a
# whole, we want to be able to supply the -f/--file argument, which is the path
# to the databse
#	- test (to test the cards that are due in our database)
#	  -n/--num for the maximum number of cards to test
#	  (maybe easiness cut-off for testing??)
#	- add (to add new untested cards to the database)
#	  -i/--interactive for adding cards interactively
#	- edit (to fixup info in the database manually)
#	  (this should also be possible from the testing command, to fix things
#	  when we notice them)

# TODO: parse-all instead of parse?
(import sqlite3 :as sql)
(import cmd)

(defn open-db [path]
  (def db
    (try
      (sql/open path)
      ([msg _]
        (print "Couldn't open database at " path ": " msg)
	(os/exit 1))))
  (try
   (sql/eval db
     "CREATE TABLE IF NOT EXISTS cards (
       id INTEGER PRIMARY KEY,
       front TEXT UNIQUE,
       back TEXT,
       tested INTEGER,
       i INTEGE,
       n INTEGER,
       ef REAL)")
   ([msg _]
     (print "Couldn't create cards table: " msg)
     (os/exit 1)))
  db)

(def- test-spec
  (cmd/spec [--file -f] (optional :file)
            [--num -n] (optional :int+ 15)))
(def- test-doc "test cards that are ready for recall")
(def- add-spec
  (cmd/spec [--file -f] (optional :file)
            [--interactive -i] (flag)
            [--front] (tuple :string)
            [--back] (tuple :string)))
(def- adddoc "add new untested cards to the databse")
(def- edit-spec
  (cmd/spec [--file -f] (optional :file)
            [--id -i] (optional :int+)))
(def- edit-doc "manually edit cards in the database")
# TODO: default help here doesn't display subcommands
(def- toplevel-spec
  (cmd/spec [--file -f] (optional :file) rest (escape :string)))
(def- toplevel-doc "A simple spaced-repetition command line tool")

(defmacro subcmds [rest & cmds]
  (defn gen-branch [label]
    ~(,(string label)
      (do (setdyn *args*
            (tuple/join
              # TODO: figure out if this should be a keyword, e.g., :add
              (tuple (string (get (dyn *args*) 0) " " ,(string label)))
              (tuple/slice ,rest 1)))
          (try (put (cmd/parse ,(symbol label "-spec") (cmd/args)) :cmd ',label)
               ([failures _]
                (loop [[arg msg] :pairs failures]
                  (if (> (length arg) 0)
                    (prin "error parsing `" arg "`")
                    (prin "error when parsing arguments"))
                  (print ": " (string/join msg ", ")))
                (cmd/print-help ,(symbol label "-spec"))
                (os/exit 1))))))
  ~(case (get ,rest 0)
     ,;(mapcat gen-branch cmds)
     (do
       (print "uknown subcommand `" (get ,rest 0) "`")
       (os/exit 1))))

(defn- add-card [front back]
  (try
    (sql/eval (dyn 'db)
     "INSERT INTO cards
      VALUES (NULL, ?, ?, 0, 0, 0, 2.5)"
     (tuple front back))
    ([msg _]
     (print "failed to insert card:" msg "\nFront\n" front "\nBack\n" back)
     (os/exit 1))))

(defn- add
  [&keys {:interactive i-flag :front fronts :back backs}]
  (if (not (= (length fronts) (length backs)))
    (do
      (prin "each --front must be matched with a --back: ")
      (print (length fronts) " `--front`s but " (length backs) " `--back`s")
      (os/exit 1)))
  # TODO: Implement a "ask if it's okay" of some kind?
  (loop [i :in (reverse (range (length fronts)))]
    (add-card (get fronts i) (get backs i))
    (add-card (get backs i) (get fronts i)))

  (while i-flag
    # TODO: format for multi-line cards
    (print "Front?")
    (def front (file/read stdin :line))
    (if (nil? front) (break))
    (print "Back?")
    (def back (file/read stdin :line))
    (if (nil? back) (break))
    (def front (string/trimr front "\n"))
    (def back (string/trimr back "\n"))
    (add-card front back)
    (add-card back front)))

(defn- read-score []
  (forever
    (print "How did you do?\n"
      "0: Complete failure to recall the information\n"
      "1: Incorrect, but upon seeing the answer, it seemed familiar\n"
      "2: Incorrect, but upon seeing the answer, it seemed easy\n"
      "3: Correct, but after significant effort\n"
      "4: Correct, after some hesitation\n"
      "5: Correct with perfect recall")
    (def score (file/read stdin :line))
    (if (nil? score)
      (do (yield :empty) (break)))
    (def score (string/trimr score "\n"))
    (if (= "e" score)
      (yield :edit)
      (let [score (try (parse score) ([_ _]))]
        (if (and (number? score) (>= score 0) (<= score 5))
          (do (yield score) (break)))))))

(defn- edit-card [card]
  (forever
    (print "")
    (print "Card " (card :id))
    (print "  - front: " (card :front))
    (print "  - back: " (card :back))
    (print "  - tested: " (card :tested))
    (print "  - [i: " (card :i) " | n: " (card :n) " | ef: " (card :ef) "]")
    (print "")
    (print "[q:quit, f/b/t/i/n/e: edit card attr]")

    (def line (file/read stdin :line))
    (if (nil? line) (break))
    (def line (string/trimr line "\n"))
    (defn parse-line []
      (as?-> (getline) l (string/trim l "\n") (try (parse l) ([_ _] nil))))
    (defn parse-u64 []
      (as?-> (getline) l
        (string/trim l "\n")
        (try (int/to-number (int/u64 l))
             ([msg _] (print msg)))))
    (defn edit-line [line]
      (let [l (string/trimr (getline) "\n")] (if (empty? l) nil l)))
    (case line
      "q" (break)
      "f" (do (prin "new front-matter: ")
            (-?>> (edit-line (card :front)) (put card :front)))
      "b" (do (prin "new back-matter: ")
            (-?>> (edit-line (card :back)) (put card :back)))
      "t" (do (prin "new last tested time: ")
            (->> (parse-u64) (put card :tested)))
      "n" (do (prin "new number of times correct: ")
            (->> (parse-u64) (put card :n)))
      "i" (do (prin "new inter-repition interval:  ")
            (->> (parse-u64) (put card :i)))
      "e" (do (prin "new easiness factor: ")
            (as?-> (parse-line) e
              (if (and (number? e) (<= 1.3 e))
                (put card :ef e)
                (print "expected a number >= 1.3, got " e)))))))

(defn- test
  [&keys {:num num}]
  (def db (dyn 'db))
  (def time (os/time))
  (defn days->secs (days) (* 24 60 60))
  (var cards (->>
    (try
      (sql/eval db "SELECT id, front, back, tested, i, n, ef FROM cards")
      ([msg _]
       (print "failed to get cards from db: " msg)
       (os/exit 1)))
    (filter |(< (+ (days->secs ($ :i)) ($ :tested)) time))
    (sort-by :tested)
    (take num)
    (map |(table ;(kvs $)))))

  (while (not (empty? cards))
    (def [card & rest] cards)
    (print "\t" (card :front))
    (if (nil? (file/read stdin :line)) (break))
    (print "\t" (card :back))
    (def score (do
      (def f (fiber/new read-score))
      (defn lp [f val]
        (case val
          :edit (do (edit-card card) (lp f (resume f)))
          :empty nil
          val))
      (lp f (resume f))))
    (if (nil? score) (break))

    (put card :tested (os/time))
    (def q (- 5 score))
    (put card :ef (max 1.3 (+ (card :ef) (- 0.1 (* q (+ 0.08 (* q 0.02)))))))
    (if (< score 3)
      (do
        (put card :i 1)
        (put card :n 0)
        (array/push cards card))
      (do
        (case (card :n)
          0 (put card :i 1)
          1 (put card :i 6)
          (put card :i (math/floor (* (card :i) (card :ef)))))
        (put card :n (inc (card :n)))))

    (try
      (sql/eval db
        "UPDATE cards SET
          front = :front, back = :back, tested = :tested,
          i = :i, n = :n, ef = :ef
         WHERE id = :id"
        card)
      ([msg _]
       (print "Coudln't update card in db: " msg)
       (break)))
    (array/remove cards 0)))

(defn- edit
  [&keys {:id id}]
  (def db (dyn 'db))
  (def cards
    (try
      (sql/eval db
        "SELECT id, front, back, tested, i, n, ef FROM cards WHERE id = ?"
        (tuple id))
      ([msg _]
       (print "couldn't get card for editing: " msg)
       (os/exit 1))))

  (if (empty? cards)
    (do (print "didn't find any cards with id " id) (break)))

  (each card cards
    (def card (table ;(kvs card)))
    (edit-card card)
    (try
      (sql/eval db
        "UPDATE cards SET
          front = :front, back = :back, tested = :tested,
          i = :i, n = :n, ef = :ef
         WHERE id = :id"
        card)
      ([msg _]
       (print "coudln't update card in db: " msg)
       (os/exit 1)))))

(defn main [& args]
  (setdyn *args* args)
  (def outer
    (try
      (cmd/parse toplevel-spec (cmd/args))
      ([msg _]
       (print "error: " msg "\n")
       (cmd/print-help toplevel-spec)
       (os/exit 1))))
  (if (or (nil? (outer :rest)) (empty? (outer :rest)))
    (do
      (print "error: expected subcommand")
      (cmd/print-help toplevel-spec)
      (os/exit 1)))
  (def inner (subcmds (outer :rest) test edit add))
  (def opts (merge outer inner))

  (setdyn 'db (open-db (get opts :file "cards.db")))
  (case (opts :cmd)
    'test (test ;(kvs opts))
    'add (add ;(kvs opts))
    'edit (edit ;(kvs opts))))
