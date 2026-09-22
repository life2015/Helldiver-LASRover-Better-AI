local ffi,bit=require('ffi'),require('bit')
local M={}
local function u(b,o)local x=ffi.new('uint32_t[1]');ffi.copy(x,b:sub((o or 0)+1),4);return tonumber(x[0])end
local function f(b,o)local x=ffi.new('float[1]');ffi.copy(x,b:sub(o+1),4);return tonumber(x[0])end
local function tick(b)local x=ffi.new('uint64_t[1]');ffi.copy(x,b,8);return tonumber(x[0])end
function M.tickword(n)return ffi.string(ffi.new('uint64_t[1]',n),8)end
local function hash(s)return (s:gsub('..',function(x)return string.char(tonumber(x,16))end)):reverse()end
local AVATAR,PACK,DRONE=hash('4d1c334d294dfa97'),hash('af9b683ccb6ddc02'),hash('5beec97f4c7f4ae9')
function M.matches(api,guards)
    for _,g in ipairs(guards) do
        local b=api.read(g.address,#g.bytes)
        if not b then return nil end
        if b~=g.bytes then return false end
    end
    return true
end
local NOT_READY,CHANGING={},{}
local function read_snapshot(api,game)
    local guards={};local reads=0
    local layout=api.layout or {};local roots=layout.roots or {}
    local function address(rva)return game+(roots[rva] or rva)end
    local function read(a,n,guard)
        reads=reads+1;assert(reads<=1800,'snapshot read bound')
        local b=api.read(a,n)
        if not b or #b~=n then error(NOT_READY,0) end
        if guard then guards[#guards+1]={address=a,bytes=b} end
        return b
    end
    local function pointer(bytes)
        local p=api.pointer(bytes);if not p then error(NOT_READY,0) end;return p
    end
    local function ptr(a,guard)return pointer(read(a,8,guard))end
    local function consistent(ok)if not ok then error(CHANGING,0) end end
    local function root(rva)return ptr(address(rva),true)end
    local function scope(first,extra)
        local result=extra or {}
        for i=first,#guards do result[#result+1]=guards[i] end
        return result
    end
    local function lookup(address,key,limit)
        local h=read(address,20,true);local cap,empty,mul=u(h,8),u(h,12),u(h,16)
        if cap==0 then return nil end
        assert(cap<=limit and bit.band(cap,cap-1)==0,'map bound')
        local p=pointer(h)
        local product=tonumber(ffi.cast('uint32_t',ffi.new('uint64_t',key)*ffi.new('uint64_t',mul)))
        for probe=0,math.min(cap,128)-1 do
            local a=p+8*bit.band(product+probe,cap-1);local b=read(a,8)
            if u(b)==key then
                guards[#guards+1]={address=a,bytes=b}
                return u(b,4)~=0xffffffff and u(b,4) or nil
            end
            if u(b)==empty then return nil end
        end
        error('map probe bound')
    end
    local function array(manager,off,index,stride,size,guard)
        local a=ptr(manager+off,true)+index*stride
        return a,read(a,size,guard)
    end
    local mode=root(0x276c3d0);local status=read(mode,0x44)
    if u(status,8)==0 or u(status,0x40)~=1 then return nil,'waiting_for_mission' end
    local pm=root(0x276c190);local counts=read(pm+0x84,8)
    assert(u(counts)<=4 and u(counts,4)<=4,'player bound')
    if u(counts)==0 or u(counts,4)==0 then return nil,'waiting_for_player' end
    local unit=u(read(pm+0x3a8,4,true));if unit==0x7fff then return nil,'waiting_for_avatar' end
    local owner=root(0x276f0c0);local ei=lookup(owner+(layout.owner_map or 0xf21a88),unit,1048576)
    if not ei then return nil,'waiting_for_avatar' end
    assert(ei<262144,'entity bound')
    local avatar=read(owner+(layout.owner_entities or 0xf31ad8)+ei*24,24,true);local aid=u(avatar,8)
    if avatar:sub(1,8)~=AVATAR or bit.band(avatar:byte(21),3)~=1 then return nil,'avatar_not_local' end
    local eq=root(0x276c468);local qi=lookup(eq+40,aid,8192)
    if not qi then return nil,'no_equipment' end
    assert(qi<4096,'equipment bound')
    local eqent=ptr(ptr(eq+64,true)+qi*8,true)
    consistent(read(eqent,20,true)==avatar:sub(1,20))
    local _,slots=array(eq,80,qi,48,16,true);local packid=u(slots,12)
    if packid==0 or packid==0xffffffff then return nil,'no_backpack' end
    -- Backpack manager links its entity to the spawned drone unit reference.
    -- Derived from game.dll+4da5ed..4da647; fail closed until all identities match.
    local bp=root(0x276c318);local n=u(read(bp+0x10,4));assert(n<=256,'backpack bound')
    local ep,links=ptr(bp+0x38,true),ptr(bp+0x50,true)
    local drone_ref,pack
    for i=0,n-1 do
        local e=ptr(ep+i*8);local b=read(e,24)
        if u(b,8)==packid then
            if b:sub(1,8)~=PACK then return nil,'not_laser_backpack' end
            if bit.band(b:byte(21),3)~=1 then return nil,'pack_not_local' end
            ptr(ep+i*8,true);read(e,24,true)
            local link=read(links+i*8,8,true);drone_ref=u(link,4);pack=b;break
        end
    end
    if not drone_ref or drone_ref==0x7fff then return nil,'waiting_for_drone' end
    local at=root(0x276cad0);local ai=lookup(at+32,packid,8192)
    if not ai then return nil,'pack_not_attached' end
    assert(ai<4096,'attachment bound')
    local _,attachment=array(at,64,ai,48,8,true)
    if u(attachment,4)~=aid then return nil,'pack_holder_mismatch' end
    local tm,bm=root(0x276ca40),root(0x276c470)
    local th=read(tm+308,84);local cap,total,active=u(th),u(th,12),u(th,16)
    assert(active<=total and total<=cap and cap<=8192,'target registry bound')
    local entity_array,aim_array=ptr(tm+360,true),ptr(tm+376,true)
    local ent,entity,ti
    for i=0,active-1 do
        local p=ptr(entity_array+i*8);local b=read(p,24)
        if b:sub(1,8)==DRONE and u(b,16)==drone_ref then
            if bit.band(b:byte(21),3)~=1 then return nil,'drone_not_local' end
            ptr(entity_array+i*8,true);read(p,24,true);ent,entity,ti=b,p,i;break
        end
    end
    if not ent then return nil,'drone_not_targeting' end
    local id=u(ent,8);consistent(lookup(tm+336,id,16384)==ti)
    local behavior_start=#guards+1
    local bi=lookup(bm+64,id,32768);if not bi then return nil,'no_behavior' end
    assert(bi<u(read(bm+32,4)) and bi<16384,'behavior bound')
    consistent(ptr(ptr(bm+88,true)+bi*8,true)==entity)
    local ba,behavior=array(bm,96,bi,layout.behavior_stride or 496,160)
    assert(u(behavior)==(layout.behavior_id or 189),'unsupported drone behavior')
    local behavior_guards=scope(behavior_start,{
        {address=address(0x276c470),bytes=read(address(0x276c470),8)},
        {address=entity,bytes=ent:sub(1,20)},
        {address=ba,bytes=behavior:sub(1,4)},
        {address=ba+104,bytes=behavior:sub(105,108)}})
    local aim=read(aim_array+ti*208,32)
    local observer=u(behavior,104);assert(observer==id,'shared perception is not supported')
    local perception_start=#guards+1
    local perception=root(0x276c270);local pi=lookup(perception+48,observer,32768)
    if not pi then return nil,'no_perception' end
    assert(pi<16384,'perception bound')
    consistent(ptr(ptr(perception+72,true)+pi*8,true)==entity)
    local pa,data=array(perception,80,pi,0x13f8,0x13f8)
    local perception_guards=scope(perception_start,{{address=entity,bytes=ent:sub(1,20)}})
    local fc=u(data);assert(fc<=32,'faction-filter bound')
    local allowed_mask=0
    for i=0,fc-1 do
        local faction=u(data,8+i*8);assert(faction<32,'faction bit bound')
        allowed_mask=bit.bor(allowed_mask,bit.lshift(1,faction))
    end
    local faction=root(0x276c9c8)
    local faction_root_guard=guards[#guards]
    local origin=api.position and api.position(u(ent,12)) or nil
    local candidates={}
    local function candidate(off)
        local raw=data:sub(off+1,off+80);local target=u(raw);if target==0 then return end
        local flags,mask,score=u(raw,72),u(raw,76),f(raw,68)
        assert(score==score and math.abs(score)<100000,'invalid cached score')
        local address=pa+off+76
        local target_start=#guards+1
        local fi=lookup(faction+73808,target,32768)
        local identity
        if fi then
            assert(fi<16384,'faction entity bound')
            local e=ptr(ptr(faction+73832,true)+fi*8,true)
            identity=read(e,20,true);consistent(u(identity,8)==target)
        end
        local target_guards=scope(target_start,{faction_root_guard})
        local distance2,position
        local x,y,z=f(raw,4),f(raw,8),f(raw,12)
        if x==x and y==y and z==z and math.abs(x)<1000000 and math.abs(y)<1000000 and math.abs(z)<1000000 then
            position={x,y,z}
            if origin then distance2=(x-origin[1])^2+(y-origin[2])^2+(z-origin[3])^2 end
        end
        candidates[#candidates+1]={id=target,identity=identity,position=position,distance2=distance2,mask=raw:sub(77,80),address=address,
            eligible=identity~=nil and bit.band(flags,1)~=0 and bit.band(mask,allowed_mask)~=0 and score>0,
            valid=function()
                if not identity then return false end
                -- Restoration depends on this observer, slot and target identity,
                -- not unrelated equipment fields or other groups' changing counts.
                local ok=M.matches(api,perception_guards);if ok~=true then return ok end
                ok=M.matches(api,target_guards);if ok~=true then return ok end
                local current=api.read(pa+off,4);if not current then return nil end
                return current==raw:sub(1,4)
            end}
    end
    for _,group in ipairs({{0x310,0x318},{0x818,0x820},{0xd20,0xd28}}) do
        local count=u(data,group[1]);assert(count<=16,'candidate group bound')
        guards[#guards+1]={address=pa+group[1],bytes=data:sub(group[1]+1,group[1]+4)}
        for i=0,count-1 do candidate(group[2]+i*80) end
    end
    -- Native function 87f9a0 skips empty special entries using the +0x48 marker.
    for _,off in ipairs({0x1228,0x1278,0x12c8}) do if u(data,off+0x48)~=0 then candidate(off) end end
    local marked,marker_status
    if api.markers then marked,marker_status=api.markers(game,aid,candidates) end
    local clock=root(0x276c068);local now=tick(read(clock+24,8))
    local deadline=tick(behavior:sub(153,160))
    assert(now>0 and now<9007199254740991 and deadline<9007199254740991,'clock bound')
    local target=u(behavior,24);local node=u(behavior,8)
    return {key=avatar:sub(1,20)..pack:sub(1,20)..ent:sub(1,20),id=id,target=target,node=node,
        synced=target~=0 and u(aim)==target and behavior:byte(121)==1 and bit.band(u(behavior,96),1)~=0,
        marked=marked,marker_status=marker_status or 'unavailable',candidates=candidates,distance_available=origin~=nil,now_native=now,deadline=behavior:sub(153,160),deadline_value=deadline,deadline_address=ba+152,
        guards=guards,valid=function()return M.matches(api,behavior_guards)end,
        transition={{address=ba,bytes=behavior:sub(1,4)},{address=ba+8,bytes=behavior:sub(9,12)},
            {address=ba+24,bytes=behavior:sub(25,28)},
            {address=ba+96,bytes=behavior:sub(97,100)},{address=ba+120,bytes=behavior:sub(121,121)},
            {address=aim_array+ti*208,bytes=aim:sub(1,4)}}},'observing'
end
function M.read(api,game)
    local ok,s,reason=pcall(read_snapshot,api,game)
    if ok then return s,reason end
    if s==NOT_READY then return nil,'waiting_for_runtime' end
    if s==CHANGING then return nil,'waiting_for_consistent_snapshot' end
    error(s,0) -- unsupported layouts and failed bounds remain hard failures
end
return M
