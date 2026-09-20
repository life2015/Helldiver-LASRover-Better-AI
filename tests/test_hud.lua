local H=assert(loadfile(ROOT..'/src/hud.lua'))()
local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
test('HUD explains adjacent selection and close threat priority including the retained request',function()
    local c={active_request=true,active_ranking='nearest',active_basis='previous_target',active_target=2}
    assert(H.model({},c,1).lines[2]=='Selecting: adjacent target')
    c.active_basis='near_rover';assert(H.model({},c,1).lines[2]=='Selecting: near Rover (15m)')
    c.active_request=false;c.last_request_at=1;c.current_key='a';c.last_request_key='a'
    c.last_request_basis='near_rover';c.last_request_ranking='nearest';c.last_request_target=2
    local m=H.model({},c,1.5)
    assert(m.lines[3]:find('near Rover (15m)',1,true) and m.lines[5]:find('2 (last)',1,true))
end)
test('HUD differentiates mod nearest and filtered native selection',function()
    local c={active_request=true,active_ranking='nearest'}
    assert(H.model({},c,1).lines[1]=='ROVER | MOD: NEAREST')
    c.active_ranking='native_distance_unavailable'
    assert(H.model({},c,1).lines[1]=='ROVER | MOD: NATIVE PICK')
end)
test('HUD does not mistake an old plan or request for current intervention',function()
    local c={decision='attack_window',ranking='nearest',last_request_ranking='nearest',last_request_at=1,current_key='a',last_request_key='a'}
    local m=H.model({},c,1.5)
    assert(m.lines[1]=='ROVER | NATIVE' and m.lines[3]:find('0.5s ago',1,true))
    assert(H.model({},c,3.1).lines[3]=='Last request: --')
    assert(H.model({},c,.5).lines[3]=='Last request: --')
end)
test('HUD shows waiting and prioritizes stopped over an outstanding lease',function()
    assert(H.model({},nil,0).lines[1]=='ROVER | WAITING')
    local m=H.model({stopped=true},{active_request=true,cleanup_pending=true},0)
    assert(m.lines[1]=='ROVER | STOPPED' and m.lines[2]:find('restoration pending',1,true))
end)
local function fixture(baseline)
    local t,reads,creates,destroys,updates=0,0,0,0,0
    local main,overlay={},{};local worlds={main,overlay};local width,height=1920,1080
    local rendered={};local badfont,baddraw=false,false
    local function unhex(s)local b=s:gsub('..',function(v)return string.char(tonumber(v,16))end);return b:reverse()end
    local data={
        [1000+0x2ac7058]='pointer!', [2000+24]=unhex('9f85b87d3ff20cbb'),
        [1000+0x2a750d8]=unhex('b56d2abac5d17df2'),[1000+0x2a75d58]=unhex('d1ebb991c79f934b')}
    local api={time=function()return t end,pointer=function(b)assert(b=='pointer!');return 2000 end,
        read=function(a,n)reads=reads+1;assert(n==8);if badfont then return nil end;return data[a]end}
    local e={Application={},World={},Gui={},IdString64={},Material={},Vector2={}}
    setmetatable(e.Vector2,{__call=function(_,x,y)return {x=x,y=y}end});e.Vector2.x=function(v)return v.x end
    e.Vector3=function(x,y,z)return {x=x,y=y,z=z}end;e.Color=function(a,r,g,b)return {a,r,g,b}end
    e.IdString64.from_hex=function(v)assert(#v==16);return v end
    e.Application.worlds=function()return worlds end;e.Application.main_world=function()return main end
    e.World.create_screen_gui=function(w)assert(w~=main);creates=creates+1;return {}end
    e.World.destroy_gui=function(w,g)assert(g);destroys=destroys+1 end
    e.Gui.resolution=function()return width,height end
    e.Gui.material=function(g,m)assert(m=='9f85b87d3ff20cbb');return {}end
    e.Material.set_scalar=function()end;e.Material.set_vector2=function()end;e.Material.set_vector4=function()end
    e.Material.set_texture=function(_,_,v)assert(v=='d1ebb991c79f934b')end
    e.Gui.rect=function(g,p,s)
        assert(p.x>=0 and p.y+s.y<=height and p.x+s.x<=width)
        assert(math.abs(p.x+s.x/2-width/2)<.01,'HUD must be centered')
        assert(height-p.y-s.y<=height*.03,'HUD must stay near the top edge')
        return 1
    end
    e.Gui.update_rect=function(g,id,p,s)return e.Gui.rect(g,p,s)end
    e.Gui.text_extents=function(g,text,font,size)assert(font=='b56d2abac5d17df2');return {x=0},{x=#text*size*.6}end
    local function text(g,txt,font,size,mat,p)
        if baddraw then error('draw unavailable')end
        assert(p.x>=0 and p.y>=0 and p.y<=height and p.x+#txt*size*.6<=width+1)
        rendered[#rendered+1]=txt;return #rendered
    end
    e.Gui.text=text;e.Gui.update_text=function(g,id,...)updates=updates+1;return text(g,...)end
    local s=H.new(e,api,1000,baseline~=false);local state={}
    return {surface=s,state=state,api=api,data=data,engine=e,rendered=rendered,
        step=function(now,c)t=now;s:frame(state,c or {decision='attack_window'})end,
        font_failure=function(value)badfont=value end,draw_failure=function(value)baddraw=value end,
        worlds=function(value)worlds=value end,viewport=function(w,h)width,height=w,h end,
        stats=function()return reads,creates,destroys,updates end,main=main,overlay=overlay}
end
test('HUD draws in a UI world and reuses retained primitives across updates',function()
    local f=fixture();f.step(0);assert(f.state.hud_status=='visible' and #f.rendered==5)
    f.step(.15,{active_request=true,active_ranking='nearest'})
    local _,creates,_,updates=f.stats();assert(creates==1 and updates==5)
    f.surface:clear();local _,_,destroyed=f.stats();assert(destroyed==1)
end)
test('HUD read and draw cadence is bounded',function()
    local f=fixture();f.step(0);local n=f.stats();f.step(.02);f.step(.05);assert(f.stats()==n)
end)
test('HUD font failure is isolated and retries after two seconds',function()
    local f=fixture();f.font_failure(true);f.step(0);assert(f.state.hud_status=='unavailable')
    local n=f.stats();f.font_failure(false);f.step(1);assert(f.stats()==n)
    f.step(2.1);assert(f.state.hud_status=='visible')
end)
test('HUD drawing failure clears owned GUI and can recover',function()
    local f=fixture();f.draw_failure(true);f.step(0);local _,a,b=f.stats()
    assert(a==1 and b==1 and f.state.hud_status=='unavailable')
    f.draw_failure(false);f.step(2.1);assert(f.state.hud_status=='visible')
end)
test('HUD never destroys a world that the engine already removed',function()
    local f=fixture();f.step(0);f.worlds({f.main});f.step(.2)
    local _,_,destroyed=f.stats();assert(destroyed==0 and f.state.hud_status=='waiting_for_ui')
    f.worlds({f.main,{}});f.step(.4);local _,created=f.stats();assert(created==2)
end)
test('HUD rebinds when another live UI world replaces the selected world',function()
    local f=fixture();f.step(0);f.worlds({f.main,{},f.overlay});f.step(.2)
    local _,created,destroyed=f.stats();assert(created==2 and destroyed==1)
end)
test('HUD fits supported aspect ratios and viewport changes',function()
    local f=fixture()
    for i,v in ipairs({{1280,720},{1920,1080},{3440,1440},{5120,1440},{1280,1024}})do
        f.viewport(unpack(v));f.step(i);assert(f.state.hud_status=='visible')
    end
end)
test('unverified font layout hides only HUD without reading font offsets',function()
    local f=fixture(false);f.step(0);assert(f.stats()==0 and f.state.hud_status=='unverified_font_layout')
end)
test('font mapping follows the native locale and rejects zero or changing data',function()
    local f=fixture();local font=H.font(f.api,1000);assert(font.font=='b56d2abac5d17df2')
    f.data[1000+0x2a750d8]=string.rep('\0',8);assert(not pcall(H.font,f.api,1000))
    f.data[1000+0x2a750d8]='12345678'
    local read,n=f.api.read,0
    f.api.read=function(a,s)if a==1000+0x2ac7058 then n=n+1;if n>1 then return 'changed!'end end;return read(a,s)end
    assert(not pcall(H.font,f.api,1000))
end)
test('locked ID is distinct from requested next ID and follows actual target changes',function()
    local c={target=123,target_synced=true,active_request=true,active_ranking='nearest',active_target=456}
    assert(H.model({},c,0).lines[5]=='Locked: 123 | Next: 456')
    c.target=456;c.active_request=false;c.active_target=nil
    assert(H.model({},c,0).lines[5]=='Locked: 456 | Next: --')
end)
test('stopped and unsynchronized targets do not display stale locked IDs',function()
    local c={target=123,target_synced=false,last_request_target=456}
    assert(H.model({},c,0).lines[5]=='Locked: -- | Next: --')
    c.target_synced=true
    assert(H.model({stopped=true},c,0).lines[5]=='Locked: -- | Next: --')
    c.target=0;assert(H.model({},c,0).lines[5]=='Locked: -- | Next: --')
end)
test('distance fallback shows native choice instead of inventing a next ID',function()
    local c={target=123,target_synced=true,active_request=true,active_ranking='native_distance_unavailable',last_request_target=456}
    assert(H.model({},c,0).lines[5]=='Locked: 123 | Next: native')
end)
test('HUD reports a timeout request and the one-entry recent limit',function()
    local c={active_request=true,active_ranking='nearest',active_reason='lock_timeout',history_count=1,history_limit=1,
        last_request_at=0,last_request_reason='lock_timeout',last_request_ranking='nearest',current_key='a',last_request_key='a'}
    local m=H.model({},c,.2)
    assert(m.lines[2]=='no attack 1.5s - reselecting' and m.lines[3]:find('timeout',1,true))
    assert(m.lines[4]:find('Recent 1/1',1,true))
    c.active_request=false;c.decision='no_attack_window'
    assert(H.model({},c,.3).lines[2]=='no attack; waiting 1.5s')
end)
local function recent_request()
    return {decision='request_finished',target=456,target_synced=true,current_key='a',last_request_key='a',
        last_request_at=1,last_request_target=456,last_request_ranking='nearest'}
end
test('HUD retains the last requested ID for two seconds without showing active intervention',function()
    local c=recent_request();local m=H.model({},c,1.1)
    assert(m.lines[5]=='Locked: 456 | Next: 456 (last)' and m.lines[1]=='ROVER | NATIVE')
    assert(H.model({},c,2.99).lines[5]:find('(last)',1,true))
    assert(H.model({},c,3).lines[5]=='Locked: 456 | Next: --')
    assert(H.model({},c,.9).lines[5]=='Locked: 456 | Next: --')
end)
test('last requested ID disappears on context loss replacement or shutdown',function()
    local c=recent_request();c.current_key=nil
    assert(not H.model({},c,1.1).lines[5]:find('(last)',1,true))
    c.current_key='b';assert(H.model({},c,1.1).lines[3]=='Last request: --')
    c.current_key='a';assert(H.model({stopped=true},c,1.1).lines[5]=='Locked: -- | Next: --')
end)
test('active request takes precedence over retained ID and native fallback is explicit',function()
    local c=recent_request();c.active_request=true;c.active_ranking='nearest';c.active_target=789
    assert(H.model({},c,1.1).lines[5]=='Locked: 456 | Next: 789')
    c.active_request=false;c.last_request_ranking='native_distance_unavailable';c.last_request_target=0
    assert(H.model({},c,1.1).lines[5]=='Locked: 456 | Next: native (last)')
end)
test('GUI still renders a short request ID when both endpoints fall between refreshes',function()
    local f=fixture();f.step(1)
    local c=recent_request();c.last_request_at=1.02
    f.step(1.15,c)
    assert(f.rendered[#f.rendered]=='Locked: 456 | Next: 456 (last)')
end)
test('both mod colours persist half a second after release with an explicit last label',function()
    local c=recent_request();c.last_request_finished_at=1.25
    for _,v in ipairs({{'nearest','NEAREST','good'},{'native_distance_unavailable','NATIVE PICK','partial'}})do
        c.last_request_ranking=v[1]
        local m=H.model({},c,1.74)
        assert(m.lines[1]=='ROVER | MOD: '..v[2]..' (last)' and m.tone==v[3])
        assert(m.lines[2]=='Request ended - native control' and not c.active_request)
        assert(H.model({},c,1.75).lines[1]=='ROVER | NATIVE')
    end
end)
test('new active requests override held colour and stopped or missing contexts hide it',function()
    local c=recent_request();c.last_request_finished_at=1.1
    c.active_request=true;c.active_ranking='native_distance_unavailable'
    assert(H.model({},c,1.2).lines[1]=='ROVER | MOD: NATIVE PICK')
    c.active_request=false
    assert(H.model({stopped=true},c,1.2).lines[1]=='ROVER | STOPPED')
    c.current_key=nil;assert(H.model({},c,1.2).lines[1]=='ROVER | NATIVE')
    c.current_key='b';assert(H.model({},c,1.2).lines[1]=='ROVER | NATIVE')
    c.current_key='a';assert(H.model({},c,1.05).lines[1]=='ROVER | NATIVE')
end)
test('GUI shows held colour even if the complete active request was between frames',function()
    local f=fixture();f.step(1)
    local c=recent_request();c.last_request_at=1.02;c.last_request_finished_at=1.07
    f.step(1.15,c)
    assert(f.rendered[#f.rendered-4]=='ROVER | MOD: NEAREST (last)')
    f.step(1.6,c);assert(f.rendered[#f.rendered-4]=='ROVER | NATIVE')
end)
test('watchdog HUD distinguishes maximum lock duration from no attack timeout',function()
    local c={active_request=true,active_ranking='nearest',active_reason='lock_max_duration',active_basis='timeout_rover',
        last_request_reason='lock_max_duration',last_request_at=0,current_key='a',last_request_key='a'}
    local m=H.model({},c,.2)
    assert(m.lines[2]=='lock 1.5s - reselecting' and m.lines[3]:find('max lock /',1,true))
end)
return tostring(passed)..' HUD tests passed'
