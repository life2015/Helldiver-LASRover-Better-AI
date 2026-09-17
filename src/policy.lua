-- No burn-state reads. Rotation is based on a short, approximate attack window.
local M={window=0.4,retry=0.15,max_gap=0.25,lease_seconds=0.25}
function M.plan(state,s,now)
    assert(type(now)=='number' and now==now,'invalid time')
    if state.key~=s.key then
        state.key=s.key;state.target=nil;state.elapsed=0;state.visited={};state.sequence=0;state.last=nil;state.retry_at=0
    end
    local dt=state.last and math.max(0,math.min(now-state.last,M.max_gap)) or 0
    if state.last and (now<state.last or now-state.last>M.max_gap) then state.elapsed=0;dt=0 end
    state.last=now
    if state.target~=s.target then state.target=s.target;state.elapsed=0;dt=0 end
    if s.node~=7 or not s.synced or not s.target or s.target==0 then state.elapsed=0;return nil end
    state.elapsed=state.elapsed+dt
    if state.elapsed<M.window or now<(state.retry_at or 0) then return nil end
    local eligible={}
    for _,c in ipairs(s.candidates or {}) do
        if c.eligible and c.id~=s.target then eligible[c.id]=true end
    end
    if not next(eligible) then return nil end -- a sole target keeps normal fire
    local allowed={};local unseen=false
    for id in pairs(eligible) do if not state.visited[id] then allowed[id]=true;unseen=true end end
    if not unseen then
        local oldest
        for id in pairs(eligible) do if not oldest or state.visited[id]<oldest then oldest=state.visited[id] end end
        for id in pairs(eligible) do if state.visited[id]==oldest then allowed[id]=true end end
    end
    local blocked={[s.target]=true}
    for _,c in ipairs(s.candidates or {}) do if c.eligible and not allowed[c.id] then blocked[c.id]=true end end
    return {blocked=blocked,allowed=allowed,target=s.target,until_time=now+M.lease_seconds}
end
function M.committed(state,plan,now)
    state.sequence=state.sequence+1;state.visited[plan.target]=state.sequence
    state.elapsed=0;state.retry_at=now+M.retry
    -- Keep state bounded during long missions.
    if state.sequence>4096 then state.visited={[plan.target]=1};state.sequence=1 end
end
return M
