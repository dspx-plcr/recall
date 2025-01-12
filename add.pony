actor AddingInteractive
  let db: CardsDB
  let term: Terminal

  new create(db': CardsDB iso, term': Terminal) =>
    db = consume db'
    term = term'

  be run() =>
    None
