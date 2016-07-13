-- Copyright (C) Yichun Zhang (agentzh)
--
-- This library is an approximate Lua port of the standard ngx_hotrate
-- module.


local ffi = require "ffi"
local math = require "math"


local ngx_shared = ngx.shared
local ngx_now = ngx.now
local setmetatable = setmetatable
local ffi_cast = ffi.cast
local ffi_str = ffi.string
local abs = math.abs
local tonumber = tonumber
local type = type
local assert = assert


-- TODO: we could avoid the tricky FFI cdata when lua_shared_dict supports
-- hash-typed values as in redis.
ffi.cdef[[
    struct lua_resty_hotrate_rec {
        unsigned             excess:31;
        unsigned             reached:1; /* reached threshold */
        uint64_t             last;  /* time in milliseconds */
        /* integer value, 1 corresponds to 0.001 r/s */
    };
]]
local const_rec_ptr_type = ffi.typeof("const struct lua_resty_hotrate_rec*")
local rec_size = ffi.sizeof("struct lua_resty_hotrate_rec")

-- we can share the cdata here since we only need it temporarily for
-- serialization inside the shared dict:
local rec_cdata = ffi.new("struct lua_resty_hotrate_rec")


local _M = {
    _VERSION = '0.01'
}


local mt = {
    __index = _M
}


function _M.new(dict_name, base, threshold, burst)
    local dict = ngx_shared[dict_name]
    if not dict then
        return nil, "shared dict not found"
    end

    assert(base > 0 and threshold >=0 and burst >= threshold )

    local self = {
        dict = dict,
        base = base * 1000,
        threshold = threshold * 1000,
        burst = burst * 1000,
    }

    return setmetatable(self, mt)
end


function _M.coming(self, key)
    local dict = self.dict
    local base = self.base
    local now = ngx_now() * 1000

    local excess, reached

    -- it's important to anchor the string value for the read-only pointer
    -- cdata:
    local v = dict:get(key)
    if v then
        if type(v) ~= "string" or #v ~= rec_size then
            return nil, "shdict abused by other users"
        end
        local rec = ffi_cast(const_rec_ptr_type, v)
        local elapsed = now - tonumber(rec.last)

        -- print("elapsed: ", elapsed, "ms")

        -- we do not handle changing rate values specifically. the excess value
        -- can get automatically adjusted by the following formula with new rate
        -- values rather quickly anyway.
        excess = tonumber(rec.excess) - base * abs(elapsed) / 1000 + 1000

        if excess < 0 then
            -- ngx.log(ngx.WARN, "excess: ", excess / 1000)
            excess = 0
        end

        if excess > self.burst then
            excess = self.burst
        end

        reached = tonumber(rec.reached)
        if excess >= self.threshold and reached == 0 then
            reached = 1

        elseif excess <= 0 and reached == 1 then
            reached = 0
        end

    else
        excess = 0
        reached = 0
    end

    rec_cdata.excess = excess
    rec_cdata.last = now
    rec_cdata.reached = reached

    dict:set(key, ffi_str(rec_cdata, rec_size))

    return reached == 1
end


function _M.set_base(self, base)
    self.base = base * 1000
end


function _M.set_threshold(self, threshold)
    self.threshold = threshold * 1000
end


function _M.set_burst(self, burst)
    self.burst = burst * 1000
end


return _M
