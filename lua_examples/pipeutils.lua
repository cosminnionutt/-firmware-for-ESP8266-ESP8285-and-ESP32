-- A collection of pipe-based utility functions

-- A convenience wrapper for chunking data arriving in bursts into more sizable
-- blocks; `o` will be called once per chunk.  The `flush` method can be used to
-- drain the internal buffer.  `flush` MUST be called at the end of the stream,
-- **even if the stream is a multiple of the chunk size** due to internal
-- buffering.  Flushing results in smaller chunk(s) being output, of course.
local function chunker(o, csize, prio)
  assert (type(o) == "function" and type(csize) == "number" and 1 <= csize)
  local p = pipe.create(function(p)
              -- wait until it looks very likely that read is going to succeed
              -- and we won't have to unread.  This may hold slightly more than
              -- a chunk in the underlying pipe object.
              if 256 * (p:nrec() - 1) <= csize then return nil end

              local d = p:read(csize)
              if #d < csize
               then p:unread(d) return false
               else o(d)        return true
              end
            end, prio or node.task.LOW_PRIORITY)

  return {
    flush = function() for d in p:reader(csize) do o(d) end end,
    write = function(d) p:write(d) end
  }
end

-- Stream and decode lines of complete base64 blocks, calling `o(data)` with
-- decoded chunks or calling `e(badinput, errorstr)` on error; the error
-- callback must ensure that this conduit is never written to again.
local function debase64(o, e, prio)
  assert (type(o) == "function" and type(e) == "function")
  local p = pipe.create(function(p)
              local s = p:read("\n+")
              if s:sub(-1) == "\n" then -- guard against incomplete line
                s = s:match("^%s*(%S*)%s*$")
                if #s ~= 0 then -- guard against empty line
                  local ok, d = pcall(encoder.fromBase64, s)
                  if ok then o(d) else e(s, d); return false end
                end
                return true
              else
                p:unread(s)
                return false
              end
            end, prio or node.task.LOW_PRIORITY)
  return { write = function(d) p:write(d) end }
end

return {
  chunker = chunker,
  debase64 = debase64,
}
