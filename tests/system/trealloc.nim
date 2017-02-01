discard """
  output: '''success'''
"""

# bug #4818

# Test that this completes without OOM.

const BUFFER_SIZE = 5000
var buffer = cast[ptr uint16](alloc(BUFFER_SIZE))

var total_size: int64 = 0
for i in 0 .. 4000:
    let size = BUFFER_SIZE * i
    #echo "requesting ", size
    total_size += size.int64
    buffer = cast[ptr uint16](realloc(buffer, size))
    #echo totalSize, " total: ", getTotalMem(), " occupied: ", getOccupiedMem(), " free: ", getFreeMem()

dealloc(buffer)
echo "success"
