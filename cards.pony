use sql = "sqlite3"

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
    /* TODO: int min? */
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

  new manually(id': I64, front': String, back': String,
      tested': I64, i': I32, n': I32, ef': F64) =>
    id = id'
    front = front'
    back = back'
    tested = tested'
    i = i'
    n = n'
    ef = ef'

class CardsDB
  let db: sql.DB

  new create(db': sql.DB iso) =>
    db = consume db'

  fun ref insert(card: Card): (OK | Error) =>
    /* TODO: strip spaces from front and back matter */
    /* TODO: Or maybe that should be done on input??? */
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

  fun ref update_card(card: Card): (OK | Error) =>
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

  fun read_all_cards(): (Array[Card] iso^ | Error) =>
    let stmt = try
      db.prepare("""
        SELECT id, front, back, tested, i, n, ef
        FROM cards
      """)?
    else
      return Internal
    end

    let stmt': sql.Stmt iso =
      match stmt
      | let s: sql.Stmt => consume s
      | let e: sql.Error => return e
      end

    recover
      let res = Array[Card]
      while true do
        match stmt'.step()
        | sql.Done => break res
        | let e: sql.Error => break e
        | sql.Row =>
          if stmt'.column_count() != 7 then
            break Internal
          end
          res.push(Card.manually(
            stmt'.column_int64_unsafe(0),
            stmt'.column_text_unsafe(1),
            stmt'.column_text_unsafe(2),
            stmt'.column_int64_unsafe(3),
            stmt'.column_int_unsafe(4),
            stmt'.column_int_unsafe(5),
            stmt'.column_double_unsafe(6)))
          res
        end
      else
        res
      end
    end
