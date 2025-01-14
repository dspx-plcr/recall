use "files"

class iso WaitForMatter is InputNotify
  let int: AddingInteractive tag
  var multi: Bool = false
  var nquotes: U8 = 0
  var parsing: Bool = true
  var str: String iso = recover String end

  new iso create(int': AddingInteractive tag) =>
    int = int'

  /* TODO: Implement backspace (and movement???) */
  /* TODO: Look into readline and ansi term */
  /* TODO: strip off leading whitespace first */
  /* TODO: Don't go to next step until \n after """ */
  fun ref apply(data: Array[U8] iso) =>
    if not parsing then
      return
    end

    let datasize = data.size()
    var data' = recover val String.from_iso_array(consume data) end
    int.echo(data')

    let prevsize = str.size()
    str = (consume str) + data'
    if (not multi) and (prevsize < 3) and (str.size() >= 3) then
      multi = try
        (str(0)? == '"') and (str(1)? == '"') and (str(2)? == '"')
      else
        false
      end
      if multi then
        str.trim_in_place(3)
        data' = data'.trim(3-prevsize)
      end
    end

    let simple_done = try
      (str(str.size()-1)? == '\n') and (not multi)
    else
      false
    end
    if simple_done then
      str.strip()
      int.got_matter(str = recover String end)
      parsing = false
      return
    end

    if multi then
      // check if we're continuing three quotes
      var i: USize = 0
      var need: U8 = (3 - nquotes).u8()
      while i.u8() < (3 - nquotes) do
        try
          if data'(i)? == '"'
          then need = need - 1
          else error
          end
        else
          break
        end
        i = i + 1
      end
      let initialsize = str.size() - data'.size()
      if need == 0 then
        str.trim_in_place(0, initialsize-nquotes.usize())
        int.got_matter(str = recover String end)
        parsing = false
        return
      end

      // check if we just have three quotes
      try
        let idx = data'.find("\"\"\"")?.usize()
        str.trim_in_place(0, initialsize+idx)
        int.got_matter(str = recover String end)
        parsing = false
        return
      end

      // update the number of quotes
      i = str.size()-1
      nquotes = 0
      while (i > 0) do
        try if str(i)? != '"' then break end
        else break end
        nquotes = nquotes + 1
        i = i - 1
      end
    end

actor AddingInteractive
  let db: CardsDB
  let term: Terminal
  var front: (None | String) = None

  new create(db': CardsDB iso, term': Terminal) =>
    db = consume db'
    term = term'

  be run() =>
    term.output.print(match front
      | None => "Front?"
      else "Back?"
    end)
    term.input(WaitForMatter(this))

  be got_matter(str: String val) =>
    term.input.dispose()
    term.output.print("")

    /* TODO: confirm before exit */
    if str.size() == 0 then
      return
    end

    match front
    | None => front = str
    | let s: String =>
      match db.insert(Card(s, str))
      | OK => None
      | let e: Error =>
        term.err.print("couldn't add card to db (" + e.name() + ")")
        term.exit(1)
        return
      end
      front = None
    end
    run()

  be echo(str: String val) =>
    term.output.write(str)

primitive Done
primitive ParseError
class AddingFileParser
  let db: CardsDB
  let file: File

  new create(db': CardsDB, file': File) =>
    db = db'
    file = file'

  fun apply(): (OK | ParseError) =>
    OK

  fun read_one(): (Done | Card | ParseError) =>
    Done
