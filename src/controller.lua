return function(api,snapshot,policy,leases,game,enabled)
    local M={requests=0,samples=0,rotations=0,candidates=0,status='starting',policy={}}
    local pending,last_poll
    local function restore()
        if not pending then return true end
        local ok=leases.restore(api,pending)
        if ok then pending=nil end
        return ok
    end
    function M.stop()
        M.stopped=true
        return restore()
    end
    function M.poll()
        local now=api.time()
        if M.stopped then return restore() end
        if last_poll and now>=last_poll and now-last_poll<0.05 then return true end
        last_poll=now
        local s,reason=snapshot.read(api,game)
        M.samples=M.samples+1;M.status=reason
        if pending then
            local consumed=api.read(pending.deadline_address,8)
            if not s or s.key~=pending.key or s.node~=7 or s.target~=pending.target or now>=pending.until_time
                or consumed~=pending.deadline_after then
                if s and s.key==pending.key and s.target~=0 and s.target~=pending.target then M.rotations=M.rotations+1 end
                if not restore() then return false,'restore_pending' end
                -- Resample after restoration; before-values may have changed.
                return true
            end
            return true
        end
        if not s then M.policy={};M.candidates=0;return true end
        M.id=s.id;M.target=s.target;M.node=s.node;M.candidates=#s.candidates
        M.eligible=0;for _,c in ipairs(s.candidates)do if c.eligible then M.eligible=M.eligible+1 end end
        local plan=policy.plan(M.policy,s,now)
        if not plan then return true end
        if not enabled then M.status='diagnostic_would_rotate';M.would_rotate=(M.would_rotate or 0)+1;policy.committed(M.policy,plan,now);return true end
        if snapshot.matches(api,s.guards)~=true or snapshot.matches(api,s.transition)~=true then return true end
        if s.deadline_value-s.now_native>1000000 then return false,'unexpected_selection_deadline' end
        local writes={}
        for _,c in ipairs(s.candidates) do
            if plan.blocked[c.id] and c.mask~=string.rep('\0',4) then
                writes[#writes+1]={address=c.address,before=c.mask,after=string.rep('\0',4),valid=c.valid}
            end
        end
        if #writes==0 then return true end
        local due=snapshot.tickword(s.now_native)
        writes[#writes+1]={address=s.deadline_address,before=s.deadline,after=due,valid=s.valid}
        local acquired,why=leases.acquire(api,writes)
        if not acquired then M.status=why;return true end
        pending=acquired;pending.key=s.key;pending.target=plan.target;pending.until_time=plan.until_time
        pending.deadline_address=s.deadline_address;pending.deadline_after=due
        if why then restore();return false,why end
        M.requests=M.requests+1;policy.committed(M.policy,plan,now);M.status='rotation_requested'
        return true
    end
    return M
end
