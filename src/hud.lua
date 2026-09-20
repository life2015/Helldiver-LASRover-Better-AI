-- Optional retained GUI. Drawing failures never stop the targeting controller.
-- Font/material setup follows KnowYourConstellation's native body-font panel.
local M={status_hold_seconds=0.5}
local basis_labels={previous_target='adjacent target',near_rover='near Rover (15m)',rover_fallback='nearest Rover',timeout_rover='nearest Rover'}
local reasons={attack_window='attack window',no_attack_window='no attack; waiting 1.5s',no_alternative='no other target',tracking='tracking / aiming',
    retry_delay='retry delay',request_finished='request released',precondition_changed='data changed; retry',
    no_writes='no change needed',diagnostic='diagnostic only'}
function M.model(state,c,now)
    c=c or {}
    local age=c.last_request_at and now-c.last_request_at
    local same_context=not state.stopped and not c.stopped and c.current_key~=nil
        and c.current_key==c.last_request_key and age and age>=0
    local released_age=c.last_request_finished_at and now-c.last_request_finished_at
    local held=same_context and released_age and released_age>=0 and released_age<M.status_hold_seconds
    local title,tone,detail='ROVER | WAITING','neutral','waiting for local laser Rover'
    if state.stopped or c.stopped then
        title='ROVER | STOPPED';tone='error'
        detail=c.cleanup_pending and 'restoration pending - see log' or 'Mod inactive - see log'
    elseif c.active_request then
        if c.active_ranking=='nearest' then title='ROVER | MOD: NEAREST';tone='good'
        else title='ROVER | MOD: NATIVE PICK';tone='partial' end
        if c.active_reason=='lock_timeout' then detail='no attack 1.5s - reselecting'
        elseif c.active_reason=='lock_max_duration' then detail='lock 1.5s - reselecting'
        else detail=basis_labels[c.active_basis] and 'Selecting: '..basis_labels[c.active_basis] or 'rotation request active' end
    elseif held and (c.last_request_ranking=='nearest' or c.last_request_ranking=='native_distance_unavailable') then
        if c.last_request_ranking=='nearest' then title='ROVER | MOD: NEAREST (last)';tone='good'
        else title='ROVER | MOD: NATIVE PICK (last)';tone='partial' end
        detail='Request ended - native control'
    elseif reasons[c.decision] then
        title='ROVER | NATIVE';detail=reasons[c.decision]
    end
    local last='Last request: --'
    local recent=same_context and age<2
    if recent then
        local pick=c.last_request_ranking=='nearest' and 'nearest' or 'native pick'
        pick=basis_labels[c.last_request_basis] or pick
        last=string.format('Last: %s%s | %.1fs ago',c.last_request_reason=='lock_timeout' and 'timeout / ' or c.last_request_reason=='lock_max_duration' and 'max lock / ' or '',pick,age)
    end
    local counts=string.format('Requests %d | Changes %d | Recent %d/%d',c.requests or 0,c.rotations or 0,c.history_count or 0,c.history_limit or 1)
    local locked,next_id='--','--'
    if not state.stopped and not c.stopped then
        if c.target_synced and c.target and c.target>0 then locked=string.format('%d',c.target)end
        if c.active_request then
            if c.active_ranking=='nearest' and c.active_target and c.active_target>0 then next_id=string.format('%d',c.active_target)
            elseif c.active_ranking=='native_distance_unavailable' then next_id='native' end
        elseif recent then
            if c.last_request_ranking=='nearest' and c.last_request_target and c.last_request_target>0 then
                next_id=string.format('%d (last)',c.last_request_target)
            elseif c.last_request_ranking=='native_distance_unavailable' then next_id='native (last)' end
        end
    end
    return {tone=tone,lines={title,detail,last,counts,'Locked: '..locked..' | Next: '..next_id}}
end

function M.font(api,game)
    local function bytes(address)
        local b=api.read(address,8);assert(b and #b==8,'Font data not ready');return b
    end
    local function hash(b)
        local out={};for i=8,1,-1 do out[#out+1]=string.format('%02x',b:byte(i))end
        local result=table.concat(out);assert(result~='0000000000000000','Font not ready');return result
    end
    local pointer_bytes=bytes(game+0x2ac7058)
    local owner=assert(api.pointer(pointer_bytes),'Font material not ready')
    local font_bytes,material_bytes,atlas_bytes=bytes(game+0x2a750d8),bytes(owner+24),bytes(game+0x2a75d58)
    assert(bytes(game+0x2ac7058)==pointer_bytes and bytes(game+0x2a750d8)==font_bytes
        and bytes(owner+24)==material_bytes and bytes(game+0x2a75d58)==atlas_bytes,'Font changed during read')
    return {font=hash(font_bytes),material=hash(material_bytes),atlas=hash(atlas_bytes)}
end

function M.new(engine,api,game,baseline_font_layout)
    local self={};local gui,world,text_ids,rect_id,signature,font_signature
    local last_draw,retry_at
    local function contains(list,item)
        for _,v in ipairs(list or {})do if v==item then return true end end;return false
    end
    function self:clear()
        local old_gui,old_world=gui,world
        gui,world,text_ids,rect_id,signature,font_signature=nil,nil,{},nil,nil,nil
        if old_gui and contains(engine.Application.worlds(),old_world) then engine.World.destroy_gui(old_world,old_gui)end
    end
    function self:frame(state,c)
        local now=api.time()
        if last_draw and now>=last_draw and now-last_draw<0.1 then return end
        if retry_at and now>=last_draw and now<retry_at then return end
        last_draw=now
        -- The controller may try unknown builds. GUI font offsets are separately
        -- baseline-locked; hiding the HUD must not disable gameplay on those builds.
        if not baseline_font_layout then state.hud_status='unverified_font_layout';return end
        local ok,why=pcall(function()
            engine=engine or rawget(_G,'stingray')
            assert(engine and engine.Application and engine.World and engine.Gui,'GUI API unavailable')
            local App,World,Gui=engine.Application,engine.World,engine.Gui
            local worlds=assert(App.worlds(),'UI worlds unavailable');local main=App.main_world();local target
            for _,w in ipairs(worlds)do if w~=main then target=w;break end end
            if not target then self:clear();state.hud_status='waiting_for_ui';return end
            if world and world~=target then self:clear()end
            local f=M.font(api,game)
            local fs=f.font..f.material..f.atlas
            if gui and font_signature~=fs then self:clear()end
            local font=engine.IdString64.from_hex(f.font)
            local material=engine.IdString64.from_hex(f.material)
            if not gui then
                gui=assert(World.create_screen_gui(target,'scale',1,1),'Could not create Rover HUD')
                world=target;text_ids={}
                local ink=assert(Gui.material(gui,material),'Font material unavailable')
                local function slot(hash)return engine.IdString64.from_hex(hash..'00000000')end
                for _,hash in ipairs({'8035c266','5e8455fe','309e7783','82b803a8'})do engine.Material.set_scalar(ink,slot(hash),0)end
                engine.Material.set_vector2(ink,slot('e13777ce'),engine.Vector2(1,-1))
                engine.Material.set_vector4(ink,slot('7701209e'),engine.Color(0,0,0,0))
                engine.Material.set_texture(ink,slot('88bac99b'),engine.IdString64.from_hex(f.atlas))
                font_signature=fs
            end
            local width,height=Gui.resolution()
            assert(width>=640 and height>=480 and width<=16384 and height<=16384,'Unsupported HUD viewport')
            local scale=math.min(width/1920,height/1080)
            local w,h=410*scale,129*scale
            local x,y=(width-w)/2,height-24*scale-h
            local model=M.model(state,c,now)
            local sig=table.concat(model.lines,'|')..model.tone..width..':'..height
            if sig~=signature then
                local bg=engine.Color(185,12,18,24)
                local pos,size=engine.Vector3(x,y,900),engine.Vector2(w,h)
                if rect_id then Gui.update_rect(gui,rect_id,pos,size,bg)else rect_id=assert(Gui.rect(gui,pos,size,bg))end
                local tones={good={90,230,130},partial={255,205,80},error={255,100,100},neutral={205,215,225}}
                for i,text in ipairs(model.lines)do
                    local rgb=i==1 and tones[model.tone] or {210,215,220}
                    local colour=engine.Color(255,unpack(rgb));local size=(i==1 and 20 or 16)*scale
                    local lo,hi=Gui.text_extents(gui,text,font,size)
                    local measured=engine.Vector2.x(hi)-engine.Vector2.x(lo)
                    assert(measured>=0 and measured<100000,'Invalid text metrics')
                    if measured>w-24*scale then size=size*(w-24*scale)/measured end
                    local p=engine.Vector3(x+12*scale,y+h-(24+(i-1)*23)*scale,901)
                    if text_ids[i] then Gui.update_text(gui,text_ids[i],text,font,size,material,p,colour)
                    else text_ids[i]=assert(Gui.text(gui,text,font,size,material,p,colour))end
                end
                signature=sig
            end
            state.hud_status='visible';state.hud_error=nil
        end)
        if not ok then
            pcall(function()self:clear()end)
            state.hud_status='unavailable';state.hud_error=tostring(why);retry_at=now+2
        else retry_at=nil end
    end
    return self
end
return M
