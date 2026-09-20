-- Run the actual compiled entry. This test process has no game.dll and every
-- file write is intercepted; entry must still report its validation failure.
local original,bridge=ORIGINAL,BRIDGE
local function env()
    local logs={}
    local e=setmetatable({print=function()end,os={getenv=function()return 'mock'end},
        io={open=function(path)return {write=function(self,s)logs[path]=(logs[path]or '')..s end,close=function()end}end},
        stingray={Application={build=function()return 'release'end,can_get=function()return false end}}},{__index=_G})
    e._G=e;e.logs=logs
    e.loadstring=function(bytes,name)local c,why=loadstring(bytes,name);if c then setfenv(c,e)end;return c,why end
    e.update=function(a)return a,nil,3 end
    e.require=function(name)
        if name:sub(1,11)=='core/wwise/' then return {}end
        return require(name)
    end
    return e
end
local a,b=env(),env()
setfenv(assert(loadfile(original)),a)();setfenv(assert(loadfile(bridge)),b)()
local count=0
for name,callback in pairs(a.WwiseFlowCallbacks)do
    assert(string.dump(callback,true)==string.dump(b.WwiseFlowCallbacks[name],true));count=count+1
end
assert(count>25 and b.CowboyBingusModLoader.api==1)
local x,y,z=b.update(7);assert(x==7 and y==nil and z==3)
assert(b.RoverFireSpread and b.RoverFireSpread.mode=='experimental')
if EXPECT_HUD~=nil then assert(b.RoverFireSpread.hud_enabled==EXPECT_HUD,'compiled HUD variant mismatch')end
local log=assert(b.logs['mock/RoverFireSpread-startup.log'])
assert(log:find('bridge_entered') and log:find('shared_loader_returned') and log:find('rover_state='))
assert(b.logs['mock/RoverFireSpread.log']:find('mode=experimental'))
local state=b.RoverFireSpread
setfenv(assert(loadfile(bridge)),b)();assert(b.RoverFireSpread==state)
return 'PASS actual compiled startup: callbacks, direct Rover entry, stage logs, duplicate guard'
