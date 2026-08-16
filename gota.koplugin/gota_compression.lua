--[[
    Bounded gzip decompression backed by KOReader's bundled zlib.

    The binding is loaded lazily so ordinary identity responses do not depend
    on FFI initialization. Both string and file callers enforce the configured
    limit against decompressed bytes, not just the compressed transfer size.
]]

local Compression = {}

local OUTPUT_CHUNK_BYTES = 64 * 1024
local Z_NO_FLUSH = 0
local Z_OK = 0
local Z_STREAM_END = 1
local Z_BUF_ERROR = -5
local GZIP_WINDOW_BITS = 15 + 16

local bindings
local binding_error

local ZLIB_CDEF = [[
typedef void *(*gota_zalloc_func)(void *, unsigned int, unsigned int);
typedef void (*gota_zfree_func)(void *, void *);
typedef struct gota_z_stream_s {
    unsigned char *next_in;
    unsigned int avail_in;
    unsigned long total_in;
    unsigned char *next_out;
    unsigned int avail_out;
    unsigned long total_out;
    char *msg;
    void *state;
    gota_zalloc_func zalloc;
    gota_zfree_func zfree;
    void *opaque;
    int data_type;
    unsigned long adler;
    unsigned long reserved;
} gota_z_stream;
const char *zlibVersion(void);
int inflateInit2_(gota_z_stream *, int, const char *, int);
int inflate(gota_z_stream *, int);
int inflateEnd(gota_z_stream *);
]]

local function loadBindings()
    if bindings then return bindings end
    if binding_error then return nil, binding_error end

    local ffi_ok, ffi = pcall(require, "ffi")
    if not ffi_ok then
        binding_error = "LuaJIT FFI is unavailable"
        return nil, binding_error
    end

    if not pcall(ffi.typeof, "gota_z_stream") then
        local cdef_ok, cdef_error = pcall(ffi.cdef, ZLIB_CDEF)
        if not cdef_ok then
            binding_error = "could not declare the zlib interface: " .. tostring(cdef_error)
            return nil, binding_error
        end
    end

    local library_ok, library
    if ffi.loadlib then
        library_ok, library = pcall(ffi.loadlib, "z", 1)
    else
        library_ok, library = pcall(ffi.load, "z")
    end
    if not library_ok then
        binding_error = "could not load KOReader's zlib: " .. tostring(library)
        return nil, binding_error
    end

    bindings = { ffi = ffi, library = library }
    return bindings
end

local function streamMessage(ffi, stream, fallback)
    if stream[0].msg ~= nil then
        local ok, message = pcall(ffi.string, stream[0].msg)
        if ok and message ~= "" then return message end
    end
    return fallback
end

local function inflateGzip(read_chunk, write_chunk, max_output_bytes)
    max_output_bytes = tonumber(max_output_bytes)
    if not max_output_bytes or max_output_bytes < 1 then
        return nil, "invalid decompressed size limit"
    end

    local loaded, load_error = loadBindings()
    if not loaded then return nil, load_error end
    local ffi, library = loaded.ffi, loaded.library
    local stream = ffi.new("gota_z_stream[1]")
    local init_result = library.inflateInit2_(
        stream,
        GZIP_WINDOW_BITS,
        library.zlibVersion(),
        ffi.sizeof(stream[0])
    )
    if init_result ~= Z_OK then
        return nil, "zlib initialization failed (" .. tostring(init_result) .. ")"
    end

    local output_buffer = ffi.new("uint8_t[?]", OUTPUT_CHUNK_BYTES)
    local input_buffer
    local input_finished = false
    local total_output = 0

    local function finish(result, err, limit_exceeded)
        pcall(library.inflateEnd, stream)
        return result, err, limit_exceeded, total_output
    end

    while true do
        if stream[0].avail_in == 0 and not input_finished then
            local chunk, read_error = read_chunk()
            if chunk == nil then
                if read_error then return finish(nil, tostring(read_error)) end
                input_finished = true
            elseif type(chunk) ~= "string" then
                return finish(nil, "gzip input source returned non-string data")
            elseif #chunk == 0 then
                input_finished = true
            else
                input_buffer = ffi.new("uint8_t[?]", #chunk)
                ffi.copy(input_buffer, chunk, #chunk)
                stream[0].next_in = input_buffer
                stream[0].avail_in = #chunk
            end
        end

        local input_before = tonumber(stream[0].avail_in)
        stream[0].next_out = output_buffer
        stream[0].avail_out = OUTPUT_CHUNK_BYTES
        local inflate_result = library.inflate(stream, Z_NO_FLUSH)
        local produced = OUTPUT_CHUNK_BYTES - tonumber(stream[0].avail_out)
        local consumed = input_before - tonumber(stream[0].avail_in)

        if produced > 0 then
            if total_output + produced > max_output_bytes then
                return finish(nil, "decompressed response exceeds the configured size limit", true)
            end
            local output = ffi.string(output_buffer, produced)
            local write_ok, write_error = write_chunk(output)
            if not write_ok then
                return finish(nil, tostring(write_error or "could not write decompressed data"))
            end
            total_output = total_output + produced
        end

        if inflate_result == Z_STREAM_END then
            return finish(true)
        end
        if inflate_result ~= Z_OK and inflate_result ~= Z_BUF_ERROR then
            return finish(nil, streamMessage(ffi, stream,
                "invalid gzip stream (zlib " .. tostring(inflate_result) .. ")"))
        end
        if input_finished and stream[0].avail_in == 0 and produced == 0 then
            return finish(nil, "truncated gzip stream")
        end
        if consumed == 0 and produced == 0 and stream[0].avail_in > 0 then
            return finish(nil, "gzip decoder made no progress")
        end
    end
end

function Compression.inflateGzipString(compressed, max_output_bytes)
    if type(compressed) ~= "string" or compressed == "" then
        return nil, "gzip response is empty"
    end

    local read = false
    local output = {}
    local ok, err, limit_exceeded = inflateGzip(function()
        if read then return nil end
        read = true
        return compressed
    end, function(chunk)
        output[#output + 1] = chunk
        return true
    end, max_output_bytes)

    if not ok then return nil, err, limit_exceeded end
    return table.concat(output), nil, false
end

function Compression.inflateGzipFile(source_path, destination_path, max_output_bytes)
    if type(source_path) ~= "string" or type(destination_path) ~= "string" or
       source_path == "" or destination_path == "" or source_path == destination_path then
        return nil, "invalid gzip file path"
    end

    local source, source_error = io.open(source_path, "rb")
    if not source then return nil, "could not open gzip response: " .. tostring(source_error) end
    os.remove(destination_path)
    local destination, destination_error = io.open(destination_path, "wb")
    if not destination then
        source:close()
        return nil, "could not create decompressed file: " .. tostring(destination_error)
    end

    local ok, err, limit_exceeded, output_size = inflateGzip(function()
        local read_ok, chunk = pcall(source.read, source, OUTPUT_CHUNK_BYTES)
        if not read_ok then return nil, chunk end
        return chunk
    end, function(chunk)
        local write_ok, write_result, write_error = pcall(destination.write, destination, chunk)
        if not write_ok then return nil, write_result end
        if not write_result then return nil, write_error end
        return true
    end, max_output_bytes)

    local source_close_ok, source_close_error = pcall(source.close, source)
    local destination_close_ok, destination_close_result, destination_close_error =
        pcall(destination.close, destination)
    if not source_close_ok and ok then
        ok, err = nil, tostring(source_close_error)
    end
    if (not destination_close_ok or not destination_close_result) and ok then
        ok = nil
        err = tostring(destination_close_ok and destination_close_error or destination_close_result)
    end

    if not ok then
        os.remove(destination_path)
        return nil, err, limit_exceeded
    end
    return destination_path, nil, false, output_size
end

return Compression
