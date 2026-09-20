return function(api,snapshot,policy,leases,game,enabled)
    local M={requests=0,samples=0,rotations=0,candidates=0,status='starting',policy={},
        history_limit=policy.history_limit,history_seconds=policy.history_seconds,lock_limit=policy.max_lock_seconds,decision='waiting',active_request=false}
    local pending,last_poll
    local function restore()
        if not pending then return true end
        local ok=leases.restore(api,pending)
        if ok then pending=nil;M.active_request=false;M.active_ranking=nil;M.active_target=nil;M.active_reason=nil;M.active_basis=nil end
        return ok
    end
    function M.stop()
        M.stopped=true;M.decision='stopped';M.cleanup_pending=true;M.target_synced=false
        local restored=restore();M.cleanup_pending=not restored
        return restored
    end
    function M.poll()
        local now=api.time()
        if M.stopped then return restore() end
        if last_poll and now>=last_poll and now-last_poll<0.05 then return true end
        last_poll=now
        local s,reason=snapshot.read(api,game)
        M.samples=M.samples+1;M.status=reason
        M.current_key=s and s.key or nil
        M.decision=reason or 'waiting';M.planned_target=0;M.planned_distance=-1;M.ranking=nil;M.selection_basis=nil
        if s then
            M.id=s.id;M.target=s.target;M.target_synced=s.synced==true;M.node=s.node;M.candidates=#s.candidates
            M.distance_available=s.distance_available==true
            M.eligible=0;for _,c in ipairs(s.candidates)do if c.eligible then M.eligible=M.eligible+1 end end
        else M.id=0;M.target=0;M.target_synced=false;M.node=0;M.candidates=0;M.eligible=0 end
        if not s then
            if reason=='waiting_for_runtime' or reason=='waiting_for_consistent_snapshot' then policy.pause(M.policy,now)
            else M.policy={} end
            M.history_count=M.policy.history_count or 0;M.distance_available=false;M.no_attack_elapsed=0;M.lock_elapsed=0
        end
        if pending then
            local consumed=api.read(pending.deadline_address,8)
            if not s or s.key~=pending.key or s.node~=pending.node or s.target~=pending.target or now>=pending.until_time
                or consumed~=pending.deadline_after then
                if s and s.key==pending.key and s.target~=0 and s.target~=pending.target then M.rotations=M.rotations+1 end
                if not restore() then M.decision='restore_pending';return false,'restore_pending' end
                M.last_request_finished_at=now -- HUD-only hold starts after actual restoration.
                M.decision=s and 'request_finished' or reason
                -- Resample after restoration; before-values may have changed.
                return true
            end
            M.decision='request_active'
            return true
        end
        if not s then M.candidates=0;return true end
        local plan,decision=policy.plan(M.policy,s,now)
        M.decision=decision or 'plan_ready'
        M.no_attack_elapsed=M.policy.idle_elapsed or 0
        M.lock_elapsed=M.policy.lock_elapsed or 0
        M.history_count=M.policy.history_count or 0
        if not plan then return true end
        M.planned_target=plan.selected or 0;M.planned_distance=plan.distance2 and math.sqrt(plan.distance2) or -1;M.ranking=plan.ranking
        M.selection_basis=plan.selection_basis
        if not enabled then M.decision='diagnostic';M.status='diagnostic_would_rotate';M.would_rotate=(M.would_rotate or 0)+1;policy.committed(M.policy,plan,now);return true end
        if snapshot.matches(api,s.guards)~=true or snapshot.matches(api,s.transition)~=true then M.decision='precondition_changed';return true end
        if s.deadline_value-s.now_native>1000000 then return false,'unexpected_selection_deadline' end
        local writes={}
        for _,c in ipairs(s.candidates) do
            if plan.blocked[c.id] and c.mask~=string.rep('\0',4) then
                writes[#writes+1]={address=c.address,before=c.mask,after=string.rep('\0',4),valid=c.valid}
            end
        end
        if #writes==0 then M.decision='no_writes';return true end
        local due=snapshot.tickword(s.now_native)
        writes[#writes+1]={address=s.deadline_address,before=s.deadline,after=due,valid=s.valid}
        local acquired,why=leases.acquire(api,writes)
        if not acquired then M.status=why;M.decision=why;return true end
        pending=acquired;pending.key=s.key;pending.target=plan.target;pending.node=plan.node;pending.until_time=plan.until_time
        pending.deadline_address=s.deadline_address;pending.deadline_after=due
        M.active_request=true;M.active_ranking=plan.ranking;M.active_target=plan.selected or 0;M.active_reason=plan.reason
        M.active_basis=plan.selection_basis
        if why then restore();return false,why end
        M.requests=M.requests+1;policy.committed(M.policy,plan,now);M.status='rotation_requested';M.decision='request_active'
        M.last_request_at=now;M.last_request_ranking=plan.ranking;M.last_request_target=plan.selected or 0
        M.last_request_finished_at=nil
        M.last_request_reason=plan.reason
        M.last_request_basis=plan.selection_basis
        M.last_request_key=s.key
        return true
    end
    return M
end
