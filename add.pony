use "buffered"
use "files"
use "promises"

class MatterParser
  var multi: Bool = false
  var nquotes: U8 = 0
  var parsing: Bool = true
  var str: String iso = recover String end
  var extra: Array[U8] iso = recover Array[U8] end
  
  new create() => None

  fun ref result(): (String iso^, Array[U8] iso^) =>
    parsing = true
    nquotes = 0
    multi = false
    (str = recover String end, extra = Array[U8])

  /* TODO: Implement backspace (and movement???) */
  /* TODO: Look into readline and ansi term */
  fun ref apply(data: Array[U8] iso): Bool =>
    if not parsing then
      extra.append(consume data)
      return false
    end

    let datasize = data.size()
    var data' = recover val String.from_iso_array(consume data) end

    let prevsize = str.size()

    str = (consume str) + data'
    if prevsize == 0 then
      str.lstrip()
    end

    if (not multi) and (prevsize < 3) and (str.size() >= 3) then
      multi = try
        (str(0)? == '"') and (str(1)? == '"') and (str(2)? == '"')
      else
        false
      end
      if multi then
        str.trim_in_place(3)
        str.lstrip()
        data' = data'.trim(3-prevsize)
      end
    end

    if not multi then
      try
        let idx = str.find("\n")?
        (str, let ex) = (str = recover String end).chop(idx.usize()+1)
        extra = (consume ex).iso_array()
        str.rstrip()
        parsing = false
        return parsing
      end
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
        (str, let ex) = (str = recover String end)
          .chop((initialsize-nquotes.usize()))
        extra = (consume ex).iso_array()
        str.rstrip()
        extra.trim_in_place(3)
        parsing = false
        return parsing
      end

      // check if we just have three quotes
      try
        let idx = data'.find("\"\"\"")?.usize()
        (str, let ex) = (str = recover String end).chop((initialsize+idx))
        str.rstrip()
        extra = (consume ex).iso_array()
        extra.trim_in_place(3)
        parsing = false
        return parsing
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

    parsing

type ParseResult is (String iso^, Array[U8] iso^)
trait FiniteReceiver
  fun ref apply(data: Array[U8] iso): Bool
  fun iso done(): ParseResult

type QueuedReader is (FiniteReceiver iso, Promise[String])
actor BufferedInput
  let buf: Reader = Reader
  var recpt: (None | QueuedReader) = None
  var future: Array[QueuedReader] = Array[QueuedReader]

  new create() => None

  be apply(data: Array[U8] iso) =>
    match recpt
    | None =>
      if future.size() == 0 then
        buf.append(consume data)
        return
      else
        try
          (let r, let p) = future.shift()?
          r(buf.block(buf.size())?)
          recpt = (consume r, p)
        end
      end
    end

    match recpt = None
    | (let r: FiniteReceiver iso, let p: Promise[String]) =>
      if not r(consume data) then
        (let str, let ex) = (consume r).done()
        buf.append(consume ex)
        p(consume str)
        recpt = None
      else
        recpt = (consume r, p)
      end
    end

  be queue(notifier: FiniteReceiver iso, promise: Promise[String]) =>
    let tmp: QueuedReader = (consume notifier, promise)
    match recpt
    | None =>
      recpt = consume tmp
      if buf.size() > 0 then
        let b = try buf.block(buf.size())? else recover Array[U8] end end
        apply(consume b)
      end
    else
      future.push(consume tmp)
    end

class iso WaitForMatter is FiniteReceiver
  let int: AddingInteractive
  let parser: MatterParser iso = recover MatterParser end

  new iso create(int': AddingInteractive) =>
    int = int'

  fun ref apply(data: Array[U8] iso): Bool =>
    let data' = recover
      let d = Array[U8].create(data.size())
      var i: USize = 0
      while i < data.size() do
        d.push(try data(i)? else 0 end)
        i = i + 1
      end
      d
    end
    int.echo(recover val String.from_iso_array(consume data') end)
    parser(consume data)

  fun iso done(): ParseResult =>
    parser.result()

actor AddingInteractive
  let db: CardsDB
  let term: Terminal
  var front: (None | String) = None
  var buf: BufferedInput = BufferedInput

  new create(db': CardsDB iso, term': Terminal) =>
    db = consume db'
    term = term'

  be got_matter(str: String val) =>
    term.output.print("")

    /* TODO: confirm before exit */
    if str.size() == 0 then
      return
    end

    match front
    | None =>
      front = str
      let pback = Promise[String]
      pback.next[None]({
        (s: String)(x: AddingInteractive = this) => x.got_matter(s) })
      term.output.print("Back?")
      buf.queue(WaitForMatter(this), pback)
    | let s: String =>
      match db.insert_both(s, str)
      | OK => None
      | let e: Error =>
        term.err.print("couldn't add cards to db (" + e.name() + ")")
        term.exit(1)
        return
      end
      front = None
      let pfront = Promise[String]
      pfront.next[None]({
        (s: String)(x: AddingInteractive = this) => x.got_matter(s) })
      term.output.print("Front?")
      buf.queue(WaitForMatter(this), pfront)
    end

  be run() =>
    term.input(object iso is InputNotify
      let b: BufferedInput = buf
      fun ref apply(data: Array[U8] iso) => b(consume data)
      fun ref dispose() => None
    end)

    let pfront = Promise[String]
    pfront.next[None]({
      (s: String)(x: AddingInteractive = this) => x.got_matter(s) })
    term.output.print("Front?")
    buf.queue(WaitForMatter(this), pfront)

  be echo(str: String val) =>
    term.output.write(str)

actor FileReader is InputStream
  let file: File

  new create(file': File iso) =>
    file = consume file'

  be apply(notify: (InputNotify iso | None), chunk_size: USize = 32) =>
    match notify
    | let n: InputNotify iso =>
      while file.position() < file.size() do
        n(file.read(chunk_size))
      end
    end

  be dispose() => None

actor NullStream is OutStream
  new create() => None
  be print(data: (String | Array[U8] val)) => None
  be write(data: (String | Array[U8] val)) => None
  be printv(data: ByteSeqIter) => None
  be writev(data: ByteSeqIter) => None
  be flush() => None

primitive Done
primitive ParseError
class AddingFileParser
  let adder: AddingInteractive

  new create(db: CardsDB iso, term: Terminal, file: File iso) =>
    let term' =
      Terminal(FileReader(consume file), term.output, term.err, term.exit)
    adder = AddingInteractive(consume db, term')

  fun apply() =>
    adder.run()
