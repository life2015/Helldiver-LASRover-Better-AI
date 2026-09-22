-- Optional, bounded read-only player marker lookup. Failure preserves normal targeting.
local ffi,bit=require('ffi'),require('bit')
local M={}
-- Native HUD update clears/recomputes these screen-state bits every frame.
-- 0x800 is a screen-space selection flag, not marker ownership or lifetime.
local function u(b,o)local v=ffi.new('uint32_t[1]');ffi.copy(v,b:sub(o+1),4);return tonumber(v[0])end
local function stable_flags(b)return bit.band(u(b,28),bit.bnot(0x1c00))end
local function f(b,o)local v=ffi.new('float[1]');ffi.copy(v,b:sub(o+1),4);return tonumber(v[0])end
local function timed(b)
    local limit,elapsed=f(b,16),f(b,20)
    return limit==limit and elapsed==elapsed and limit>0 and limit<math.huge and elapsed>=0 and elapsed<limit
end
local function read(api,game,owner,candidates)
    local config=api.layout and api.layout.markers
    if not config then return nil,'unsupported_layout' end
    local function bytes(a,n)local b=api.read(a,n);assert(b and #b==n,'unreadable');return b end
    for _,sig in ipairs(config.signatures)do
        local expected=sig[2]:gsub('..',function(x)return string.char(tonumber(x,16))end)
        assert(bytes(game+sig[1],#expected)==expected,'marker_signature')
    end
    local root=bytes(game+config.root,8);local manager=assert(api.pointer(root),'marker_root')
    local data=bytes(manager,16+128*88);local head,tail=u(data,8),u(data,12)
    assert(head<128 and tail<128,'marker_bounds')
    local chosen,offset,expired
    for n=0,(tail-head)%128-1 do
        local off=16+((head+n)%128)*88;local b=data:sub(off+1,off+88)
        if u(b,24)==owner then
            if timed(b) then chosen=b;offset=off
            elseif f(b,16)>0 and f(b,20)>=f(b,16) then expired=true end
        end
    end
    if not chosen then return nil,expired and 'expired' or 'none' end
    local kind,id=u(chosen,0),u(chosen,32)
    -- The latest local marker wins, including ground/friendly/item markers that clear priority.
    -- HUD types 5..8 can also label native hostile candidates (live build 25327279).
    -- This is a display category; hostility comes from the Rover candidate filter.
    if kind<1 or kind>8 or id==0 then return nil,'not_enemy' end
    local candidate
    for _,c in ipairs(candidates)do
        if c.id==id and (not candidate or c.eligible or not candidate.identity and c.identity) then
            candidate=c;if c.eligible then break end
        end
    end
    local header=data:sub(9,16)
    local function valid()
        local ok,result=pcall(function()
            if bytes(game+config.root,8)~=root or bytes(manager+8,8)~=header then return false end
            local b=bytes(manager+offset,88)
            -- Screen flags, position and elapsed time may change without cancelling a mark.
            -- Keep identity, non-screen flags, duration and lifetime checks intact.
            return b:sub(1,4)==chosen:sub(1,4) and b:sub(17,20)==chosen:sub(17,20)
                and u(b,24)==u(chosen,24) and u(b,32)==id and stable_flags(b)==stable_flags(chosen)
                and timed(b) and f(b,20)>=f(chosen,20)
        end)
        return ok and result==true
    end
    if not valid() then return nil,'changed' end
    -- An observation describes the live ping, never permission to select it.
    -- Keep it separate from the strictly eligible mark used for write requests.
    local observation={id=id,identity=candidate and candidate.identity,
        reason=candidate and (candidate.eligibility_reason or (candidate.eligible and 'eligible' or 'ineligible')) or 'missing',
        token=root..tostring(offset)..chosen:sub(1,4)..chosen:sub(17,20)..chosen:sub(25,28)..chosen:sub(33,36)..tostring(stable_flags(chosen)),
        elapsed=f(chosen,20),remaining=f(chosen,16)-f(chosen,20)}
    if candidate and candidate.identity and candidate.valid()~=true then return nil,'changed' end
    if not candidate or not candidate.eligible or not candidate.identity then return nil,'not_eligible',observation end
    local function request_valid()
        local ok,result=pcall(function()return valid() and candidate.valid()==true end)
        return ok and result==true
    end
    return {id=id,identity=candidate.identity,valid=request_valid},'eligible',observation
end
function M.read(...)
    local ok,mark,status,observation=pcall(read,...)
    if not ok then return nil,'unavailable' end
    return mark,status,observation
end
return M
