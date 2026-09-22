local ffi=require('ffi')
local M=assert(loadfile(ROOT..'/src/markers.lua'))()
local profile=assert(loadfile(ROOT..'/src/layout.lua'))().profiles[1]
local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
local function word(v)return ffi.string(ffi.new('uint32_t[1]',v),4)end
local function float(v)return ffi.string(ffi.new('float[1]',v),4)end
local function ptr(v)return ffi.string(ffi.new('uint64_t[1]',v),8)end
local function fixture()
    local mem={[1000+profile.markers.root]=ptr(2000),[2000]=string.rep('\0',16+128*88)}
    local function put(a,b)
        for start,data in pairs(mem)do if a>=start and a+#b<=start+#data then
            local off=a-start;mem[start]=data:sub(1,off)..b..data:sub(off+#b+1);return
        end end
        error('bad fixture address')
    end
    local api={layout=profile,read=function(a,n)
        for start,data in pairs(mem)do if a>=start and a+n<=start+#data then return data:sub(a-start+1,a-start+n)end end
    end,pointer=function(b)local v=ffi.new('uint64_t[1]');ffi.copy(v,b,8);return tonumber(v[0])end}
    for _,sig in ipairs(profile.markers.signatures)do mem[1000+sig[1]]=sig[2]:gsub('..',function(x)return string.char(tonumber(x,16))end)end
    local function record(slot,id,owner,kind,elapsed)
        local a=2016+slot*88;put(a,word(kind or 1));put(a+16,float(8));put(a+20,float(elapsed or 1));put(a+24,word(owner or 11));put(a+28,word(0x1a00));put(a+32,word(id))
    end
    put(2012,word(1));record(0,22)
    local candidates={{id=22,identity='enemy22',eligible=true,valid=function()return true end}}
    return api,put,record,candidates,mem
end
local function read(api,c)return M.read(api,1000,11,c)end
test('local live enemy mark joins the verified candidate identity',function()
    local a,p,r,c=fixture();local m,status=read(a,c);assert(status=='eligible' and m.id==22 and m.identity=='enemy22' and m.valid())
end)
test('teammate mark cannot grant priority',function()
    local a,p,r,c=fixture();r(0,22,12);local m,status=read(a,c);assert(not m and status=='none')
end)
test('expired markers retained in ring are ignored',function()
    local a,p,r,c=fixture();r(0,22,11,1,8);assert(not read(a,c));p(2036,float(0/0));assert(not read(a,c))
end)
test('ground squad-member item and objective markers never become enemies',function()
    for _,kind in ipairs({0,9,10,18,20})do local a,p,r,c=fixture();r(0,22,11,kind);local m,status=read(a,c);assert(not m and status=='not_enemy')end
end)
test('latest local ground mark clears older enemy priority',function()
    local a,p,r,c=fixture();p(2012,word(2));r(1,0,11,0);assert(not read(a,c))
end)
test('missing ineligible or unidentified candidates cannot be selected',function()
    local a,p,r,c=fixture();assert(not read(a,{}));c[1].eligible=false;assert(not read(a,c));c[1].eligible=true;c[1].identity=nil;assert(not read(a,c))
end)
test('marker cancellation expiry and target identity change invalidate request',function()
    for _,change in ipairs({'time','flags','id','identity','head','root'})do
        local a,p,r,c=fixture();local m=assert(read(a,c))
        if change=='time' then p(2036,float(8)) elseif change=='flags' then p(2044,word(0))
        elseif change=='id' then p(2048,word(33)) elseif change=='identity' then c[1].valid=function()return false end
        elseif change=='head' then p(2008,word(1)) else p(1000+profile.markers.root,ptr(3000))end
        assert(not m.valid(),change)
    end
end)
test('moving target and advancing timer preserve marker validity',function()
    local a,p,r,c=fixture();local m=assert(read(a,c));p(2020,float(55));p(2036,float(2));assert(m.valid())
end)
test('unknown layout unreadable memory bad bounds and signatures degrade only marker lookup',function()
    for _,bad in ipairs({'layout','memory','bounds','signature'})do
        local a,p,r,c=fixture()
        if bad=='layout' then a.layout=nil elseif bad=='memory' then a.read=function()return nil end
        elseif bad=='bounds' then p(2012,word(128)) else p(1000+profile.markers.signatures[1][1],'x')end
        local m,status=read(a,c);assert(not m and (status=='unsupported_layout' or status=='unavailable'))
    end
end)
test('ring wrap and marker outside screen focus are handled',function()
    local a,p,r,c=fixture();p(2008,word(127));p(2012,word(1));r(127,99,12);assert(read(a,c).id==22)
    p(2044,word(0x1200));assert(read(a,c).id==22)
end)
test('changed timer moving backwards rejects slot reuse',function()
    local a,p,r,c=fixture();local m=assert(read(a,c));p(2036,float(0));assert(not m.valid())
end)
test('display categories five through eight defer to native hostile eligibility',function()
    for kind=5,8 do
        local a,p,r,c=fixture();r(0,22,11,kind)
        assert(read(a,c).id==22)
        c[1].eligible=false;local mark,status=read(a,c);assert(not mark and status=='not_eligible')
    end
end)
test('captured local enemy flags without focus bit still select eligible enemies',function()
    for _,flags in ipairs({0x200,0x600,0x1200,0x1a00})do
        local a,p,r,c=fixture();p(2044,word(flags));assert(read(a,c).id==22)
        c[1].eligible=false;local mark,status=read(a,c);assert(not mark and status=='not_eligible')
        r(0,22,12);p(2044,word(flags));mark,status=read(a,c);assert(not mark and status=='none')
    end
end)

test('HUD screen flag changes do not cancel a live marker request',function()
    local a,p,r,c=fixture();local mark=assert(read(a,c))
    for _,flags in ipairs({0x200,0x600,0xa00,0x1200,0x1a00})do
        p(2044,word(flags));assert(mark.valid())
    end
    p(2044,word(0x4000));assert(not mark.valid())
end)

test('newest ground ping without screen focus clears older enemy priority',function()
    local a,p,r,c=fixture();p(2012,word(2));r(1,0,11,0);p(2016+88+28,word(0x600))
    local mark,status=read(a,c);assert(not mark and status=='not_enemy')
end)

test('unfocused mark still expires cancels and rejects reused identity',function()
    for _,change in ipairs({'expiry','owner','target','head','identity'})do
        local a,p,r,c=fixture();p(2044,word(0x600));local mark=assert(read(a,c))
        if change=='expiry' then p(2036,float(8)) elseif change=='owner' then p(2040,word(12))
        elseif change=='target' then p(2048,word(33)) elseif change=='head' then p(2008,word(1))
        else c[1].valid=function()return false end end
        assert(not mark.valid(),change)
    end
end)
test('live ping survives score-only rejection as observation but never grants selection',function()
    local a,p,r,c=fixture();local mark,status,obs=read(a,c)
    assert(mark and obs.id==22 and obs.identity=='enemy22' and obs.remaining==7)
    local token=obs.token;c[1].eligible=false;c[1].eligibility_reason='score'
    mark,status,obs=read(a,c)
    assert(not mark and status=='not_eligible' and obs.reason=='score' and obs.token==token)
    c[1].valid=function()return false end
    mark,status,obs=read(a,c);assert(not mark and status=='changed' and not obs)
end)
test('missing candidate observation exposes ID only and cancellation clears it',function()
    local a,p,r,c=fixture();local mark,status,obs=read(a,{})
    assert(not mark and obs.id==22 and not obs.identity and obs.reason=='missing')
    p(2008,word(1));mark,status,obs=read(a,{})
    assert(not mark and not obs and status=='none')
end)
test('expired marker reports expiry without retaining an observation',function()
    local a,p,r,c=fixture();r(0,22,11,1,8)
    local mark,status,obs=read(a,c);assert(not mark and status=='expired' and not obs)
end)
test('observation prefers eligible duplicate and retains screen-independent token',function()
    local a,p,r,c=fixture();table.insert(c,1,{id=22,eligible=false,identity='enemy22',eligibility_reason='score',valid=function()return true end})
    local m,_,obs=read(a,c);assert(m and obs.reason=='eligible');local token=obs.token
    p(2044,word(0x200));local _,_,next_obs=read(a,c);assert(next_obs.token==token)
end)
test('request-time candidate read error cancels priority without escaping the validity guard',function()
    local a,p,r,c=fixture();local mark=assert(read(a,c))
    c[1].valid=function()error('read failed')end
    assert(mark.valid()==false)
end)
return tostring(passed)..' marker tests passed'
