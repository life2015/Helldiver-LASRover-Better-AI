-- Compare-and-restore leases over existing private writable data only.
local M={}
function M.restore(api,lease)
    local ok=true
    for i=#lease.writes,1,-1 do
        local w=lease.writes[i]
        if not w.done then
            local valid=w.valid()
            if valid==nil then ok=false
            elseif not valid then w.done=true
            else
                local current=api.read(w.address,#w.after)
                if not current then ok=false
                elseif current==w.after then
                    if api.write(w.address,w.before) and api.read(w.address,#w.before)==w.before then w.done=true else ok=false end
                elseif current==w.before then w.done=true
                elseif not w.complete then
                    local ours=false
                    for cut=1,#w.after-1 do
                        if current==w.after:sub(1,cut)..w.before:sub(cut+1) then ours=true;break end
                    end
                    if ours then
                        if api.write(w.address,w.before) and api.read(w.address,#w.before)==w.before then w.done=true else ok=false end
                    else w.done=true end
                else w.done=true end -- an engine/other-mod update takes precedence
            end
        end
    end
    return ok
end
function M.acquire(api,writes)
    local lease={writes={}}
    -- Validate the complete transaction before the first write.
    for _,w in ipairs(writes) do
        if not w.valid() or api.read(w.address,#w.before)~=w.before or not api.writable_data(w.address,#w.before) then
            return nil,'precondition_changed'
        end
    end
    for _,w in ipairs(writes) do
        lease.writes[#lease.writes+1]=w
        if not w.valid() or not api.write(w.address,w.after) or api.read(w.address,#w.after)~=w.after then
            return lease,'write_failed'
        end
        w.complete=true
    end
    return lease
end
return M
