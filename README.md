![Banner](images/banner_wide.png)

# Sneak! - Sneak is good now.

An OpenMW mod that makes sneak mechanics playable. Sneak detection is now a visually displayed gradual progress. It loosely follows original sneak detection formulas in a sense that whichever creature was difficult to sneak by in the original will also be difficult to sneak by now. There are many small tweaks to how those formulas work and how they translate into a gradual detection progress, aimed at providing a more fun gameplay experience. This mod attempts to strike a balance between gamified mechanics and """realism""".

Click on a preview below to watch a release trailer.
[![Release Trailer](https://img.youtube.com/vi/e-O7qEIHpNw/0.jpg)](https://www.youtube.com/watch?v=e-O7qEIHpNw)

Features:

- Gradual visual detection progress instead of instant detection.

- Weapon skill is boosted by 50% while in sneak stance.

- Slight increase of sneak speed (it's 90% of the walk speed now). Due to how sneak animations and footstep sounds work it *might* feel like sneaking is faster than walking now - it is not, footstep sounds are just more frequent in sneaking stance.

- Contrary to vanilla boots don't affect your sneak chances. All in all your equipment has no effect on your sneak.

- Mod works by kicking you out of a sneaking stance when you are detected, so the engine can take over the NPC agression/attack logic, so dont be surprised when you are suddenly forced out of a sneaking stance - this is intended.


## Recommendations

Try [Dynamic Reticle](https://www.nexusmods.com/morrowind/mods/56584) they go well together, as it adds some subtle sneak visual effects.

There are also few sneak-related mods out there such as [Burglary Overhaul](https://www.nexusmods.com/morrowind/mods/56965) and [SHOP](https://www.nexusmods.com/morrowind/mods/57747), both mod authors were very helpful and Sneak! will eventually seamlessly work with both of them (but probably it doesnt right now). I haven't personally tested them together myself, but wanted to put them on your radar!

## Installation

NO MATTER WHICH INSTALLATION APPROACH YOU USE you need to **enable `SneakIsGoodNow.omwscripts` and `SneakIsGoodNow.omwaddon` files** inside the `ContentFiles` tab of OpenMW launcher. You are done, have fun!

AND be sure to **enable `Toggle Sneak`** - this option makes it so that you don't have to hold sneak button to sneak, this mod will not work properly without it. Don't remember where that setting is and I'm too lazy to look it up, it's somewhere in the launcher or in game settings.

Install as any other OpenMW mod, if you installed an OpenMW mod before - you know what to do, information below is for those who are new to OpenMW modding.

I'm usually lazy in describing all the ways one can install an OpenMW mod, but this time I'll do it justice! So if you are new to OpenMW mods - there are 3 distinct ways to install any OpenMW mod, here they are from least to most complicated:

Use **ONE OF these methods**

**A) Use Mod Organiser 2 with an OpenMW addon** - it automates installation of OpenMW mods and has Nexus integration - either drag and drop a downloaded mod archive into it or, if you are downloading from Nexus - MO2 will handle the mod download for you as soon as you press the download button. Probably you also need to click on the mod in MO2 after download is done and click install? I haven't used MO2 for a bit since I'm on Linux now, but I highly recommend MO2.

**B) OR Install using an OpenMW launcher** - also quite a convenient method that's easy to use for mods that don't have a BAIN/FOMOD installer (a special option-selection tool bundled with some mods, this one does not use it). First extract the mod archive somewhere so it's now a single mod folder (not a `scripts` folder, but a mod folder containing a `scripts` folder), then in the OpenMW launcher go to `Data Directories` tab and use `Append` button to add the extracted mod folder to a list of Data Directories.

**C) OR Take the contents of this mod's archive and drop them into** a `Data Files` folder inside your Morrowind installation (not OpenMW!).

## For Developers

**Sneak!** provides a minimalist interface exposing current player detection state. You can read about how to use script interfaces [here](https://openmw-zack.readthedocs.io/en/lua_global_new/reference/lua-scripting/overview.html#script-interfaces).

Note that Sneak! mostly only works while player is sneaking, it does not do any detection or line-of-sight checks when player is not sneaking.

Interface is available only on player scripts, it exposes a player detection state:

```Lua
local ps = I.SneakIsGoodNow.playerState
-- Available properties:
ps.isSneaking -- boolean
ps.detectedByNonAggro -- boolean
ps.isMoving -- boolean
ps.isInvisible -- boolean
ps.chameleon -- 1 - 100 number - strength of chameleon effect on a player

```

Since the mod works by kicking you out of sneak state when you are detected - you can consider player detected when `ps.isSneaking` is false. Unless you are detected only by non-aggressive creatures (player is not booted out of sneak then), then `isSneaking` will still be true while `detectedByNonAggro` will be true.

Furthermore there is a table with few properties that you can modify to affect how detectable player is:

```Lua
local extraMods = I.SneakIsGoodNow.playerState.extraMods
extraMods.elusivenessMod = 1.0 -- default value
extraMods.elusivenessConst = 0 -- default value
```

`elusivenessMod` is more or less a general modifier of how elusive player is, it's applied before chameleon; adds a flat bonus to overall elusiveness.

`elusivenessConst` is a flat bonus that will be added to player's elusiveness score.

If multiple mods will be altering these values - obviously last one will win, since I don't have a system in place for multiple mods to introduce their own separate modifiers, but it's a fairly niche use case so I'm sure it will be fiiiiiine.

I also haven't tested this API at all, but I'm sure it will be fiiiiiine ;)

## Appreciation

Thanks to [Blurpandra](https://www.nexusmods.com/profile/blurpandra/mods?gameId=100) (Erin Pentecost) for sharing his sneak detection code used in his Burglary Overhaul mod. To [fallchildren](https://gitlab.com/fallchildren) and [choirbug](https://gitlab.com/olyukha) for inspiring me to try this janky aproach to a sneak overhaul - they are currently working on a "Dark Project" mod (you can find it in OpenMW discor in mods section) which is a more ambitious stealth overhaul inspired by Thief series mechanics. 

Check their mods, especially the [footstep sound mod](https://gitlab.com/fallchildren/openmw-footsteps), choirbug made a whole bunch of very immersive amazing sounds for it (to hear them you will need to change the sound backend in the mod's settings).

And also to the entirety of the OpenMW community, my inspiration almost always comes from interacting with OpenMW discord, sometimes we have some differences admittedly, but hey, who doesn't? Love you all :3

## AI use discalimer

To be honest, nowadays everyone seem to be using LLMs to some capacity, so leaving disclaimers like that becomes pointless, but sometimes I still do since I know some people are bothered by the whole AI thing (not without a reason) and will appreciate a disclaimer.

So I mostly used Qwen to help with some coding tasks and with spelling and grammar in this readme, as well as ChatGPT for a research into creature aggression OpenMW source code and porting that to Lua.