-- Mod version, published to Nexus by .github/workflows/nexus-release.yml (the first `version = ...` in this file)
local VERSION = "1.1"

local mp = "scripts/MaxYari/SneakIsGoodNow/"
DebugLevel = 0

local I = require("openmw.interfaces")
local types = require("openmw.types")
local nearby = require("openmw.nearby")
local core = require("openmw.core")
local omwself = require("openmw.self")
local util = require("openmw.util")

local DEFS = require(mp .. 'utils/sneak_defs')
local gutils = require(mp .. 'utils/gutils')
local itemutil = require(mp .. "utils/item_utils")
local detection = require(mp .. "detection_math")
local aggression = require(mp .. "aggression_math")
local DetectionMarker = require(mp .. "Sneak_ui_elements")
local reticle = require(mp .. "stealth_reticle")
local lean = require(mp .. "lean")
local settings = require(mp .. 'settings').settings
local skillSettings = require(mp .. 'settings').skillSettings
local uiSettings = require(mp .. 'settings').uiSettings
local selfActor = gutils.Actor:new(omwself)

-- Max Yari's Script Services (MSS) is a required dependency: checked once, when this script loads.
if not core.contentFiles.has("MaxYariScriptServices.omwscripts") then
    print("[Sneak Is Good Now] ERROR: critical dependency is missing: Max Yari's Script Services (MSS). Please install it.")
    require('openmw.ui').showMessage("Sneak Is Good Now: Critical dependency is missing, please install Max Yari's Script Services (MSS)")
end

gutils.print("Sneak! E-N-G-A-G-E-D", 0)

local sneakCheckPeriod = 0.33 -- seconds between sneak checks per actor
local followTargetsCheckPeriod = 2.0 -- seconds between follow target updates per actor
local losCheckPeriod = 0.2
local knockoutCheckPeriod = 0.25

-- Detection meter
local minDetectDur = 0.6            -- average seconds to be seen at a 0% chance to stay hidden
local maxDetectDur = 15             -- average seconds to be seen at speedLimitChance (the median lands near 9 s)
local speedLimitChance = 90         -- above this chance to stay hidden the fill speeds stop changing
local fillJitter = 1.0              -- how far one roll pushes the fill speed above or below the average
local successRollsBeforeDrain = 3   -- passed rolls in a row before the meter starts draining
local inSightDrainRate = 0.10       -- per second, while in sight after successRollsBeforeDrain passed rolls
local outOfSightDrainRate = 0.25    -- per second, while out of sight

-- "ps" stands for "Player State"
local ps = {
    isSneaking = false,
    detectedByNonAggro = false,
    hostileInSight = false,
    isMoving = false,
    isInvisible = false,
    chameleon = 0
}

local extraMods = {
    elusivenessMod = 1.0,
    elusivenessConst = 0
}

local modifiedSkill = nil
local skillMod = 0
local lastCell = nil

local nearbyCheckTimer = 0
local nearbyCheckPeriod = 0.2

local effectsCheckPeriod = 0.2

local observerActorStatuses = {}
local persistantActorStatuses = {}

local interface = {
    version = 1.0,
    observerActorStatuses = observerActorStatuses,
    playerState = ps,
    extraMods = extraMods
}

    
-- "ast" stands for "Actor's Status"
local function getAst(actor)
    local ast = persistantActorStatuses[actor.id]
    if not ast then
        -- gutils.print("Creating new persistant actor status for " .. actor.recordId)
        ast = {
            actor = actor,
            gactor = gutils.Actor:new(actor),
            cell = actor.cell,
            distance = 250,
            progress = 0.0,
            successRolls = 0
        }

        persistantActorStatuses[actor.id] = ast
    end
    return ast
end

local function getAstIfExists(actor)
    if not persistantActorStatuses[actor.id] then return nil end
    return getAst(actor)
end




-- Meter fill speeds (per second) after a failed and after a passed roll.
-- The chance to stay hidden sets the average speed, so the meter fills in about detectDur seconds,
-- and each roll only pushes the speed above (failed) or below (passed) that average. Passed rolls
-- in a row drain the meter instead, and that drain is already counted into the average.
-- Above speedLimitChance the speeds stop changing: drain streaks take over and the time to be seen
-- climbs on its own (about 29 s at 95%, never at 100% where no roll can fail).
local function getFillSpeeds(sneakChance)
    local p = math.min(sneakChance or 0, speedLimitChance) / 100
    local detectDur = minDetectDur + (maxDetectDur - minDetectDur) * (p * 100 / speedLimitChance) ^ 2.5
    -- Share of rolls that fail, pass, or pass as part of a draining streak
    local drainShare = p ^ successRollsBeforeDrain
    local failShare, passShare = 1 - p, p - drainShare
    local failMult = 1 + fillJitter * p
    local passMult = 1 - fillJitter * (1 - p)
    local base = (1 / detectDur + drainShare * inSightDrainRate) / (failShare * failMult + passShare * passMult)
    return base * failMult, base * passMult
end

local function posAboveActor(actor)
    local bbox = actor:getBoundingBox()
    return bbox.center + util.vector3(0, 0, bbox.halfSize.z)
end

local function getFollowTargets(actor)
    actor:sendEvent("MaxYariUtil_GetFollowTargets")
end

local function isFriend(ast)    
    if not ast.followTargets then return false end
    if gutils.arrayContains(ast.followTargets, omwself.object) and (not ast.combatTargets or not gutils.arrayContains(ast.combatTargets, omwself.object)) then
        return true
    end
    return false
end





-- Fatigue below zero is the engine's own knockout. Gothic Style Knockout drops it to -300 (and it regenerates
-- only a few points a second), plain exhaustion rarely gets anywhere near -100, so by default only those deep
-- knockouts count. The "KnockoutLosesTrack" setting makes any knockout count.
local DEEP_KNOCKOUT_FATIGUE = -100

local function isFatigueKnockedOut(actor)
    local threshold = settings.KnockoutLosesTrack and 0 or DEEP_KNOCKOUT_FATIGUE
    return types.Actor.stats.dynamic.fatigue(actor).current < threshold
end

local function isActorKnockedOut(actor)
    if isFatigueKnockedOut(actor) then return true end
    -- Devilish Sleep Spell
    for _, spell in pairs(types.Actor.activeSpells(actor)) do
        if spell.id == DEFS.KNOCKOUT_SPELL_ID then return true end
    end
    return false
end

-- The engine gives sneak skill for avoiding the notice of anyone in sight, hostile or not. Here it's only
-- given while a hostile actor (a red marker) is in sight, so sneaking around friendly NPCs doesn't train it.
-- All sneak skill gains are then scaled by the "SneakSkillGainMult" setting.
I.SkillProgression.addSkillUsedHandler(function(skillid, params)
    if skillid ~= "sneak" then return end
    if params.useType == I.SkillProgression.SKILL_USE_TYPES.Sneak_AvoidNotice and not ps.hostileInSight then
        return false
    end
    params.skillGain = params.skillGain * skillSettings.SneakSkillGainMult
end)


-- Main logic starts here -----------------------------------------------
-------------------------------------------------------------------------
local function detectionLogicTick(dt)
    -- Fetching cell changes and removing actors from other cells
    local cell = I.MSS.getCell()
    if not lastCell or (lastCell ~= cell and not (lastCell.isExterior and cell.isExterior)) then
        lastCell = cell
        for id, ast in pairs(persistantActorStatuses) do
            if ast.cell ~= cell then                 
                if ast.marker then                    
                    ast.marker:destroy()
                end                
                persistantActorStatuses[id] = nil
                observerActorStatuses[id] = nil
            end
        end
    end

    -- Throttled nearby scan: new observers picked up every ~0.2s instead of every frame;
    -- existing observers in observerActorStatuses continue to be processed every frame below
    nearbyCheckTimer = nearbyCheckTimer + dt
    if ps.isSneaking and nearbyCheckTimer >= nearbyCheckPeriod then
        nearbyCheckTimer = 0
        for _, actor in ipairs(nearby.actors) do

            if actor == omwself.object then goto continue end

            local isDead = types.Actor.isDead(actor)

            -- Don't add dead actors to observers, but mark them dead if ast exists
            local ast = nil
            if isDead then
                ast = getAstIfExists(actor)
                if ast then ast.isDead = true end
                goto continue
            end

            if not ast then ast = getAst(actor) end

            local distance = (I.MSS.getPosition() - actor.position):length()
            ast.distance = distance
            ast.isDead = false

            -- Add to observerActorStatuses if within detection range and not a friend
            if distance <= detection.detectionRange and not ast.isFriend then
                observerActorStatuses[actor.id] = ast
            end

            ::continue::
        end
    end
    
    ps.detectedByNonAggro = false
    ps.hostileInSight = false
    local now = core.getSimulationTime()
    -- The most alert observer, shown by the stealth reticle
    local topProgress, topAggressive = 0, true
    for actorId, ast in pairs(observerActorStatuses) do
        -- LOS check for all observer actors (regardless of detection range)
        if ast.losChecker == nil then
            ast.losChecker = gutils.cachedFunction(detection.LOS, losCheckPeriod, math.random() * losCheckPeriod)
        end

        -- Sneak check for all observers (reuses inLOS from above)
        if ast.sneakChecker == nil then
            ast.sneakChecker = gutils.cachedFunction(detection.sneakCheck, sneakCheckPeriod, math.random() * sneakCheckPeriod)
        end
        if ast.followTargetsChecker == nil then
            ast.followTargetsChecker = gutils.cachedFunction(getFollowTargets, followTargetsCheckPeriod, math.random() * followTargetsCheckPeriod)
        end

        ast.inLOS = ast.losChecker(omwself.object, ast.actor)
        local isNotDetected, newSneakChance, rollState = ast.sneakChecker(ast, ps, extraMods)
        ast.followTargetsChecker(ast.actor)

        ast.noticing = not isNotDetected
        if newSneakChance ~= nil then ast.sneakChance = newSneakChance end
        
        if ast.fightingPlayer then
            ast.isAggressive = true
        else
            ast.isAggressive = aggression.isAggressive(ast, omwself.object)
        end        

        -- Manage detection progress ----
        ---------------------------------
        if ast.progress == nil then ast.progress = 0.0 end
        if ast.successRolls == nil then ast.successRolls = 0 end
        -- Passed rolls in a row: counted per roll, the checker returns its cached result between rolls
        if rollState == "new" then
            ast.successRolls = isNotDetected and ast.successRolls + 1 or 0
        end
        local failSpeed, passSpeed = getFillSpeeds(ast.sneakChance)

        -- Handle knocked out actors (Gothic Style Knockout, Devilish Sleep Spell): they can't see or fight.
        -- A knockout blow also makes an actor fight the player, and its fatigue drop lands a frame after the
        -- hit report, so the fatigue of an actor fighting the player is read on every tick
        if ast.actor:isValid() then
            if now >= (ast.nextKnockoutCheck or 0) then
                ast.isKnockedOut = isActorKnockedOut(ast.actor)
                ast.nextKnockoutCheck = now + knockoutCheckPeriod
            elseif ast.fightingPlayer and not ast.isKnockedOut then
                ast.isKnockedOut = isFatigueKnockedOut(ast.actor)
            end
        end

        -- Handle dead/invalid actors
        if ast.isDead or ast.isKnockedOut or not ast.actor:isValid() then
            ast.noticing = false
            ast.progress = 0.0
            ast.successRolls = 0
        elseif ast.fightingPlayer then
            ast.noticing = true
            ast.progress = 1.0
        elseif not ast.inLOS then
            -- Out of LOS: drain at a fixed rate, and count it as a streak of passed rolls
            ast.progress = math.max(0.0, ast.progress - dt * outOfSightDrainRate)
            ast.successRolls = successRollsBeforeDrain
        elseif ast.noticing then
            -- Failed roll: fill faster than average
            ast.progress = math.min(1.0, ast.progress + dt * failSpeed)
        elseif ast.successRolls < successRollsBeforeDrain then
            -- Passed roll: keep filling, slower than average
            ast.progress = math.max(0.0, math.min(1.0, ast.progress + dt * passSpeed))
        else
            -- Several passed rolls in a row: the observer calms down
            ast.progress = math.max(0.0, ast.progress - dt * inSightDrainRate)
        end

        -- Send spotted event and break sneak only when detection progress reaches 1.0
        if ast.progress >= 1.0 then
            if ast.isAggressive then
                omwself.controls.sneak = false  -- Break sneak when fully detected
            else
                ps.detectedByNonAggro = true
            end
        end

        if ast.inLOS and ast.isAggressive and not ast.isDead and not ast.isKnockedOut then
            ps.hostileInSight = true
        end

        if not ast.isDead and not ast.isKnockedOut and ast.progress > topProgress then
            topProgress = ast.progress
            topAggressive = ast.isAggressive
        end

        -- Manage ui markers ------------------
        ---------------------------------------
        -- Show markers only when sneaking and detection progress is happening
        local shouldShowMarker = uiSettings.ShowMarkers and ps.isSneaking and not ast.isDead and not ast.isKnockedOut
            and ast.inLOS
        if shouldShowMarker then
            -- If marker doesnt exist but should - make it
            if not ast.marker then ast.marker = DetectionMarker:new() end
        elseif ast.marker then
            -- If it shouldnt exist but does - remove it
            local isSuccesful = ast.progress >= 1.0
            ast.marker:disappear(isSuccesful)
        end

        if ast.marker and ast.marker.destroyed then
            ast.marker = nil
        end

        if ast.marker then
            -- Update the marker's progress and position
            ast.marker:setProgress(ast.progress)
            ast.marker:setWorldPos(posAboveActor(ast.actor))
            ast.marker:setAggressive(ast.isAggressive)
        end

        -- Update tweeners here to avoid a second full pass over observerActorStatuses in onUpdate
        if ast.marker then ast.marker:updateTweeners(dt) end

        -- Final cleanup, if no marker and no progress - remove the status object --
        -- While sneaking, an observer in sight stays even without a marker (markers can be turned off), it's
        -- what tells a hostile is in sight for the sneak skill
        ----------------------------------------------------------------------------
        if (ast.marker == nil) and (ast.progress <= 0.0) and not (ps.isSneaking and ast.inLOS) then
            observerActorStatuses[actorId] = nil
        end

        ::continue::
    end

    reticle.update(dt, ps.isSneaking and uiSettings.ShowAnimatedReticle, topProgress, topAggressive)
end


local function onUpdate(dt)
    if dt == 0 then
        return
    end

    lean.update(dt)

    -- Fetching locomotion statuses
    ps.isMoving = selfActor:getCurrentSpeed() > 0 or not selfActor:isOnGround()
    ps.isSneaking = omwself.controls.sneak

    -- Invisibility and chameleon through MSS, re-read at most every effectsCheckPeriod (effects change
    -- infrequently)
    local invisibility = I.MSS.getActiveEffect(core.magic.EFFECT_TYPE.Invisibility, effectsCheckPeriod)
    ps.isInvisible = invisibility ~= nil and invisibility > 0
    ps.chameleon = I.MSS.getActiveEffect(core.magic.EFFECT_TYPE.Chameleon, effectsCheckPeriod) or 0

    detectionLogicTick(dt)

    -- Weapon skill modifier: only runs while sneaking or when cleaning up a leftover modifier
    if ps.isSneaking or modifiedSkill then
        -- The weapon's record through MSS: cached, and only read again when the weapon changes
        local weaponInfo = I.MSS.getEquipmentInfo(types.Actor.EQUIPMENT_SLOT.CarriedRight)
        local skill = "handtohand"
        if weaponInfo and weaponInfo.type == types.Weapon then
            skill = itemutil.weaponEquipmentSkills[weaponInfo.record.type].id
        end
        local stat = selfActor:getSkillStat(skill)

        if ps.isSneaking then
            if modifiedSkill ~= skill then
                -- if we switched to a different skill, remove old modifier
                if modifiedSkill then
                    local oldStat = selfActor:getSkillStat(modifiedSkill)
                    oldStat.modifier = oldStat.modifier - skillMod
                end

                skillMod = stat.base * skillSettings.WeaponBonus
                modifiedSkill = skill
                stat.modifier = stat.modifier + skillMod
            end
        else
            if modifiedSkill then
                -- remove modifier when not sneaking; use modifiedSkill's stat, not current weapon's,
                -- in case the player unequipped their weapon on the same frame they stopped sneaking
                local oldStat = selfActor:getSkillStat(modifiedSkill)
                oldStat.modifier = oldStat.modifier - skillMod
                modifiedSkill = nil
                skillMod = 0
            end
        end
    end
end





-- Event handlers ----------------------------------------------
----------------------------------------------------------------
local function onCombatTargetsChanged(e)
    
    if e.actor == omwself.object then return end
    -- print("Combat targets changed for " .. e.actor.recordId)

    local ast = getAst(e.actor)    
    ast.combatTargets = e.targets    
    ast.isFriend = isFriend(ast)
    ast.isDead = types.Actor.isDead(e.actor) 

    if not ast.isDead and gutils.arrayContains(ast.combatTargets, omwself.object) then
        gutils.print("Player: Combat targets changed for " .. e.actor.recordId, "Player is a target", 1)
        ast.fightingPlayer = true
        ast.isAggressive = true
        observerActorStatuses[e.actor.id] = ast
    else
        ast.fightingPlayer = false
        if ast.isFriend then
            observerActorStatuses[e.actor.id] = nil
        end
    end
end

local function onGetFollowTargets(e)
    -- gutils.print("Player: Received follow targets resp from " .. e.actor.recordId, 1)    
    if e.actor == omwself.object then return end

    local ast = getAst(e.actor)
    ast.followTargets = e.targets
    ast.isFriend = isFriend(ast)
    if ast.isFriend then
        observerActorStatuses[e.actor.id] = nil
    end
    -- gutils.print(e.actor.recordId, "Is a friend",ast.isFriend, 1)
end

local function onReportAttack(e)
    if e.target == omwself.object then return end

    -- gutils.print("Reported attack by " .. e.attacker.recordId .. " on " .. e.target.recordId)
    local ast = getAst(e.target)
    ast.isFriend = isFriend(ast)
    ast.isDead = types.Actor.isDead(e.target) 

    if e.attacker == omwself.object and not ast.isDead then
        ast.fightingPlayer = true
        ast.isAggressive = true
        ast.isKnockedOut = isActorKnockedOut(e.target)
        ast.nextKnockoutCheck = core.getSimulationTime() + knockoutCheckPeriod
        observerActorStatuses[e.target.id] = ast
    end
end

local function onSave()
    return {
        modifiedSkill = modifiedSkill,
        skillMod = skillMod
    }
end

local function onLoad(data)
    if data.modifiedSkill then
        modifiedSkill = data.modifiedSkill
        skillMod = data.skillMod
    end
end

return {    
    engineHandlers = {
        onFrame = lean.onFrame,
        onUpdate = onUpdate,
        onSave = onSave,
        onLoad = onLoad
    },
    eventHandlers = { 
        OMWMusicCombatTargetsChanged = onCombatTargetsChanged,
        MaxYariUtil_FollowTargets = onGetFollowTargets,
        [DEFS.e.ReportAttack] = onReportAttack
    },
    interfaceName = DEFS.mod_name,
    interface = interface
}