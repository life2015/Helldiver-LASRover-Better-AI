return function(create_api,snapshot,policy,leases,controller,build)
    if rawget(_G,'RoverFireSpread') then return end
    local state={mode=build.enabled and 'experimental' or 'diagnostic',status='starting'}
    rawset(_G,'RoverFireSpread',state)
    local api,control,last_log
    local function report(force)
        local now=api and api.time() or 0
        if not force and last_log and now-last_log<2 then return end
        last_log=now
        pcall(function()
            local dir=os.getenv('LOCALAPPDATA');if not dir then return end
            local f=io.open(dir..'/RoverFireSpread.log','w');if not f then return end
            f:write('Rover Fire Spread prototype 0.3\nbuild_id=experimental-0.3\nmode='..state.mode..'\nstatus='..tostring(state.status)..'\n')
            f:write('process_id='..tostring(api and api.pid and api.pid() or 0)..'\n')
            if control then
                for _,key in ipairs({'samples','requests','rotations','would_rotate','id','target','node','candidates','eligible'})do
                    f:write(key..'='..tostring(control[key] or 0)..'\n')
                end
            end
            f:close()
        end)
    end
    report(true)
    local ok,why=pcall(function()
        api=create_api();local game=assert(api.module('game.dll'));local exe=assert(api.module(nil))
        assert(api.module_hash(game)==build.game_sha,'Unsupported game.dll')
        assert(api.module_hash(exe)==build.exe_sha,'Unsupported executable')
        for _,sig in ipairs(build.signatures)do
            local bytes=sig[2]:gsub('..',function(x)return string.char(tonumber(x,16))end)
            assert(api.read(game+sig[1],#bytes)==bytes,'Runtime signature mismatch')
        end
        assert(type(update)=='function','Game update unavailable')
        if not build.enabled then
            api.write=function()error('Diagnostic mode prohibits writes')end
        end
        control=controller(api,snapshot,policy,leases,game,build.enabled)
    end)
    if not ok then state.status=tostring(why);report(true);return end
    local original,previous_shutdown=update,shutdown
    local stopped=false
    local function check()
        if stopped then return end
        local called,accepted,reason=pcall(control.poll)
        state.status=control.status
        if not called or not accepted then
            stopped=true;local clean,restored=pcall(control.stop)
            state.status=tostring(called and reason or accepted)..((clean and restored) and '' or '; restoration_requires_retry')
        end
        report(stopped)
    end
    local function after(called,...)
        if not called then
            stopped=true;pcall(control.stop);state.status='original_update_failed';report(true);error((...),0)
        end
        check();return ...
    end
    update=function(...)
        if stopped then pcall(control.stop) else check() end
        return after(pcall(original,...))
    end
    shutdown=function(...)
        stopped=true;local ok,restored=pcall(control.stop)
        state.status=ok and restored and 'stopped' or 'restoration_incomplete';report(true)
        if previous_shutdown then return previous_shutdown(...) end
    end
    state.status='waiting_for_mission';report(true)
end
