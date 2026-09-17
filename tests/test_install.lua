local install=assert(loadfile(ROOT..'/src/install.lua'))()
local real_io=io
io={open=function()return nil end} -- isolate every lifecycle log from real files
local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
local function fixture(original,options)
    options=options or {};RoverFireSpread=nil;update=original;shutdown=function()return 'old shutdown'end
    local polls,stops=0,0
    local api={time=function()return 0 end,module=function(name)return name or 'exe'end,module_hash=function()return 'hash'end}
    local oldopen=io.open;io.open=function()return nil end
    install(function()return api end,nil,nil,nil,function()
        return {status='observing',poll=function()polls=polls+1;if options.fail then error('poll error')end;return true end,
            stop=function()stops=stops+1;return true end}
    end,{enabled=false,game_sha=options.hash or 'hash',exe_sha='hash',signatures={}})
    io.open=oldopen
    return api,function()return polls,stops end
end
test('update wrapper preserves arguments and nil-containing returns',function()
    fixture(function(a,b)assert(a==4 and b==9);return 2,nil,3 end)
    local a,b,c=update(4,9);assert(a==2 and b==nil and c==3)
end)
test('diagnostic installation prohibits writes',function()
    local api=fixture(function()end);assert(not pcall(api.write,1,'x'))
end)
test('poll failure restores and still calls original update',function()
    local called=0;local _,counts=fixture(function()called=called+1 end,{fail=true})
    update();local polls,stops=counts();assert(called==1 and polls==1 and stops>=1)
end)
test('original update errors propagate after cleanup',function()
    local _,counts=fixture(function()error('original error')end)
    local ok,why=pcall(update);local _,stops=counts();assert(not ok and why:find('original error') and stops==1)
end)
test('unsupported game never wraps update',function()
    local original=function()return 'untouched'end;fixture(original,{hash='wrong'})
    assert(update==original and RoverFireSpread.status:find('Unsupported'))
end)
test('shutdown restores then preserves previous callback',function()
    local _,counts=fixture(function()end);assert(shutdown()=='old shutdown')
    local _,stops=counts();assert(stops==1)
end)
io=real_io
return tostring(passed)..' installation tests passed'
