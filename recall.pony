use "cli"
use "files"
use sql = "sqlite3"

primitive OK
primitive Internal
type Error is (
    Internal
  | sql.Error
)

class Card
  var id: (None | I64)
  var front: String val
  var back: String val
  var tested: I64
  var i: I32
  var n: I32
  var ef: F64

  new create(front': String, back': String) =>
    id = None
    front = front'
    back = back'
    tested = 0
    i = 0
    n = 0
    ef = 2.5

  new with_stats(front': String, back': String,
      tested': I64, i': I32, n': I32, ef': F64) =>
    id = None
    front = front'
    back = back'
    tested = tested'
    i = i'
    n = n'
    ef = ef'

class CardsDB
  let db: sql.DB

  new trn create(db': sql.DB iso) =>
    db = consume db'

  fun insert(card: Card ref): (OK | Error) =>
    let stmt = try
      db.prepare("""
        INSERT INTO cards
        VALUES (NULL, ?, ?, ?, ?, ?, ?)
        RETURNING id
      """)?
    else
      return Internal
    end

    let stmt': sql.Stmt iso =
      match stmt
      | let s: sql.Stmt => consume s
      | let e: sql.Error => return e
      end

    let bound = (consume stmt').bind_or_err([
      card.front
      card.back
      card.tested
      card.i
      card.n
      card.ef
    ])
    let bound' =
      match bound
      | let s: sql.Stmt => consume s
      | let e: sql.Error => return e
      end

    match bound'.step()
    | sql.Done => return Internal
    | sql.Row => None
    | let e: sql.Error => return e
    end

    card.id = bound'.column_int64_unsafe(0)
    match bound'.step()
    | sql.Done => OK
    | sql.Row => Internal
    | let e: sql.Error => e
    end

  fun update_card(card: Card): (OK | Error) =>
    let id =
      match card.id
      | None => return Internal
      | let x: I64 => x
      end

    let stmt = try
      db.prepare("""
        UPDATE cards SET
          front = ?,
          back = ?,
          tested = ?,
          i = ?,
          n = ?,
          ef = ?
        WHERE id = ?
      """)?
    else
      return Internal
    end

    let stmt': sql.Stmt iso =
      match stmt
      | let s: sql.Stmt => consume s
      | let e: sql.Error => return e
      end

    let bound = (consume stmt').bind_or_err([
      card.front
      card.back
      card.tested
      card.i
      card.n
      card.ef
      id
    ])
    let bound' =
      match bound
      | let s: sql.Stmt => consume s
      | let e: sql.Error => return e
      end
    match bound'.step()
    | sql.Done => OK
    | sql.Row => Internal
    | let e: sql.Error => e
    end

class OptionParser
  let spec: CommandSpec box
  let parser: CommandParser box

  new create()? =>
    let root = CommandSpec.parent(
      "recall", "a simple spaced-repetition program to help with memory recall",
      [ OptionSpec.string("file", "path to the sqlite db"
          where short' = 'f', default' = "$XDG_DATA_DIR/recall/cards.db")
    ])?

    let add = CommandSpec.leaf(
      "add", "add cards to the database",
      [ OptionSpec.string("front", "front matter for the card"
          where default' = "")
        OptionSpec.string("back", "back matter for the card"
          where default' = "")
        OptionSpec.bool("interactive", "add cards in interactive mode"
          where short' = 'i', default' = true)
    ])?

    let test = CommandSpec.leaf(
      "test", "test your recall!",
      [ OptionSpec.i64("num", "number of cards to test", 'n', 0) ])?

    root.add_command(add)?
    root.add_command(test)?
    root.add_help()?

    spec = root
    parser = CommandParser(spec)

  fun parse(
      args: Array[String val] box,
      envs: (Array[String val] box | None) = None)
      : (Options | CommandHelp | SyntaxError) =>
    match parser.parse(args, envs)
    | let c: Command => Options(c)
    | let h: CommandHelp => h
    | let e: SyntaxError => e
    end

  fun print_help(os: OutStream tag) =>
    Help.general(spec).print_help(os)

class Options
  let cmd: Command

  new create(cmd': Command) =>
    cmd = cmd'

  fun print_help(os: OutStream tag) =>
      Help.general(cmd.spec()).print_help(os)

  fun db_path(): String =>
    cmd.option("file").string()

actor Main
  let env: Env

  new create(root_env: Env) =>
    env = root_env

    let parser = try
      OptionParser.create()?
    else
      env.err.print("couldn't create option parser")
      env.exitcode(1)
      return
    end
    let opts = match parser.parse(env.args, env.vars)
    | let o: Options => o
    | let h: CommandHelp =>
      h.print_help(env.err)
      env.exitcode(0)
      return
    | let e: SyntaxError =>
      env.err.print(e.string())
      parser.print_help(env.err)
      env.exitcode(1)
      return
    end

    env.err.print("DB path: " + opts.db_path())

    let db = try
      open_db("cards.db")?
    else
      return
    end

    let c = Card("What year was Y2K expected to occur?", "2000")
    match db.insert(c)
    | Internal =>
      env.err.print("internal error when inserting a card...")
      env.exitcode(1)
      return
    | let err: sql.Error =>
      env.err.print("couldn't insert a card into the DB (" + err.name() + ")")
      env.exitcode(1)
      return
    end

    env.err.print("Ready to rock and roll with card #" + c.id.string())

    c.front = "I lied"
    c.back = "I lied"
    c.ef = 10
    c.i = 10000000
    c.n = 10000
    match db.update_card(c)
    | Internal =>
      env.err.print("internal error when inserting a card...")
      env.exitcode(1)
      return
    | let err: sql.Error =>
      env.err.print("couldn't insert a card into the DB (" + err.name() + ")")
      env.exitcode(1)
      return
    end

  fun open_db(dbpath: String): CardsDB? =>
    let db =
      match sql.OpenDB(FilePath(FileAuth(env.root), dbpath))
      | let db: sql.DB iso => consume db
      else
        env.err.print("unable to open db " + dbpath)
        env.exitcode(1)
        error
      end

    let create_stmt = try
      db.prepare("""
        CREATE TABLE IF NOT EXISTS cards (
          id INTEGER PRIMARY KEY,
          front TEXT UNIQUE,
          back TEXT,
          tested INTEGER,
          i INTEGER,
          n INTEGER,
          ef REAL
        )""")?
    else
      env.err.print("""
        query size to create table exceeded max size
           (this should never happen)
      """)
      env.exitcode(1)
      error
    end

    let create_stmt' =
      match create_stmt
      | let s: sql.Stmt => consume s
      | let e: sql.Error =>
        env.err.print("unable to create the cards db (" + e.name() + ")")
        env.exitcode(1)
        error
      end

    match create_stmt'.step()
    | sql.Done => (consume create_stmt').finalise()
    | let e: sql.Error =>
      env.err.print("unable to create the cards db (" + e.name() + ")")
      env.exitcode(1)
      error
    end

    CardsDB(consume db)
