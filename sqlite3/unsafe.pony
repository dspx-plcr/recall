use "files"

use "lib:sqlite3"

use @sqlite3_open[NativeInt](filename: Pointer[U8] tag, db: Pointer[_PConn])
use @sqlite3_prepare_v2[NativeInt](db: _PConn, sql: Pointer[U8] tag,
  sqllen: NativeInt, stmt: Pointer[_PStmt], unused: Pointer[Pointer[U8] ref])
use @sqlite3_bind_double[NativeInt](stmt: _PStmt, col: NativeInt, num: F64)
use @sqlite3_bind_int[NativeInt](stmt: _PStmt, col: NativeInt, num: NativeInt)
use @sqlite3_bind_int64[NativeInt](stmt: _PStmt, col: NativeInt, num: I64)
use @sqlite3_bind_text[NativeInt](stmt: _PStmt, col: NativeInt,
  text: Pointer[U8] tag, len: NativeInt, destructor: Pointer[None])
use @sqlite3_step[NativeInt](stmt: _PStmt)
use @sqlite3_column_count[NativeInt](stmt: _PStmt)
use @sqlite3_column_double[F64](stmt: _PStmt, col: NativeInt)
use @sqlite3_column_int[NativeInt](stmt: _PStmt, col: NativeInt)
use @sqlite3_column_int64[I64](stmt: _PStmt, col: NativeInt)
use @sqlite3_column_text[Pointer[U8]](stmt: _PStmt, col: NativeInt)
use @sqlite3_finalize[NativeInt](stmt: _PStmt)
use @sqlite3_close_v2[NativeInt](db: _PConn)

// TODO: Sort this out
type NativeInt is I32

primitive _Conn
type _PConn is Pointer[_Conn] tag
primitive _Stmt
type _PStmt is Pointer[_Stmt] tag

primitive OpenDB
  fun apply(file: FilePath): (DB iso^ | Error val) =>
    var handle: _PConn = _PConn
    let res = @sqlite3_open(file.path.cstring(), addressof handle)
    if res == 0 then
      DB._create(consume handle)
    else
      ToError.fromInt(res)
    end

class DB
  let _handle: _PConn
  var _closed: Bool = false

  new iso _create(handle: _PConn) =>
    _handle = consume handle

  fun prepare(sql: String val): (Stmt iso^ | Error val)? =>
    let len = if sql.size() <= I32.max_value().usize() then
      sql.size().i32()
    else
      error
    end
    var stmt: _PStmt = _PStmt
    var unused: Pointer[U8] ref = recover ref Pointer[U8] end
    let res = @sqlite3_prepare_v2(_handle, sql.cstring(), len,
      addressof stmt, addressof unused)
    if res == 0 then
      let unused' = String.copy_cstring(consume unused).clone()
      Stmt._create(consume stmt, consume unused')
    else
      ToError.fromInt(res)
    end

  fun iso close() =>
    @sqlite3_close_v2(_handle)
    _closed = true

  fun iso dispose() =>
    if not _closed then
      (consume this).close()
    end

  fun _final() =>
    if not _closed then
      @sqlite3_close_v2(_handle)
    end

type BindType is (F64 | NativeInt | I64 | String)
class iso Stmt
  let _handle: _PStmt
  var _finalised: Bool = false
  let unused: String val

  new iso _create(handle: _PStmt, unused': String = "") =>
    _handle = handle
    unused = unused'

  fun iso bind_or_err(binds: Array[BindType]): (Stmt iso^ | Error) =>
    var col: NativeInt = 1
    for b in binds.values() do
      let res =
        match b
        | let v: String => bind_text_unsafe(col, v)
        | let v: F64 => bind_double_unsafe(col, v)
        | let v: NativeInt => bind_int_unsafe(col, v)
        | let v: I64 => bind_int64_unsafe(col, v)
        end

      match res
      | OK => col = col + 1
      | let err: Error => return err
      end
    end
    consume this

  fun bind_double_partial_unsafe(col: NativeInt, num: F64)? =>
    match bind_double_unsafe(col, num)
    | OK => None
    else error
    end

  fun bind_double_unsafe(col: NativeInt, num: F64): (OK | Error) =>
    let res = @sqlite3_bind_double(_handle, col, num)
    if res == 0 then
      OK
    else
      ToError.fromInt(res)
    end

  fun bind_int_partial_unsafe(col: NativeInt, num: NativeInt)? =>
    match bind_int_unsafe(col, num)
    | OK => None
    else error
    end

  fun bind_int_unsafe(col: NativeInt, num: NativeInt): (OK | Error) =>
    let res = @sqlite3_bind_int(_handle, col, num)
    if res == 0 then
      OK
    else
      ToError.fromInt(res)
    end

  fun bind_int64_partial_unsafe(col: NativeInt, num: I64)? =>
    match bind_int64_unsafe(col, num)
    | OK => None
    else error
    end

  fun bind_int64_unsafe(col: NativeInt, num: I64): (OK | Error) =>
    let res = @sqlite3_bind_int64(_handle, col, num)
    if res == 0 then
      OK
    else
      ToError.fromInt(res)
    end

  fun bind_text_partial_unsafe(col: NativeInt, str: String)? =>
    match bind_text_unsafe(col, str)
    | OK => None
    else error
    end

  fun bind_text_unsafe(col: NativeInt, str: String): (OK | Error) =>
    let res = @sqlite3_bind_text(_handle, col, str.cstring(), str.size().i32(),
      @{(s: Pointer[None]) => None})
    if res == 0 then
      OK
    else
      ToError.fromInt(res)
    end

  fun column_count(): NativeInt =>
    @sqlite3_column_count(_handle)

  fun column_double_unsafe(col: NativeInt): F64 =>
    @sqlite3_column_double(_handle, col)

  fun column_int_unsafe(col: NativeInt): NativeInt =>
    @sqlite3_column_int(_handle, col)

  fun column_int64_unsafe(col: NativeInt): I64 =>
    @sqlite3_column_int64(_handle, col)

  fun column_text_unsafe(col: NativeInt): String =>
    recover String.copy_cstring(@sqlite3_column_text(_handle, col)) end

  // TODO: Can OK be returned here?
  fun step(): (Done | Row | Error) =>
    match @sqlite3_step(_handle)
    | Done.int() => Done
    | Row.int() => Row
    | let err: NativeInt => ToError.fromInt(err)
    end

  fun iso finalise(): (OK | Error) =>
    if _finalised then
      OK
    end

    let res = @sqlite3_finalize(_handle)
    _finalised = true
    if res == 0 then
      OK
    else
      ToError.fromInt(res)
    end

  fun _final() =>
    if not _finalised then
      @sqlite3_finalize(_handle)
    end
