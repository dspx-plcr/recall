
primitive OK
  fun name(): String => "OK"
  fun int(): NativeInt => 0
primitive Abort
  fun name(): String => "Abort"
  fun int(): NativeInt => 4
primitive Busy
  fun name(): String => "Busy"
  fun int(): NativeInt => 5
primitive CantOpen
  fun name(): String => "CantOpen"
  fun int(): NativeInt => 14
primitive Constraint
  fun name(): String => "Constraint"
  fun int(): NativeInt => 19
primitive Corrupt
  fun name(): String => "Corrupt"
  fun int(): NativeInt => 11
primitive Done
  fun name(): String => "Done"
  fun int(): NativeInt => 101
primitive Empty
  fun name(): String => "Empty"
  fun int(): NativeInt => 16
primitive Generic
  fun name(): String => "Generic"
  fun int(): NativeInt => 1
primitive Format
  fun name(): String => "Format"
  fun int(): NativeInt => 24
primitive Full
  fun name(): String => "Full"
  fun int(): NativeInt => 13
primitive Internal
  fun name(): String => "Internal"
  fun int(): NativeInt => 2
primitive Interrupt
  fun name(): String => "Interrupt"
  fun int(): NativeInt => 9
primitive IO
  fun name(): String => "IO"
  fun int(): NativeInt => 10
primitive Locked
  fun name(): String => "Locked"
  fun int(): NativeInt => 6
primitive Mismatch
  fun name(): String => "Mismatch"
  fun int(): NativeInt => 20
primitive Misuse
  fun name(): String => "Misuse"
  fun int(): NativeInt => 21
primitive NoLFS
  fun name(): String => "NoLFS"
  fun int(): NativeInt => 22
primitive NoMem
  fun name(): String => "NoMem"
  fun int(): NativeInt => 7
primitive NotADB
  fun name(): String => "NotADB"
  fun int(): NativeInt => 26
primitive NotFound
  fun name(): String => "NotFound"
  fun int(): NativeInt => 12
primitive Notice
  fun name(): String => "Notice"
  fun int(): NativeInt => 27
primitive Perm
  fun name(): String => "Perm"
  fun int(): NativeInt => 3
primitive Protocol
  fun name(): String => "Protocol"
  fun int(): NativeInt => 15
primitive Range
  fun name(): String => "Range"
  fun int(): NativeInt => 25
primitive ReadOnly
  fun name(): String => "ReadOnly"
  fun int(): NativeInt => 8
primitive Row
  fun name(): String => "Row"
  fun int(): NativeInt => 100
primitive Schema
  fun name(): String => "Schema"
  fun int(): NativeInt => 17
primitive TooBig
  fun name(): String => "TooBig"
  fun int(): NativeInt => 18
primitive Warning
  fun name(): String => "Warning"
  fun int(): NativeInt => 28
primitive Unknown
  fun name(): String => "Unknown"

type Error is (
    Abort
  | Busy
  | CantOpen
  | Constraint
  | Corrupt
  | Empty
  | Generic
  | Format
  | Full
  | Internal
  | Interrupt
  | IO
  | Locked
  | Mismatch
  | Misuse
  | NoLFS
  | NoMem
  | NotADB
  | NotFound
  | Notice
  | Perm
  | Protocol
  | Range
  | ReadOnly
  | Schema
  | TooBig
  | Warning
  | Unknown
)

primitive ToError
  fun fromInt(code: I32): Error =>
    match code
    | Abort.int() => Abort
    | Busy.int() => Busy
    | CantOpen.int() => CantOpen
    | Constraint.int() => Constraint
    | Corrupt.int() => Corrupt
    | Empty.int() => Empty
    | Generic.int() => Generic
    | Format.int() => Format
    | Full.int() => Full
    | Internal.int() => Internal
    | Interrupt.int() => Interrupt
    | IO.int() => IO
    | Locked.int() => Locked
    | Mismatch.int() => Mismatch
    | Misuse.int() => Misuse
    | NoLFS.int() => NoLFS
    | NoMem.int() => NoMem
    | NotADB.int() => NotADB
    | NotFound.int() => NotFound
    | Notice.int() => Notice
    | Perm.int() => Perm
    | Protocol.int() => Protocol
    | Range.int() => Range
    | ReadOnly.int() => ReadOnly
    | Schema.int() => Schema
    | TooBig.int() => TooBig
    | Warning.int() => Warning
    else Unknown
    end
