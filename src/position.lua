-- Read UnitApi.world_pose(node 0) data using the guarded layout also used by
-- CowboyBingus/SentryAimRetention. No native game function calls.
local ffi=require('ffi')
local M={}
local function uint(b)local x=ffi.new('uint32_t[1]');ffi.copy(x,b,4);return tonumber(x[0])end
function M.read(api,exe,unit)
    if not exe or not unit or unit==0 then return nil end
    local guards={}
    local function read(a,n,guard)
        local b=api.read(a,n);if not b or #b~=n then error('position unavailable',0)end
        if guard then guards[#guards+1]={a,b}end;return b
    end
    local function ptr(a)return assert(api.pointer(read(a,8,true)))end
    local ok,result=pcall(function()
        local units=ptr(exe+0x1a140f0);local index=unit%0x400000
        assert(index<uint(read(units+0x98,4)))
        local generations=ptr(units+0xa0)
        assert(read(generations+index,1,true)==string.char(math.floor(unit/0x400000)%256))
        local object=ptr(ptr(units+0x88)+8*index)
        assert(uint(read(object+8,4,true))==unit and uint(read(object+0x70,4))>0)
        assert(read(ptr(ptr(object)+0xe8),5)=='\x48\x8d\x41\x60\xc3')
        local matrix=read(ptr(object+0x88),64)
        local xyz={}
        for i=0,2 do
            local v=ffi.new('float[1]');ffi.copy(v,matrix:sub(49+i*4,52+i*4),4)
            xyz[i+1]=tonumber(v[0]);assert(xyz[i+1]==xyz[i+1] and math.abs(xyz[i+1])<1000000)
        end
        for _,g in ipairs(guards)do if read(g[1],#g[2])~=g[2] then return nil end end
        return xyz
    end)
    return ok and result or nil
end
return M
