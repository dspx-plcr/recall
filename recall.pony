use "cli"
use "files"
use "time"
use sql = "sqlite3"

primitive OK
primitive Internal
  fun name(): String => "internal error"
type Error is (
    Internal
  | sql.Error
)

class val Terminal
  let input: InputStream
  let output: OutStream
  let err: OutStream
  let exit: {(I32)} val

  new create(input': InputStream, output': OutStream, err': OutStream,
      exit': {(I32)} val) =>
    input = input'
    output = output'
    err = err'
    exit = exit'

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
          where short' = 'i', default' = false)
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

primitive Test
primitive Add
type SubCommand is (Test | Add)
class Options
  let cmd: Command

  new create(cmd': Command) =>
    cmd = cmd'

  fun print_help(os: OutStream tag) =>
    Help.general(cmd.spec()).print_help(os)

  fun sub(): SubCommand? =>
    match cmd.spec().name()
    | "test" => Test
    | "add" => Add
    else error
    end

  fun db_path(): String => cmd.option("file").string()
  fun front(): String => cmd.option("front").string()
  fun back(): String => cmd.option("back").string()
  fun multi(): String => cmd.option("multi").string()
  fun interactive(): Bool => cmd.option("interactive").bool()

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

    let db = try
      open_db("cards.db")?
    else
      return
    end

    try
      match (opts.sub()?, consume db)
      | (Add, let db': CardsDB iso) => add(consume db', opts)
      | (Test, let db': CardsDB iso) => test(consume db', opts)
      end
    else
      env.err.print("internal error: unrecognised command")
      env.exitcode(1)
    end

  fun open_db(dbpath: String): CardsDB iso? =>
    let db = match sql.OpenDB(FilePath(FileAuth(env.root), dbpath))
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

    let create_stmt' = match create_stmt
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

    recover CardsDB(consume db) end

  fun add(db: CardsDB iso, opts: Options) =>
    if opts.interactive() then
      AddingInteractive(consume db,
        Terminal(env.input, env.out, env.err, env.exitcode))
        .run()
    elseif (opts.front() != "") and (opts.back() != "") then
      match (consume db).insert(Card(opts.front(), opts.back()))
      | OK => None
      | let e: Error =>
        env.err.print("couldn't insert card into db (" + e.name() + ")")
        env.exitcode(1)
      end
    elseif opts.multi() != "" then
      None
    else
      opts.print_help(env.err)
    end

  fun test(db: CardsDB iso, opts: Options) =>
    let cards' = match db.read_all_cards()
      | let cs: Array[Card] iso => consume cs
      | Internal =>
        env.err.print("couldn't read cards from database")
        env.exitcode(1)
        return
      | let e: sql.Error =>
        env.err.print(
          "couldn't read all cards from database (" + e.name() + ")")
        env.exitcode(1)
        return
    end

    let cs = get_cards_to_test(consume cards')
    let orch = TestingOrchestrator(consume db, consume cs,
      Terminal(env.input, env.out, env.err, env.exitcode))
    orch.test()

  fun get_cards_to_test(cards: Array[Card] iso): Array[Card] iso^ =>
    (let secs, _) = Time.now()
    recover
      let res = Array[Card]
      for c in (consume cards).values() do
        if (secs <= c.tested) or
          (((secs - c.tested) / (60*60*24)) >= c.i.i64())
        then
          res.push(c)
        end
      end
      res
    end
