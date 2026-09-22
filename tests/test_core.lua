local root=assert(ROOT)
local P=assert(loadfile(root..'/src/policy.lua'))()
local L=assert(loadfile(root..'/src/lease.lua'))()
local C=assert(loadfile(root..'/src/controller.lua'))()
local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
local function row(target,ids)
    local s={key='rover-A',target=target,node=7,synced=true,candidates={}}
    for _,id in ipairs(ids or {1,2,3})do s.candidates[#s.candidates+1]={id=id,identity='entity-'..id,eligible=true}end
    return s
end
local function due(state,s,start)
    P.plan(state,s,start);P.plan(state,s,start+.15);P.plan(state,s,start+.3)
    return P.plan(state,s,start+.45)
end
test('rotation waits for the short attack window',function()
    local st={};local s=row(1);assert(not P.plan(st,s,0));assert(not P.plan(st,s,.2))
    local p=P.plan(st,s,.4);assert(p and p.blocked[1] and p.allowed[2] and p.allowed[3])
end)
test('single target continues uninterrupted',function()assert(not due({},row(1,{1}),0))end)
test('unusable alternatives do not force a rotation',function()
    local s=row(1,{1,2});s.candidates[2].eligible=false;assert(not due({},s,0))
end)
test('new targets receive a fresh window',function()
    local st={};local s=row(1);assert(due(st,s,0));s.target=2
    assert(not P.plan(st,s,.5));assert(not P.plan(st,s,.6))
end)
test('tracking and mismatched aim wait for the longer timeout',function()
    local s=row(1);s.node=6;assert(not due({},s,0));s.node=7;s.synced=false;assert(not due({},s,0))
end)
test('long gaps and clock reversal do not count as attack time',function()
    local st={};local s=row(1);P.plan(st,s,0);P.plan(st,s,.2)
    assert(not P.plan(st,s,10));assert(not P.plan(st,s,9))
end)
test('one recent target avoids an immediate return while another candidate exists',function()
    local st={};local s=row(1);local p=due(st,s,0);P.committed(st,p,.45)
    s.target=2;p=due(st,s,.5);assert(p.allowed[3] and not p.allowed[1]);P.committed(st,p,.95)
    s.target=3;p=due(st,s,1);assert(p.allowed[1] and not p.allowed[2]);P.committed(st,p,1.45)
    s.target=1;p=due(st,s,1.5);assert(p.allowed[2] and not p.allowed[3])
end)
test('new rover identity discards previous rotation history',function()
    local st={};local s=row(1);local p=due(st,s,0);P.committed(st,p,.45)
    s.key='rover-B';s.target=2;p=due(st,s,1);assert(p.allowed[1] and p.allowed[3])
end)
test('nearest unvisited candidate is the only preferred alternative',function()
    local s=row(1);s.candidates[2].distance2=100;s.candidates[3].distance2=25
    local p=due({},s,0);assert(p.selected==3 and p.allowed[3] and not p.allowed[2] and p.blocked[2])
end)
test('unvisited target outranks a closer recently attacked target',function()
    local st={};due(st,row(2,{2}),0)
    local s=row(1);s.candidates[2].distance2=1;s.candidates[3].distance2=100
    local p=due(st,s,.5);assert(p.selected==3)
end)
test('the sole alternative can be reused even when it is the recent record',function()
    local st={};due(st,row(2,{2}),0)
    local s=row(1,{1,2});s.candidates[2].distance2=1
    assert(due(st,s,.5).selected==2)
end)
test('records expire exactly one second after last observation',function()
    local st={};due(st,row(2,{2}),0)
    P.pause(st,1.44);assert(st.visited[2]);P.pause(st,1.45);assert(not st.visited[2] and st.history_count==0)
end)
test('each new record replaces the preceding one without growing past one',function()
    local st={}
    for i=1,9 do due(st,row(i,{i}),(i-1)*.46);assert(st.history_count==1)end
    assert(not st.visited[1] and not st.visited[8] and st.visited[9])
end)
test('attacking the same target refreshes one entry rather than appending',function()
    local st={};local s=row(1,{1});due(st,s,0)
    for i=1,30 do P.plan(st,s,.45+i*.15)end
    assert(st.history_count==1 and st.visited[1].at>4)
end)
test('reused numeric target ID with a new identity is unvisited',function()
    local st={};due(st,row(2,{2}),0)
    local s=row(1);s.candidates[2].identity='new-entity-2';s.candidates[2].distance2=1;s.candidates[3].distance2=100
    local p=due(st,s,1);assert(p.selected==2 and not st.visited[2])
end)
test('short partial attack is not recorded as a completed attack window',function()
    local st={};local s=row(1);P.plan(st,s,0);P.plan(st,s,.2)
    s.target=2;P.plan(st,s,.3);assert(not st.visited[1])
end)
test('distance ties use a stable target ID instead of candidate iteration order',function()
    local s=row(1,{3,2,1});s.candidates[1].distance2=25;s.candidates[2].distance2=25
    assert(due({},s,0).selected==2)
end)
test('invalid distance falls back to native choice when no distances are usable',function()
    local s=row(1);s.candidates[2].distance2=0/0;s.candidates[3].distance2=-1
    local p=due({},s,0);assert(not p.selected and p.allowed[2] and p.allowed[3] and p.ranking=='native_distance_unavailable')
end)
test('duplicate candidate records choose the nearest valid distance for one ID',function()
    local s=row(1,{1,2,3,2});s.candidates[2].distance2=100;s.candidates[3].distance2=25;s.candidates[4].distance2=9
    assert(due({},s,0).selected==2)
end)
local function fixture()
    local mem={[10]='AAAA',[20]='BBBBBBBB'};local writes=0
    local api={read=function(a,n)local b=mem[a];return b and b:sub(1,n)end,
        writable_data=function()return true end,write=function(a,b)writes=writes+1;mem[a]=b;return true end}
    local changes={{address=10,before='AAAA',after='\0\0\0\0',valid=function()return true end},
        {address=20,before='BBBBBBBB',after='CCCCCCCC',valid=function()return true end}}
    return api,mem,changes,function()return writes end
end
test('leases restore both mask and deadline',function()
    local api,m,w=fixture();local l,e=L.acquire(api,w);assert(l and not e and m[10]==w[1].after)
    assert(L.restore(api,l) and m[10]=='AAAA' and m[20]=='BBBBBBBB')
end)
test('prevalidation rejects changed memory before any write',function()
    local api,m,w,n=fixture();m[20]='changed!';assert(not L.acquire(api,w));assert(n()==0)
end)
test('engine deadline updates survive cleanup',function()
    local api,m,w=fixture();local l=L.acquire(api,w);m[20]='ENGINE!!';assert(L.restore(api,l));assert(m[20]=='ENGINE!!')
end)
test('reused candidate storage is not restored by a stale lease',function()
    local api,m,w,n=fixture();local l=L.acquire(api,w);w[1].valid=function()return false end
    m[10]='NEW!';assert(L.restore(api,l));assert(m[10]=='NEW!')
end)
test('temporary read failure keeps the restore pending',function()
    local api,m,w=fixture();local l=L.acquire(api,w);w[1].valid=function()return nil end
    assert(not L.restore(api,l));w[1].valid=function()return true end;assert(L.restore(api,l));assert(m[10]=='AAAA')
end)
test('partial write failure can be rolled back',function()
    local api,m,w=fixture();local original=api.write
    api.write=function(a,b)if a==20 then m[a]=b:sub(1,3)..m[a]:sub(4);return false end;return original(a,b)end
    local l,e=L.acquire(api,w);assert(l and e=='write_failed');api.write=original
    assert(L.restore(api,l));assert(m[10]=='AAAA' and m[20]=='BBBBBBBB')
end)
test('nonwritable data is never touched',function()
    local api,m,w,n=fixture();api.writable_data=function()return false end
    assert(not L.acquire(api,w));assert(n()==0)
end)
local function controller_fixture(enabled)
    local api,mem,w,n=fixture();local now=0;api.time=function()return now end
    local s=row(1,{1,2});s.id=9;s.guards={};s.transition={};s.deadline='BBBBBBBB';s.deadline_value=1000100
    s.now_native=1000000;s.deadline_address=20;s.valid=function()return true end
    s.candidates[1].address=10;s.candidates[1].mask='AAAA';s.candidates[1].valid=s.valid
    s.candidates[2].address=30;s.candidates[2].mask='DDDD';s.candidates[2].valid=s.valid;mem[30]='DDDD'
    local snapshot={read=function()if s.unavailable then return nil,'waiting_for_runtime'end;return s,'observing'end,matches=function()return true end,tickword=function()return 'CCCCCCCC'end}
    local c=C(api,snapshot,P,L,nil,enabled)
    return c,s,mem,function(t)now=t;assert(c.poll())end,n
end
test('diagnostic mode records intent without writes',function()
    local c,s,m,step,n=controller_fixture(false);step(0);step(.15);step(.3);step(.45)
    assert(c.would_rotate==1 and c.requests==0 and n()==0)
end)
test('controller waits through startup then resumes normal selection',function()
    local c,s,m,step,n=controller_fixture(true)
    s.unavailable=true;step(0);step(.15);assert(c.status=='waiting_for_runtime' and n()==0 and not c.stopped)
    s.unavailable=false;step(.3);step(.45);step(.6);step(.8)
    assert(c.requests==1 and not c.stopped)
end)
test('runtime loss during a request restores owned data',function()
    local c,s,m,step=controller_fixture(true)
    step(0);step(.15);step(.3);step(.45);assert(c.requests==1)
    s.unavailable=true;step(.55);assert(m[10]=='AAAA' and m[20]=='BBBBBBBB' and not c.stopped)
end)
test('transient runtime loss retains recent history but cancels attack timing',function()
    local c,s,m,step=controller_fixture(false);step(0);step(.15);step(.3);step(.45)
    assert(c.policy.visited[1]);s.unavailable=true;step(.55)
    assert(c.policy.visited[1] and c.policy.elapsed==0)
    step(4.5);assert(c.policy.history_count==0)
end)
test('experimental mode restores after observed target change',function()
    local c,s,m,step=controller_fixture(true);step(0);step(.15);step(.3);step(.45)
    assert(c.requests==1 and m[10]=='\0\0\0\0');s.target=2;step(.55)
    assert(c.rotations==1 and m[10]=='AAAA' and m[20]=='BBBBBBBB')
end)
test('selection lease times out rather than suppressing forever',function()
    local c,s,m,step=controller_fixture(true);step(0);step(.15);step(.3);step(.45);step(.8)
    assert(m[10]=='AAAA');assert(c.stop())
end)
test('shutdown restores an outstanding request',function()
    local c,s,m,step=controller_fixture(true);step(0);step(.15);step(.3);step(.45)
    assert(c.stop());assert(m[10]=='AAAA' and m[20]=='BBBBBBBB')
end)
test('telemetry separates an active request from its last completed request',function()
    local c,s,m,step=controller_fixture(true);s.candidates[2].distance2=25
    step(0);assert(c.decision=='attack_window' and not c.active_request)
    step(.15);step(.3);step(.45)
    assert(c.active_request and c.active_ranking=='nearest' and c.last_request_target==2 and c.active_target==2 and c.target_synced and c.last_request_finished_at==nil)
    step(.51);assert(c.active_request and c.decision=='request_active')
    s.target=2;step(.57)
    assert(not c.active_request and not c.active_ranking and c.ranking==nil and c.planned_target==0 and not c.active_target and c.target==2)
    assert(c.last_request_ranking=='nearest' and c.last_request_at==.45 and c.rotations==1 and c.last_request_key==s.key and c.current_key==s.key and c.last_request_finished_at==.57)
end)
test('distance fallback is still an active mod request',function()
    local c,s,m,step=controller_fixture(true);step(0);step(.15);step(.3);step(.45)
    assert(c.active_request and c.active_ranking=='native_distance_unavailable')
end)
test('single target and waiting states do not keep an active request label',function()
    local c,s,m,step=controller_fixture(true);s.candidates[2].eligible=false;step(0)
    assert(c.decision=='no_alternative' and not c.active_request)
    s.unavailable=true;step(.15)
    assert(c.decision=='waiting_for_runtime' and c.target==0 and c.eligible==0 and not c.target_synced and c.current_key==nil)
end)
local function stalled(s,state)
    state=state or {};s.node=6
    for i=0,5 do assert(not P.plan(state,s,i*.25)) end
    return P.plan(state,s,1.5),state
end
test('lock timeout waits one and a half seconds then chooses nearest other candidate',function()
    local s=row(1);s.node=6;s.candidates[2].distance2=25;s.candidates[3].distance2=4
    local st={};for i=0,5 do assert(not P.plan(st,s,i*.25)) end
    assert(not P.plan(st,s,1.49))
    local p=P.plan(st,s,1.5)
    assert(p and p.reason=='lock_timeout' and p.node==6 and p.selected==3 and p.blocked[1])
    assert(st.history_count==1 and st.visited[1].reason=='lock_timeout')
end)
test('timeout nearest choice can revisit a recent reachable alternative',function()
    local s=row(1);s.node=6;s.candidates[2].distance2=1;s.candidates[3].distance2=25
    local st={};for i=0,5 do assert(not P.plan(st,s,i*.25)) end
    st.visited[2]={identity='entity-2',at=1.25};st.history_count=1
    assert(P.plan(st,s,1.5).selected==2)
end)
test('starting attack cancels idle timing but does not reset the same-target watchdog',function()
    local s=row(1);s.node=6;local st={}
    for i=0,5 do assert(not P.plan(st,s,i*.25)) end
    s.node=7;assert(not P.plan(st,s,1.45));assert(st.idle_elapsed==0)
    local p=P.plan(st,s,1.65)
    assert(p.reason=='lock_max_duration' and st.idle_elapsed==0)
end)
test('target switch or entity reuse starts a new lock timeout',function()
    local s=row(1);s.node=6;local st={};P.plan(st,s,0);P.plan(st,s,.25)
    s.target=2;assert(not P.plan(st,s,.5));assert(st.idle_elapsed==0)
    P.plan(st,s,.75);s.candidates[2].identity='reused';assert(not P.plan(st,s,1));assert(st.idle_elapsed==0)
end)
test('long gaps and missing snapshots never count toward the idle timeout',function()
    local s=row(1);s.node=6;local st={};P.plan(st,s,0);P.plan(st,s,.25)
    assert(not P.plan(st,s,2));assert(st.idle_elapsed==0)
    P.plan(st,s,2.25);P.pause(st,2.4);assert(not P.plan(st,s,2.5));assert(st.idle_elapsed==0)
    P.plan(st,s,2.75);assert(not P.plan(st,s,1));assert(st.idle_elapsed==0)
end)
test('node seven with unsynchronized aim also receives the idle timeout',function()
    local s=row(1);s.synced=false;local st={}
    for i=0,5 do assert(not P.plan(st,s,i*.25)) end
    assert(not P.plan(st,s,1.49))
    assert(P.plan(st,s,1.5).reason=='lock_timeout')
end)
test('timeout never forces a sole or invalid target and ignores other nodes',function()
    assert(not stalled(row(1,{1})))
    local s=row(1);s.candidates[2].eligible=false;s.candidates[3].eligible=false;assert(not stalled(s))
    s=row(1);s.node=3;local st={};for i=0,7 do assert(not P.plan(st,s,i*.25)) end
    s=row(1);s.candidates[1].identity=nil;assert(not stalled(s))
end)
test('controller keeps a node six request until release and restores on attack entry',function()
    local c,s,m,step=controller_fixture(true);s.node=6;s.candidates[2].distance2=9
    for i=0,5 do step(i*.25);assert(c.requests==0) end;step(1.5)
    assert(c.requests==1 and c.active_reason=='lock_timeout' and c.active_target==2 and m[10]=='\0\0\0\0')
    step(1.56);assert(c.active_request)
    s.node=7;step(1.62);assert(not c.active_request and m[10]=='AAAA' and m[20]=='BBBBBBBB')
end)
test('node six request is restored if native selection does not consume it',function()
    local c,s,m,step=controller_fixture(true);s.node=6
    for i=0,5 do step(i*.25);assert(c.requests==0) end;step(1.5);step(1.8)
    assert(not c.active_request and m[10]=='AAAA' and c.requests==1)
end)
local function located(points)
    local s=row(1)
    for i,p in ipairs(points)do
        s.candidates[i].position=p
        s.candidates[i].distance2=p[1]^2+p[2]^2+p[3]^2
    end
    return s
end
test('normal rotation follows adjacent enemies instead of nearest drone range',function()
    local s=located({{20,0,0},{22,0,0},{16,0,0}})
    local p=due({},s,0)
    assert(p.selected==2 and p.selection_basis=='previous_target' and p.distance2==4)
end)
test('far target yields to a candidate within twenty meters',function()
    local s=located({{40,0,0},{41,0,0},{20,0,0}})
    local p=due({},s,0)
    assert(p.selected==3 and p.selection_basis=='near_rover' and p.blocked[2])
end)
test('a target exactly at twenty meters keeps adjacent selection across the boundary',function()
    local s=located({{20,0,0},{21,0,0},{1,0,0}})
    local p=due({},s,0);assert(p.selected==2 and p.selection_basis=='previous_target')
end)
test('a target just outside twenty meters switches to the near pool',function()
    local s=located({{20.001,0,0},{20.002,0,0},{1,0,0}})
    assert(due({},s,0).selected==3)
end)
test('returning to close threats outranks the recent exclusion',function()
    local st={};due(st,row(3,{3}),0)
    local s=located({{40,0,0},{41,0,0},{5,0,0}})
    assert(due(st,s,.5).selected==3)
end)
test('adjacent sorting still avoids the one recent enemy when alternatives exist',function()
    local st={};due(st,row(2,{2}),0)
    local s=located({{5,0,0},{6,0,0},{10,0,0}})
    assert(due(st,s,.5).selected==3)
end)
test('near pool applies recent priority then nearest drone distance',function()
    local s=located({{40,0,0},{2,0,0},{12,0,0}})
    assert(due({},s,0).selected==2)
    local st={};due(st,row(2,{2}),0);assert(due(st,s,.5).selected==3)
end)
test('timeout escapes toward the drone rather than staying by the blocked target',function()
    local s=located({{12,0,0},{13,0,0},{2,0,0}})
    local p=stalled(s);assert(p.selected==3 and p.selection_basis=='timeout_rover')
end)
test('missing or invalid target positions use drone range without mixed metrics',function()
    local s=located({{12,0,0},{13,0,0},{2,0,0}})
    s.candidates[1].position={0/0,0,0}
    local p=due({},s,0);assert(p.selected==3 and p.selection_basis=='rover_fallback')
    s=located({{12,0,0},{13,0,0},{2,0,0}})
    s.candidates[2].position=nil;s.candidates[3].position=nil
    assert(due({},s,0).selection_basis=='rover_fallback')
    s.candidates[2].distance2=nil;s.candidates[3].distance2=nil
    assert(due({},s,0).selection_basis=='native')
end)
test('target-relative positions work without a drone origin but cannot assert near priority',function()
    local s=located({{30,0,0},{31,0,0},{1,0,0}})
    for _,c in ipairs(s.candidates)do c.distance2=nil end
    local p=due({},s,0);assert(p.selected==2 and p.selection_basis=='previous_target')
end)
test('ineligible nearby enemies do not trigger the radius override',function()
    local s=located({{30,0,0},{31,0,0},{1,0,0}});s.candidates[3].eligible=false
    local p=due({},s,0);assert(p.selected==2 and p.selection_basis=='previous_target')
end)
test('adjacency measures all three axes and preserves deterministic ties',function()
    local s=located({{0,0,5},{0,0,7},{0,0,1}})
    assert(due({},s,0).selected==2)
    s.candidates[3].position={0,2,5};assert(due({},s,0).selected==2)
end)
test('controller retains request distance basis after restoring the request',function()
    local c,s,m,step=controller_fixture(true)
    s.candidates[1].position={5,0,0};s.candidates[2].position={6,0,0}
    s.candidates[1].distance2=25;s.candidates[2].distance2=36
    step(0);step(.15);step(.3);step(.45)
    assert(c.selection_basis=='previous_target' and c.active_basis=='previous_target' and c.planned_distance==1)
    s.target=2;step(.55)
    assert(c.active_basis==nil and c.selection_basis==nil and c.last_request_basis=='previous_target')
end)

local function flapping(s,st,mode,last)
    for i=0,last do
        local attack=math.floor(i/4)%2==0
        s.node=mode=='node' and (attack and 7 or 6) or 7
        s.synced=mode=='node' or attack
        assert(not P.plan(st,s,i/16))
    end
end
for _,mode in ipairs({'node','sync'}) do
    test('same-target watchdog survives repeated '..mode..' toggles',function()
        local st={};local s=row(1);flapping(s,st,mode,23)
        assert(not P.plan(st,s,1.49))
        local plan=P.plan(st,s,1.5)
        assert(plan and plan.reason=='lock_max_duration' and plan.blocked[1])
        assert(st.elapsed<P.window and st.idle_elapsed<P.no_attack_seconds)
        assert(st.lock_elapsed==1.5)
    end)
end
test('normal attack window wins when the watchdog becomes due on the same sample',function()
    local st={};local s=row(1);s.node=6
    for i=0,16 do assert(not P.plan(st,s,i/16)) end
    s.node=7
    for i=17,23 do assert(not P.plan(st,s,i/16)) end
    assert(P.plan(st,s,1.5).reason=='attack_window')
end)
test('watchdog uses nearest Rover ignoring Recent and falls back to native without distance',function()
    for _,distances in ipairs({true,false}) do
        local st={};local s=located({{12,0,0},{13,0,0},{2,0,0}})
        if not distances then for _,c in ipairs(s.candidates)do c.distance2=nil end end
        flapping(s,st,'sync',23)
        st.visited[3]={identity='entity-3',at=1.4};st.history_count=1
        local plan=P.plan(st,s,1.5)
        assert(plan.reason=='lock_max_duration')
        if distances then assert(plan.selected==3 and plan.selection_basis=='timeout_rover')
        else assert(not plan.selected and plan.allowed[2] and plan.allowed[3] and plan.selection_basis=='native') end
    end
end)
test('watchdog resets across identity context observation and node discontinuities',function()
    for _,change in ipairs({'identity','target','key','missing_identity','node','pause','gap','reverse'}) do
        local st={};local s=row(1);flapping(s,st,'sync',20)
        assert(st.lock_elapsed==1.25)
        local now=1.3125
        if change=='identity' then s.candidates[1].identity='reused'
        elseif change=='target' then s.target=2
        elseif change=='key' then s.key='new-rover'
        elseif change=='missing_identity' then s.candidates[1].identity=nil
        elseif change=='node' then s.node=3
        elseif change=='pause' then P.pause(st,1.3)
        elseif change=='gap' then now=2
        elseif change=='reverse' then now=1 end
        assert(not P.plan(st,s,now));assert(st.lock_elapsed==0,change)
        s.node=7;s.synced=false
        if change=='missing_identity' then s.candidates[1].identity='entity-1' end
        assert(not P.plan(st,s,now+.0625))
        assert(st.lock_elapsed<=.0625,change)
    end
end)
test('watchdog needs an identified target and an eligible alternative',function()
    for _,mode in ipairs({'single','invalid','missing_identity'}) do
        local st={};local s=row(1)
        if mode=='single' then s=row(1,{1})
        elseif mode=='invalid' then s.candidates[2].eligible=false;s.candidates[3].eligible=false
        else s.candidates[1].identity=nil end
        flapping(s,st,'sync',64)
        if mode=='missing_identity' then assert(st.lock_elapsed==0) end
    end
end)
test('committed watchdog starts a fresh observation window rather than requesting every poll',function()
    local st={};local s=row(1);flapping(s,st,'sync',23)
    local plan=P.plan(st,s,1.5);P.committed(st,plan,1.5)
    assert(st.lock_elapsed==0 and not st.lock_tracking)
    assert(not P.plan(st,s,1.5625));assert(st.lock_elapsed==0)
end)
test('controller submits the watchdog request and safely restores it',function()
    local c,s,m,step=controller_fixture(true);s.candidates[2].distance2=9
    for i=0,23 do s.synced=math.floor(i/4)%2==0;step(i/16);assert(c.requests==0) end
    step(1.5)
    assert(c.requests==1 and c.active_reason=='lock_max_duration' and c.active_target==2)
    assert(c.lock_elapsed==1.5 and c.lock_limit==1.5 and m[10]=='\0\0\0\0')
    s.target=2;step(1.5625)
    assert(c.rotations==1 and not c.active_request and m[10]=='AAAA')
    assert(c.last_request_reason=='lock_max_duration')
end)

test('own marked eligible enemy outranks adjacency and near radius',function()
    local s=located({{40,0,0},{2,0,0},{45,0,0}});s.marked={id=3,identity='entity-3'}
    local plan=due({},s,0);assert(plan.selected==3 and plan.selection_basis=='player_mark' and plan.blocked[2])
end)
test('marked selection works without distance and never widens eligibility',function()
    local s=row(1);s.marked={id=3,identity='entity-3'};assert(due({},s,0).selected==3)
    s.candidates[3].eligible=false;assert(due({},s,0).selection_basis~='player_mark')
    s.candidates[3].eligible=true;s.marked.identity='reused';assert(due({},s,0).selection_basis~='player_mark')
end)
test('marked current target receives four seconds before normal rotation',function()
    local s=row(1);s.marked={id=1,identity='entity-1'};local st={}
    for i=0,63 do assert(not P.plan(st,s,i/16))end
    local p=P.plan(st,s,4);assert(p.reason=='attack_window' and p.blocked[1] and p.selection_basis~='player_mark')
    assert(st.attack_limit==4 and st.no_attack_limit==3 and st.lock_limit==5)
end)

test('marked no-attack timeout waits three seconds then chooses nearest alternative',function()
    local s=located({{10,0,0},{8,0,0},{2,0,0}});s.node=6;s.synced=false
    s.marked={id=1,identity='entity-1'};local st={}
    for i=0,47 do assert(not P.plan(st,s,i/16))end
    local p=P.plan(st,s,3);assert(p.reason=='lock_timeout' and p.selected==3 and p.selection_basis=='timeout_rover')
end)

test('attack toggles and repeated marking cannot postpone the five-second watchdog',function()
    local s=row(1);local st={}
    for i=0,79 do
        s.marked={id=1,identity='entity-1'};s.node=i%4<2 and 6 or 7;s.synced=s.node==7
        assert(not P.plan(st,s,i/16))
    end
    s.node=6;s.synced=false
    local p=P.plan(st,s,5);assert(p.reason=='lock_max_duration' and st.lock_elapsed==5)
end)

test('canceled changed ineligible or identity-mismatched marks immediately restore normal limits',function()
    for _,change in ipairs({'cancel','other','identity','ineligible'})do
        local s=row(1);s.marked={id=1,identity='entity-1'};local st={}
        for i=0,31 do assert(not P.plan(st,s,i/16))end
        if change=='cancel' then s.marked=nil elseif change=='other' then s.marked={id=2,identity='entity-2'}
        elseif change=='identity' then s.marked.identity='reused' else s.candidates[1].eligible=false end
        local p=P.plan(st,s,2);assert(p and p.reason==(change=='other' and 'marked_priority' or 'attack_window'),change)
        assert(not st.marked_current and st.attack_limit==.4 and st.no_attack_limit==1.5 and st.lock_limit==1.5)
    end
end)

test('new marked target starts a fresh four-second attack window',function()
    local s=row(1);s.marked={id=1,identity='entity-1'};local st={}
    for i=0,47 do assert(not P.plan(st,s,i/16))end
    s.target=2;s.marked={id=2,identity='entity-2'}
    for i=48,111 do assert(not P.plan(st,s,i/16))end
    assert(P.plan(st,s,7).reason=='attack_window')
end)

test('gaps pause and reused current identity discard marked attack progress',function()
    for _,change in ipairs({'gap','pause','identity'})do
        local s=row(1);s.marked={id=1,identity='entity-1'};local st={}
        for i=0,47 do assert(not P.plan(st,s,i/16))end
        local start=3
        if change=='gap' then start=10 elseif change=='pause' then P.pause(st,3)
        else s.candidates[1].identity='new-entity';s.marked.identity='new-entity' end
        for i=0,63 do assert(not P.plan(st,s,start+i/16),change)end
        assert(P.plan(st,s,start+4).reason=='attack_window')
    end
end)

test('controller applies marked timers without extending the actual write lease',function()
    local c,s,m,step,n=controller_fixture(true);s.marked={id=1,identity='entity-1',valid=function()return true end}
    for i=0,63 do step(i/16);assert(c.requests==0 and n()==0)end
    assert(c.marked_current and c.attack_limit==4 and c.no_attack_limit==3 and c.lock_limit==5)
    step(4);assert(c.requests==1 and c.active_reason=='attack_window' and m[10]=='\0\0\0\0')
    step(4.25);assert(not c.active_request and m[10]=='AAAA' and m[20]=='BBBBBBBB')
    s.unavailable=true;step(4.5);assert(not c.marked_current and c.attack_elapsed==0 and c.lock_limit==1.5)
end)
test('Recent suppresses immediate return to the marked target',function()
    local st={};due(st,row(3,{3}),0);local s=located({{5,0,0},{6,0,0},{10,0,0}});s.marked={id=3,identity='entity-3'}
    assert(due(st,s,.5).selected==2);assert(due(st,s,2).selected==3)
end)
test('eligible new mark takes priority when an unrelated old target reaches timeout',function()
    local s=located({{12,0,0},{13,0,0},{2,0,0}});local st={};s.node=6
    for i=0,5 do assert(not P.plan(st,s,i*.25))end
    s.marked={id=2,identity='entity-2'}
    local p=P.plan(st,s,1.5);assert(p.selected==2 and p.selection_basis=='player_mark' and p.reason=='marked_priority')
end)
test('marker canceled before transaction cannot initiate writes',function()
    local c,s,m,step,n=controller_fixture(true);s.marked={id=2,identity='entity-2',valid=function()return false end}
    step(0);step(.15);step(.3);step(.45);assert(c.requests==0 and c.decision=='mark_changed' and n()==0)
end)
test('canceling an active marked request restores normal candidates',function()
    local c,s,m,step=controller_fixture(true);local live=true
    s.marked={id=2,identity='entity-2',valid=function()return live end}
    step(0);assert(c.requests==1 and c.active_basis=='player_mark')
    live=false;step(.0625);assert(not c.active_request and m[10]=='AAAA')
end)
local function mark_state(s,score)
    s.marker_observation={id=1,identity='entity-1',token='ping-A',elapsed=1,remaining=7,reason=score and 'score' or 'eligible'}
    s.candidates[1].eligible=not score;s.candidates[1].eligibility_reason=score and 'score' or 'eligible'
    s.marked=not score and {id=1,identity='entity-1',valid=function()return true end} or nil
    s.marker_status=score and 'not_eligible' or 'eligible'
end

test('score outage preserves current marked dwell for exactly 1.5 seconds',function()
    local s=row(1);local st={};mark_state(s,false)
    for i=0,8 do assert(not P.plan(st,s,i/8))end
    mark_state(s,true)
    for i=9,19 do assert(not P.plan(st,s,i/8));assert(st.marked_current and st.attack_limit==4)end
    local p=P.plan(st,s,2.5);assert(p and p.reason=='attack_window' and not st.marked_current and not st.mark_cache)
end)

test('score recovery continues attack progress without restarting the four-second window',function()
    local s=row(1);local st={};mark_state(s,false)
    for i=0,31 do
        mark_state(s,i>=8 and i<16 or i>=24);assert(not P.plan(st,s,i/8))
    end
    assert(P.plan(st,s,4).reason=='attack_window');assert(st.elapsed==4 and st.marked_grace_remaining>0)
end)

test('grace never grants a new marked selection or accepts never-eligible targets',function()
    local s=row(1);mark_state(s,true);local st={}
    assert(due(st,s,0));assert(not st.marked_current)
    s.target=2;s.candidates[2].distance2=4;s.candidates[3].distance2=9
    local p=due({},s,0);assert(p.selected==3 and p.selection_basis~='player_mark' and not p.allowed[1])
end)

test('cancellation replacement identity loss and non-score failures immediately cancel grace',function()
    for _,change in ipairs({'cancel','replace','identity','flags','faction','missing','token','rewind'})do
        local s=row(1);local st={};mark_state(s,false)
        for i=0,8 do P.plan(st,s,i/8)end
        mark_state(s,true)
        if change=='cancel' then s.marker_observation=nil
        elseif change=='replace' then s.marker_observation.id=2
        elseif change=='identity' then s.marker_observation.identity='new'
        elseif change=='token' then s.marker_observation.token='ping-B'
        elseif change=='rewind' then s.marker_observation.elapsed=0
        elseif change=='missing' then table.remove(s.candidates,1)
        else s.candidates[1].eligibility_reason=change;s.marker_observation.reason=change end
        P.plan(st,s,1.125);assert(not st.marked_current and not st.mark_cache,change)
    end
end)

test('grace does not extend three-second no-attack or five-second maximum-lock escape',function()
    for _,mode in ipairs({'idle','toggle'})do
        local s=row(1);local st={};local limit=mode=='idle' and 3 or 5
        for i=0,limit*8 do
            mark_state(s,i>limit*8-4)
            s.node=mode=='idle' and 6 or (i%4<2 and 6 or 7);s.synced=s.node==7
            local p=P.plan(st,s,i/8)
            if i<limit*8 then assert(not p)else assert(p.reason==(mode=='idle' and 'lock_timeout' or 'lock_max_duration'))end
        end
    end
end)

test('pause gap context and target changes discard grace',function()
    for _,change in ipairs({'pause','gap','key','target','reverse','node'})do
        local s=row(1);local st={};mark_state(s,false);P.plan(st,s,1)
        mark_state(s,true);local now=1.125
        if change=='pause' then P.pause(st,1.05) elseif change=='gap' then now=2
        elseif change=='key' then s.key='other' elseif change=='target' then s.target=2
        elseif change=='reverse' then now=.9 else s.node=3 end
        P.plan(st,s,now);assert(not st.marked_current and not st.mark_cache,change)
    end
end)

test('controller reports score grace and ended mark without inventing an eligible selection',function()
    local c,s,m,step=controller_fixture(true);mark_state(s,false)
    for i=0,8 do step(i/8)end
    mark_state(s,true);step(1.125)
    assert(c.marked_target==1 and c.marker_reason=='score' and c.marked_grace_remaining>1 and c.requests==0)
    s.marker_observation=nil;s.marker_status='expired';step(1.25)
    assert(c.marked_target==0 and c.marker_notice=='mark expired' and c.marked_grace_remaining==0)
    for i=11,23 do step(i/8)end
    assert(c.marker_notice==nil)
end)
test('eligible mark triggers immediately before attack or aiming timers mature',function()
    for _,node in ipairs({6,7})do
        local s=located({{40,0,0},{2,0,0},{45,0,0}});s.node=node;s.synced=node==7
        s.marked={id=3,identity='entity-3'};local st={}
        local p=P.plan(st,s,0)
        assert(p and p.reason=='marked_priority' and p.selected==3 and p.blocked[1] and p.blocked[2])
        assert(st.elapsed==0 and st.idle_elapsed==0 and st.mark_wait_reason=='ready')
    end
end)
test('immediate marking preserves real-time eligibility identity and native state gates',function()
    for _,bad in ipairs({'score','missing','identity','node','zero_target','no_identity'})do
        local s=row(1);local st={};s.marked={id=3,identity='entity-3'}
        if bad=='score' then s.candidates[3].eligible=false
        elseif bad=='missing' then table.remove(s.candidates,3)
        elseif bad=='identity' then s.marked.identity='reused'
        elseif bad=='node' then s.node=3
        elseif bad=='zero_target' then s.target=0
        else s.node=6;s.candidates[1].identity=nil end
        assert(not P.plan(st,s,0),bad)
    end
end)
test('marked priority retry waits half a second even after target or ping changes',function()
    local s=row(1);s.marked={id=3,identity='entity-3'};local st={}
    local p=P.plan(st,s,0);P.committed(st,p,0)
    s.target=2
    for _,t in ipairs({.125,.25,.375,.499})do
        s.marker_observation={id=3,identity='entity-3',token=tostring(t)}
        assert(not P.plan(st,s,t));assert(st.mark_wait_reason=='retry')
    end
    assert(P.plan(st,s,.5).reason=='marked_priority')
end)
test('immediate mark respects Recent after escaping an unattackable marked target',function()
    local s=located({{10,0,0},{2,0,0},{9,0,0}});s.marked={id=1,identity='entity-1'}
    s.node=6;s.synced=false;local st={}
    for i=0,11 do assert(not P.plan(st,s,i*.25))end
    local p=P.plan(st,s,3);assert(p.reason=='lock_timeout' and p.selected==2);P.committed(st,p,3)
    s.target=2;s.node=7;s.synced=true
    assert(not P.plan(st,s,3.125));assert(st.mark_wait_reason=='recent')
    s.synced=false;s.node=6
    for _,t in ipairs({3.25,3.5,3.75,3.999})do assert(not P.plan(st,s,t))end
    p=P.plan(st,s,4);assert(p.reason=='marked_priority' and p.selected==1)
end)
test('controller submits immediate mark once and preserves lease and retry bounds',function()
    local c,s,m,step=controller_fixture(true);s.marked={id=2,identity='entity-2',valid=function()return true end}
    step(0);assert(c.requests==1 and c.active_reason=='marked_priority' and m[10]==string.rep('\0',4))
    step(.25);assert(not c.active_request and m[10]=='AAAA' and m[20]=='BBBBBBBB')
    step(.375);assert(c.requests==1 and c.mark_wait_reason=='retry')
    step(.5);assert(c.requests==2 and c.active_basis=='player_mark')
end)
return tostring(passed)..' core tests passed'
