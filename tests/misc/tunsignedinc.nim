
block: # bug #2427
  var x = 0'u8
  dec x # OverflowError
  x -= 1 # OverflowError
  x = x - 1 # No error

  doAssert(x == 253'u8)

block:
  var x = 130'u8
  x += 130'u8
  doAssert(x == 4'u8)

block:
  var x = 40000'u16
  x = x + 40000'u16
  doAssert(x == 14464'u16)

block:
  var x = 4000000000'u32
  x = x + 4000000000'u32
  doAssert(x == 3705032704'u32)

block:
  var x = 123'u16
  x -= 125
  doAssert(x == 65534'u16)
