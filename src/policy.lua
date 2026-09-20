-- No burn-state reads. Rotation is based on a short, approximate attack window.
local M={window=0.4,no_attack_seconds=1.5,max_lock_seconds=1.5,retry=0.15,max_gap=0.25,lease_seconds=0.25,history_seconds=1,history_limit=1,near_radius=15}
local function reset_lock(state)
    state.lock_elapsed=0;state.lock_tracking=false
end
local function prune(state,now)
    state.visited=state.visited or {}
    local count=0
    for id,record in pairs(state.visited)do
        if now<record.at or now-record.at>=M.history_seconds then state.visited[id]=nil
        else count=count+1 end
    end
    state.history_count=count
end
local function remember(state,id,identity,now,reason)
    if not identity then return end
    if not state.visited[id] then
        if state.history_count>=M.history_limit then
            local oldest
            for key,r in pairs(state.visited)do
                if not oldest or r.at<state.visited[oldest].at or r.at==state.visited[oldest].at and key<oldest then oldest=key end
            end
            state.visited[oldest]=nil;state.history_count=state.history_count-1
        end
        state.history_count=state.history_count+1
    end
    state.visited[id]={identity=identity,at=now,reason=reason}
end
function M.pause(state,now)
    prune(state,now);state.elapsed=0;state.idle_elapsed=0;reset_lock(state);state.attacking=false;state.last=nil;state.target=nil;state.target_identity=nil
end
local function distance(c)
    local d=c.distance2
    return type(d)=='number' and d==d and d>=0 and d<math.huge and d or math.huge
end
local function position(c)
    local p=c and c.position
    if type(p)~='table' then return nil end
    for i=1,3 do
        local v=p[i]
        if type(v)~='number' or v~=v or math.abs(v)>=1000000 then return nil end
    end
    return p
end
local function separation(c,origin)
    local p=position(c)
    if not p or not origin then return math.huge end
    return (p[1]-origin[1])^2+(p[2]-origin[2])^2+(p[3]-origin[3])^2
end
function M.plan(state,s,now)
    assert(type(now)=='number' and now==now,'invalid time')
    if state.key~=s.key then
        state.key=s.key;state.target=nil;state.target_identity=nil;state.elapsed=0;state.idle_elapsed=0;reset_lock(state)
        state.attacking=false;state.visited={};state.last=nil;state.retry_at=0
    end
    prune(state,now)
    local dt=state.last and math.max(0,math.min(now-state.last,M.max_gap)) or 0
    if state.last and (now<state.last or now-state.last>M.max_gap) then state.elapsed=0;state.idle_elapsed=0;reset_lock(state);state.attacking=false;dt=0 end
    if state.last and now<state.last then state.retry_at=0 end
    state.last=now
    local eligible={};local target_identity,current
    for _,c in ipairs(s.candidates or {}) do
        local old=state.visited[c.id]
        if old and c.identity and old.identity~=c.identity then
            state.visited[c.id]=nil;state.history_count=state.history_count-1
        end
        if c.id==s.target then
            target_identity=c.identity
            if c.identity and (not current or distance(c)<distance(current)
                or distance(c)==distance(current) and position(c) and not position(current)) then current=c end
        end
        if c.eligible and c.id~=s.target and (not eligible[c.id] or distance(c)<distance(eligible[c.id])) then eligible[c.id]=c end
    end
    if state.target~=s.target or state.target_identity~=target_identity then
        state.target=s.target;state.target_identity=target_identity;state.elapsed=0;state.idle_elapsed=0;reset_lock(state);state.attacking=false;dt=0
    end
    -- Nodes 6 and 7 both consume the same guarded selection deadline. Node 6
    -- only enters 7 after its native attack gates pass; entering 7 requests fire.
    -- This is attack-state evidence, not beam emission or hit detection.
    if (s.node~=6 and s.node~=7) or not s.target or s.target==0 then
        state.elapsed=0;state.idle_elapsed=0;reset_lock(state);state.attacking=false;return nil,'tracking'
    end
    -- Independent of attack/aim toggles; only consecutive, identified snapshots
    -- in nodes 6/7 count. Never carry time across missing data or other nodes.
    if target_identity then
        state.lock_elapsed=(state.lock_elapsed or 0)+(state.lock_tracking and dt or 0)
        state.lock_tracking=true
    else reset_lock(state) end
    local reason,waiting
    if s.node==7 and s.synced then
        if not state.attacking then dt=0 end
        state.elapsed=state.elapsed+dt;state.idle_elapsed=0;state.attacking=true
        if state.elapsed>=M.window then reason='attack_window' else waiting='attack_window' end
    else
        if state.attacking then dt=0 end
        state.elapsed=0;state.attacking=false;state.idle_elapsed=(state.idle_elapsed or 0)+dt
        if not target_identity then state.idle_elapsed=0;return nil,'tracking' end
        if state.idle_elapsed>=M.no_attack_seconds then reason='lock_timeout' else waiting='no_attack_window' end
    end
    if not reason and target_identity and state.lock_elapsed>=M.max_lock_seconds then reason='lock_max_duration' end
    if not reason then return nil,next(eligible) and waiting or 'no_alternative' end
    local timeout=reason~='attack_window'
    if now<(state.retry_at or 0) then return nil,'retry_delay' end
    if not next(eligible) then remember(state,s.target,target_identity,now,reason);return nil,'no_alternative' end
    -- Close threats take precedence over Recent only when returning from a far
    -- target. An already-near target can continue through its adjacent cluster.
    local near_priority=false
    if not timeout and current and distance(current)<math.huge and distance(current)>M.near_radius^2 then
        local nearby={}
        for id,c in pairs(eligible)do if distance(c)<=M.near_radius^2 then nearby[id]=c end end
        if next(nearby) then eligible=nearby;near_priority=true end
    end
    local pool={};local unseen=false
    for id,c in pairs(eligible) do
        if timeout or not state.visited[id] then pool[id]=c;unseen=true end
    end
    if not unseen then
        local oldest
        for id in pairs(eligible) do if not oldest or state.visited[id].at<oldest then oldest=state.visited[id].at end end
        for id,c in pairs(eligible) do if state.visited[id].at==oldest then pool[id]=c end end
    end
    local origin=not timeout and not near_priority and position(current) or nil
    local basis=timeout and 'timeout_rover' or near_priority and 'near_rover' or 'rover_fallback'
    -- Use one distance metric for the entire pool; never compare distances to
    -- different origins. If no target-relative positions work, use drone range.
    if origin then
        local usable=false
        for _,c in pairs(pool)do if separation(c,origin)<math.huge then usable=true;break end end
        if usable then basis='previous_target' else origin=nil end
    end
    local selected,best
    for id,c in pairs(pool)do
        local d=origin and separation(c,origin) or distance(c)
        if d<math.huge and (not best or d<best or d==best and id<selected) then selected=id;best=d end
    end
    local allowed={}
    if selected then allowed[selected]=true else for id in pairs(pool)do allowed[id]=true end end
    local blocked={[s.target]=true}
    for _,c in ipairs(s.candidates or {}) do if c.eligible and not allowed[c.id] then blocked[c.id]=true end end
    -- Choose using the preceding record before replacing it with this target;
    -- otherwise a one-entry history would only contain the already excluded target.
    remember(state,s.target,target_identity,now,reason)
    return {blocked=blocked,allowed=allowed,target=s.target,node=s.node,reason=reason,selected=selected,distance2=best,
        ranking=selected and 'nearest' or 'native_distance_unavailable',selection_basis=selected and basis or 'native',until_time=now+M.lease_seconds}
end
function M.committed(state,plan,now)
    state.elapsed=0;state.idle_elapsed=0;reset_lock(state);state.retry_at=now+M.retry
end
return M
