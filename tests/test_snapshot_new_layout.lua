local profile=assert(loadfile(ROOT..'/src/layout.lua'))().profiles[1]
assert(profile.behavior_id==190 and profile.behavior_stride==504 and profile.owner_map==0xf22ec8 and profile.owner_entities==0xf32f18)
SNAPSHOT_LAYOUT=profile
local result=assert(loadfile(ROOT..'/tests/test_snapshot.lua'))()
SNAPSHOT_LAYOUT=nil
return result:gsub('snapshot tests','new-layout snapshot tests')
