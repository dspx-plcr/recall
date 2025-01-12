use "time"

class iso GetScoreNotifier is InputNotify
  var str: String iso = recover String end
  let orch: TestingOrchestrator tag

  new iso create(orch': TestingOrchestrator tag) =>
    orch = orch'

  fun ref apply(data: Array[U8] iso) =>
    let data' = recover val String.from_iso_array(consume data) end
    orch.echo(data')
    let done = try
      data'(data'.size()-1)? == '\n'
    else
      orch.no_score_from_user()
      return
    end
    str = str + data'
    if done then
      orch.parse_score(str = recover String end)
    end

class iso WaitForInputNotifier is InputNotify
  var str: String = ""
  let orch: TestingOrchestrator tag

  new iso create(orch': TestingOrchestrator tag) =>
    orch = orch'

  fun ref apply(data: Array[U8] iso) =>
    let data' = recover val String.from_iso_array(consume data) end
    let done = try
      data'(data'.size()-1)? == '\n'
    else
      orch.no_input_from_user()
      return
    end
    str = str + data'
    if done then
      orch.prompt_for_score()
    end

actor TestingOrchestrator
  let db: CardsDB
  var cards: Seq[Card]
  var card: (None | Card)
  let term: Terminal

  new create(db': CardsDB iso, cards': Seq[Card] iso, term': Terminal) =>
    db = consume db'
    cards = consume cards'
    card = None
    term = term'

  be test() =>
    let card' = match card
      | None =>
        try
          if cards.size() == 0 then
            error
          end
          cards.pop()?
        else
          return
        end
      | let c: Card => c
    end

    card = card'
    term.output.write("\t" + card'.front)
    term.input(WaitForInputNotifier(recover this end))

  be prompt_for_score() =>
    let card' = match card
      | None => return
      | let c: Card => c
    end
    term.output.print("")
    term.output.print("Correct answer was")
    term.output.print("\t" + card'.back)
    term.output.print("How did you do?")
    term.output.write("""
      0: Complete failure to recall the information
      1: Incorrect, but upon seeing the answer, it seemed familiar
      2: Incorrect, but upon seeing the answer, it seemed easy
      3: Correct, but after significant effort
      4: Correct, after some hesitation
      5: Correct with perfect recall
      """)
    term.input(GetScoreNotifier(recover this end))

  be parse_score(score: String iso) =>
    let c = match card
      | None => return
      | let c: Card => c
    end

    let s = try
      score.strip()
      let s = score.u8()?
      if s > 5 then
        error
      end
      s
    else
      prompt_for_score()
      return
    end

    term.input.dispose()
    card = None

    let id = match c.id
      | None =>
        term.err.print("internal error (card without database id)")
        term.exit(1)
        return
      | let i: I64 => i
    end

    (let i, let n) =
      if s < 3 then
        (1, 0)
      else
        let i = match c.n
          | 0 => 1
          | 1 => 6
          | let n: I32 => (c.i.f64() * c.ef).i32()
        end
        (i, c.n + 1)
      end
    let q = (5 - s).f64()
    let ef = (c.ef + (0.1 - (q * (0.08 + (q * 0.02))))).max(1.3)
    (let tested, _) = Time.now()

    let res = db.update_card(
      Card.manually(id, c.front, c.back, tested, i, n, ef))
    match res
    | OK => test()
    | let e: Error =>
      term.err.print(
        "couldn't save updated card info in database (" + e.name() + ")")
      term.exit(1)
    end

  be echo(str: String val) =>
    term.output.write(str)

  be no_input_from_user() =>
    term.err.print("error reading input")
    term.input.dispose()
    term.exit(1)

  be no_score_from_user() =>
    term.err.print("error reading score")
    term.input.dispose()
    term.exit(1)
