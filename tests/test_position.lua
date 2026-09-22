local ffi=require('ffi')
local P=assert(loadfile(ROOT..'/src/position.lua'))()
local blocks={}
local function alloc(n)local b=ffi.new('uint8_t[?]',n);blocks[#blocks+1]={b,n};return tonumber(ffi.cast('uintptr_t',b))end
local function put(a,b)ffi.copy(ffi.cast('void *',a),b,#b)end
local function u(a,v)put(a,ffi.string(ffi.new('uint32_t[1]',v),4))end
local function ptr(a,v)put(a,ffi.string(ffi.new('uint64_t[1]',v),8))end
local exe=alloc(0x1a14100);local units=alloc(256);ptr(exe+0x1a140f0,units)
local slots,gen,object,vtable,code,matrix=alloc(16),alloc(2),alloc(256),alloc(256),alloc(5),alloc(64)
ptr(units+0x88,slots);ptr(units+0xa0,gen);u(units+0x98,2)
ptr(slots+8,object);put(gen+1,string.char(2));local unit=2*0x400000+1
u(object+8,unit);u(object+0x70,1);ptr(object,vtable);ptr(vtable+0xe8,code)
put(code,'\x48\x8d\x41\x60\xc3');ptr(object+0x88,matrix)
put(matrix+48,ffi.string(ffi.new('float[3]',{12,34,56}),12))
local api={read=function(a,n)
    for _,b in ipairs(blocks)do local start=tonumber(ffi.cast('uintptr_t',b[1]));if a>=start and a+n<=start+b[2]then return ffi.string(ffi.cast('void *',a),n)end end
end,pointer=function(b)local p=ffi.new('uint64_t[1]');ffi.copy(p,b,8);local n=tonumber(p[0]);return n~=0 and n or nil end}
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
test('guarded root pose reads translation without calling native code',function()
    local p=P.read(api,exe,unit);assert(p[1]==12 and p[2]==34 and p[3]==56)
end)
test('recycled unit generation rejects stale pose',function()
    put(gen+1,string.char(3));assert(not P.read(api,exe,unit));put(gen+1,string.char(2))
end)
test('unsupported pose layout disables distance only',function()
    put(code,'wrong');assert(not P.read(api,exe,unit));put(code,'\x48\x8d\x41\x60\xc3')
end)
test('invalid pose translation is not treated as nearest',function()
    put(matrix+48,ffi.string(ffi.new('float[1]',0/0),4));assert(not P.read(api,exe,unit))
    put(matrix+48,ffi.string(ffi.new('float[1]',12),4))
end)
test('unit replaced during pose read is rejected',function()
    local read=api.read
    api.read=function(a,n)local b=read(a,n);if a==matrix then u(object+8,unit+1)end;return b end
    assert(not P.read(api,exe,unit));api.read=read;u(object+8,unit)
end)
test('missing unit and missing root do not abort the controller',function()
    assert(not P.read(api,exe,0));ptr(exe+0x1a140f0,0);assert(not P.read(api,exe,unit));ptr(exe+0x1a140f0,units)
end)
test('new layout reads the relocated unit root without using the old slot',function()
    api.layout=assert(loadfile(ROOT..'/src/layout.lua'))().profiles[1]
    ptr(exe+0x1a140f0,0);ptr(exe+0x1a100f0,units)
    local p=P.read(api,exe,unit);assert(p and p[1]==12 and p[2]==34 and p[3]==56)
    ptr(exe+0x1a100f0,0);api.layout=nil;ptr(exe+0x1a140f0,units)
end)
return tostring(count)..' position tests passed'
