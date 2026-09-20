-- HD2-Addon: mods/retrox/rover_fire_spread
-- Keep this resource plaintext: v15 reads the first-line declaration.
local loader=rawget(_G,'CowboyBingusModLoader')
assert(loader and loader.api>=1 and loader.version>=16,'Bingus Shared Loader v15 or newer is required')
local implementation='mods/retrox/rover_fire_spread_impl'
assert(stingray.Application.can_get('lua',implementation),'Rover implementation resource missing')
return require(implementation)
