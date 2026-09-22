local install=assert(loadfile(ROOT..'/src/install.lua'))()
local real_io=io
io={open=function()return nil end} -- isolate every lifecycle log from real files
local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
local function fixture(original,options)
    options=options or {};RoverFireSpread=nil;update=original;shutdown=function()return 'old shutdown'end
    local polls,stops=0,0
    local api={time=function()return 0 end,module=function(name)return name and 100 or 200 end,
        module_hash=function(module)return module==100 and (options.game_actual or 'hash') or (options.exe_actual or 'hash')end,
        read=options.read or function()return options.signature_actual end}
    local oldopen=io.open;io.open=function()return nil end
    install(function()return api end,nil,nil,nil,function()
        return {status='observing',poll=function()polls=polls+1;if options.fail then error('poll error')end;return true end,
            stop=function()stops=stops+1;return true end}
    end,{enabled=false,game_sha='hash',exe_sha='hash',signatures=options.signatures or {},layouts=options.layouts,show_hud=options.show_hud},options.hud)
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
test('changed game hash attempts initialization and records actual hashes',function()
    local original=function()return 'running'end;local _,counts=fixture(original,{game_actual='new_game',signatures={{0,'aa'}},signature_actual='\xaa'})
    assert(update~=original and update()=='running' and counts()>0)
    assert(RoverFireSpread.compatibility=='unverified_build_attempt' and RoverFireSpread.game_sha256=='new_game')
end)
test('changed executable hash also allows an unverified attempt',function()
    local original=function()end;fixture(original,{exe_actual='new_exe'})
    assert(update~=original and RoverFireSpread.compatibility=='unverified_build_attempt' and RoverFireSpread.exe_sha256=='new_exe')
end)
test('matching hashes identify the baseline without claiming gameplay success',function()
    fixture(function()end)
    assert(RoverFireSpread.compatibility=='baseline_hash_match' and RoverFireSpread.status=='waiting_for_mission')
end)
test('signature mismatch still prevents initialization on an unverified build',function()
    local original=function()end;fixture(original,{game_actual='new_game',signatures={{0,'aa'}},signature_actual='\xbb'})
    assert(update==original and RoverFireSpread.status:find('Runtime signature mismatch'))
end)
test('unreadable signature still prevents initialization on the baseline',function()
    local original=function()end;fixture(original,{signatures={{0,'aa'}}})
    assert(update==original and RoverFireSpread.status:find('Runtime signature mismatch'))
end)
test('shutdown restores then preserves previous callback',function()
    local _,counts=fixture(function()end);assert(shutdown()=='old shutdown')
    local _,stops=counts();assert(stops==1)
end)
test('HUD exceptions do not stop targeting or alter callback return values',function()
    local _,counts=fixture(function()return 7,nil,9 end,{hud={new=function()return {frame=function()error('draw failed')end}end}})
    local a,b,c=update();local polls,stops=counts()
    assert(a==7 and b==nil and c==9 and polls==2 and stops==0)
    assert(RoverFireSpread.hud_status=='unavailable' and not RoverFireSpread.stopped)
end)
test('HUD survives controller failure to show stopped and clears at shutdown',function()
    local seen,cleared=false,false
    fixture(function()end,{fail=true,hud={new=function()return {
        frame=function(_,state)seen=state.stopped end,clear=function()cleared=true end}end}})
    update();assert(seen);shutdown();assert(cleared)
end)
test('HUD can be disabled without changing the update chain',function()
    local _,counts=fixture(function()return 'ok'end,{show_hud=false,hud={new=function()error('must not create')end}})
    assert(update()=='ok' and RoverFireSpread.hud_status=='disabled')
    assert(counts()>0 and RoverFireSpread.hud_enabled==false)
end)
local profile=assert(loadfile(ROOT..'/src/layout.lua'))().profiles[1]
local function profile_read(a,n)
    for _,sig in ipairs(profile.signatures)do
        if a==100+sig[1] then return (sig[2]:gsub('..',function(x)return string.char(tonumber(x,16))end)) end
    end
end
test('matching new module pair selects its own layout and validates all signatures',function()
    local api=fixture(function()end,{game_actual=profile.game_sha,exe_actual=profile.exe_sha,
        layouts={profile},read=profile_read,signatures={{0,'ff'}}})
    assert(api.layout==profile and RoverFireSpread.layout_id=='25327279' and not RoverFireSpread.stopped)
    assert(RoverFireSpread.compatibility=='verified_layout_hash_match')
end)
test('each new-layout signature remains mandatory',function()
    for _,bad in ipairs(profile.signatures)do
        local original=function()end
        fixture(original,{game_actual=profile.game_sha,exe_actual=profile.exe_sha,layouts={profile},
            read=function(a,n)if a==100+bad[1] then return nil end;return profile_read(a,n)end})
        assert(update==original and RoverFireSpread.stopped and RoverFireSpread.status:find('signature mismatch'))
    end
end)
test('one matching module does not select a mixed-version layout',function()
    for _,pair in ipairs({{profile.game_sha,'different'},{'different',profile.exe_sha}})do
        local api=fixture(function()end,{game_actual=pair[1],exe_actual=pair[2],layouts={profile}})
        assert(not api.layout and RoverFireSpread.layout_id=='24826606')
    end
end)
test('HUD receives verified font layout after new profile selection',function()
    local seen=false
    fixture(function()end,{game_actual=profile.game_sha,exe_actual=profile.exe_sha,layouts={profile},read=profile_read,
        hud={new=function(_,api,_,verified)seen=verified and api.layout==profile;return {frame=function()end}end}})
    update();assert(seen)
end)
io=real_io
return tostring(passed)..' installation tests passed'
