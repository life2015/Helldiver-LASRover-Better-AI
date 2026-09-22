-- A shared-loader start alone does not prove Rover initialization succeeded.
return function(run_shared,run_rover)
    local stages={}
    local function report(stage)
        stages[#stages+1]=stage
        pcall(function()
            local dir=os.getenv('LOCALAPPDATA');if not dir then return end
            local f=io.open(dir..'/RoverFireSpread-startup.log','w');if not f then return end
            f:write('build_id=experimental-0.7.10\n'..table.concat(stages,'\n')..'\n');f:close()
        end)
    end
    report('bridge_entered')
    local shared_ok,shared_why=pcall(run_shared)
    report(shared_ok and 'shared_loader_returned' or 'shared_loader_failed='..tostring(shared_why))
    local ok,why=pcall(run_rover)
    local state=rawget(_G,'RoverFireSpread')
    if not ok then report('rover_chunk_failed='..tostring(why))
    elseif type(state)~='table' then report('rover_state_missing')
    else report('rover_state='..tostring(state.status)..';mode='..tostring(state.mode)) end
end
