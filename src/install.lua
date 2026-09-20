return function(create_api,snapshot,policy,leases,controller,build,hud)
    if rawget(_G,'RoverFireSpread') then return end
    local state={mode=build.enabled and 'experimental' or 'diagnostic',status='starting',hud_enabled=build.show_hud~=false}
    rawset(_G,'RoverFireSpread',state)
    local api,control,last_log,game,surface
    local function report(force)
        local now=api and api.time() or 0
        if not force and last_log and now-last_log<2 then return end
        last_log=now
        pcall(function()
            local dir=os.getenv('LOCALAPPDATA');if not dir then return end
            local f=io.open(dir..'/RoverFireSpread.log','w');if not f then return end
            f:write('Rover Fire Spread prototype 0.7.4\nbuild_id=experimental-0.7.4\nmode='..state.mode..'\nstatus='..tostring(state.status)..'\n')
            f:write('process_id='..tostring(api and api.pid and api.pid() or 0)..'\n')
            f:write('hud_enabled='..tostring(state.hud_enabled)..'\n')
            for _,key in ipairs({'compatibility','game_sha256','exe_sha256','hud_status','hud_error'})do
                f:write(key..'='..tostring(state[key] or 'pending')..'\n')
            end
            if control then
                for _,key in ipairs({'samples','requests','rotations','would_rotate','id','target','node','candidates','eligible',
                    'history_count','history_limit','history_seconds','distance_available','planned_target','planned_distance','ranking','selection_basis',
                    'decision','target_synced','active_request','active_ranking','active_target','active_reason','no_attack_elapsed','lock_elapsed','lock_limit',
                    'last_request_at','last_request_finished_at','last_request_ranking','last_request_target','last_request_reason','active_basis','last_request_basis','cleanup_pending'})do
                    local value=control[key];if value==nil then value=0 end
                    f:write(key..'='..tostring(value)..'\n')
                end
            end
            f:close()
        end)
    end
    report(true)
    local ok,why=pcall(function()
        api=create_api();game=assert(api.module('game.dll'));local exe=assert(api.module(nil))
        state.game_sha256=api.module_hash(game);state.exe_sha256=api.module_hash(exe)
        assert(type(state.game_sha256)=='string' and #state.game_sha256>0,'Game hash unavailable')
        assert(type(state.exe_sha256)=='string' and #state.exe_sha256>0,'Executable hash unavailable')
        state.compatibility=state.game_sha256==build.game_sha and state.exe_sha256==build.exe_sha
            and 'baseline_hash_match' or 'unverified_build_attempt'
        -- A whole-file hash change is advisory. Signatures and all per-write
        -- identity/layout checks remain mandatory on an unverified build.
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
    if not ok then state.stopped=true;state.status=tostring(why);state.hud_status='initialization_failed';report(true);return end
    local original,previous_shutdown=update,shutdown
    local stopped=false
    local function check()
        if stopped then return end
        local called,accepted,reason=pcall(control.poll)
        state.status=control.status
        if not called or not accepted then
            stopped=true;state.stopped=true;local clean,restored=pcall(control.stop)
            state.status=tostring(called and reason or accepted)..((clean and restored) and '' or '; restoration_requires_retry')
        end
        report(stopped)
    end
    local function after(called,...)
        if not called then
            stopped=true;state.stopped=true;pcall(control.stop);if surface then pcall(function()surface:clear()end)end
            state.status='original_update_failed';report(true);error((...),0)
        end
        check()
        if hud and build.show_hud~=false then
            local drawn,err=pcall(function()
                if not surface then surface=hud.new(rawget(_G,'stingray'),api,game,state.game_sha256==build.game_sha)end
                surface:frame(state,control)
            end)
            if not drawn then state.hud_status='unavailable';state.hud_error=tostring(err)end
        else state.hud_status='disabled' end
        report(false);return ...
    end
    update=function(...)
        if stopped then pcall(control.stop) else check() end
        return after(pcall(original,...))
    end
    shutdown=function(...)
        stopped=true;state.stopped=true;local ok,restored=pcall(control.stop)
        if surface then pcall(function()surface:clear()end)end
        state.hud_status='closed'
        state.status=ok and restored and 'stopped' or 'restoration_incomplete';report(true)
        if previous_shutdown then return previous_shutdown(...) end
    end
    state.status='waiting_for_mission';report(true)
end
