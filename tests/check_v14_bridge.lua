-- Actual published v14 bytecode, with game modules stubbed and filesystem
-- creation denied. Runs in the independent build process, never in the game.
local ffi=require('ffi')
local function env(installed,broken)
    local loaded,logs,lookups={},{},{}
    local e=setmetatable({print=function()end,os={getenv=function()return 'mock'end},
        io={open=function(path)return {write=function(self,s)logs[path]=(logs[path]or '')..s end,close=function()end}end},
        stingray={Application={build=function()return 'release'end,can_get=function(kind,name)
            assert(kind=='lua');lookups[#lookups+1]=name;return installed
        end}}},{__index=_G})
    e._G=e;e.loaded=loaded;e.logs=logs;e.lookups=lookups
    e.update=function(a)return a,nil,3 end
    e.loadstring=function(bytes,name)local c,why=loadstring(bytes,name);if c then setfenv(c,e)end;return c,why end
    local mockffi=setmetatable({load=function(name,...)
        local lib=ffi.load(name,...)
        if name=='kernel32' then return setmetatable({CreateDirectoryA=function()return 0 end,
            GetLastError=function()return 5 end},{__index=lib})end
        return lib
    end},{__index=ffi})
    e.require=function(name)
        if name=='ffi' then return mockffi end
        if name:sub(1,11)=='core/wwise/' then return {}end
        if name:sub(1,5)=='mods/' then
            assert(installed,'missing modules must not reach require')
            loaded[name]=(loaded[name]or 0)+1
            if name==broken then error('mock optional module failure')end
            return {}
        end
        return require(name)
    end
    return e
end
local function run(path,e)setfenv(assert(loadfile(path)),e)()end
for _,installed in ipairs({false,true})do
    local a,b=env(installed),env(installed)
    run(ORIGINAL,a);run(BRIDGE,b)
    local count=0
    for name,callback in pairs(a.WwiseFlowCallbacks)do
        assert(string.dump(callback,true)==string.dump(b.WwiseFlowCallbacks[name],true));count=count+1
    end
    assert(count>25)
    assert(b.CowboyBingusModLoader.version==a.CowboyBingusModLoader.version)
    assert(b.CowboyBingusModLoader.api==1 and type(b.CowboyBingusModLoader.open_log)=='function')
    assert(#a.lookups==#b.lookups and #a.lookups>=14)
    for i,name in ipairs(a.lookups)do
        assert(b.lookups[i]==name and a.loaded[name]==b.loaded[name])
        assert(a.CowboyBingusModLoader.modules[name]==b.CowboyBingusModLoader.modules[name])
    end
    if installed then assert(b.loaded['mods/cowboybingus/armory_preview_cache']==1)end
    assert(b.RoverFireSpread and b.RoverFireSpread.mode=='experimental')
    assert(b.RoverFireSpread.hud_enabled==EXPECT_HUD,'compiled HUD variant mismatch')
    local log=assert(b.logs['mock/RoverFireSpread-startup.log'])
    assert(log:find(EXPECT_BUILD,1,true) and log:find('shared_loader_release=v14',1,true))
    assert(log:find('shared_loader_returned',1,true) and log:find('rover_state=',1,true))
    local x,y,z=b.update(7);assert(x==7 and y==nil and z==3)
    local state=b.RoverFireSpread;run(BRIDGE,b);assert(state==b.RoverFireSpread)
    for name,n in pairs(b.loaded)do assert(n==1,'duplicate optional module: '..name)end
end
local e=env(true,'mods/cowboybingus/vanilla_plus_megapack')
run(BRIDGE,e)
assert(e.CowboyBingusModLoader.modules['mods/cowboybingus/vanilla_plus_megapack']:find('load failed',1,true))
assert(e.loaded['mods/cowboybingus/armory_preview_cache']==1 and e.RoverFireSpread)
-- A pre-existing v14 coordinator is respected, without loading its modules twice.
local b=env(true);run(ORIGINAL,b);local loader=b.CowboyBingusModLoader
run(BRIDGE,b);assert(b.CowboyBingusModLoader==loader and b.RoverFireSpread)
for _,n in pairs(b.loaded)do assert(n==1)end
return 'PASS published v14: preserved callbacks and module roster, missing/failed modules, unwritable logs, Rover startup, update returns, duplicate guard, existing coordinator'
