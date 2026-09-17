local root=assert(ROOT)
local P=assert(loadfile(root..'/src/policy.lua'))()
local L=assert(loadfile(root..'/src/lease.lua'))()
local C=assert(loadfile(root..'/src/controller.lua'))()
local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
local function row(target,ids)
    local s={key='rover-A',target=target,node=7,synced=true,candidates={}}
    for _,id in ipairs(ids or {1,2,3})do s.candidates[#s.candidates+1]={id=id,eligible=true}end
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
test('scanning and mismatched aim never trigger rotation',function()
    local s=row(1);s.node=6;assert(not due({},s,0));s.node=7;s.synced=false;assert(not due({},s,0))
end)
test('long gaps and clock reversal do not count as attack time',function()
    local st={};local s=row(1);P.plan(st,s,0);P.plan(st,s,.2)
    assert(not P.plan(st,s,10));assert(not P.plan(st,s,9))
end)
test('many targets cycle instead of ping-ponging between two',function()
    local st={};local s=row(1);local p=due(st,s,0);P.committed(st,p,.45)
    s.target=2;p=due(st,s,1);assert(p.allowed[3] and not p.allowed[1]);P.committed(st,p,1.45)
    s.target=3;p=due(st,s,2);assert(p.allowed[1] and not p.allowed[2]);P.committed(st,p,2.45)
    s.target=1;p=due(st,s,3);assert(p.allowed[2] and not p.allowed[3])
end)
test('new rover identity discards previous rotation history',function()
    local st={};local s=row(1);local p=due(st,s,0);P.committed(st,p,.45)
    s.key='rover-B';s.target=2;p=due(st,s,1);assert(p.allowed[1] and p.allowed[3])
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
return tostring(passed)..' core tests passed'
