local aiAttack = {}

-- imports

local constants = require("Constants")
local mapUtils = require("MapUtils")
local unitGroupUtils = require("UnitGroupUtils")

-- constants
          
local PLAYER_PHEROMONE = constants.PLAYER_PHEROMONE
local DEATH_PHEROMONE = constants.DEATH_PHEROMONE
local ENEMY_BASE_PHEROMONE = constants.ENEMY_BASE_PHEROMONE
local PLAYER_BASE_PHEROMONE = constants.PLAYER_BASE_PHEROMONE
local PLAYER_DEFENSE_PHEROMONE = constants.PLAYER_DEFENSE_PHEROMONE

local SQUAD_RAIDING = constants.SQUAD_RAIDING
local SQUAD_SUICIDE_RAID = constants.SQUAD_SUICIDE_RAID
local SQUAD_HUNTING = constants.SQUAD_HUNTING
local SQUAD_GUARDING = constants.SQUAD_GUARDING
local SQUAD_SUICIDE_HUNT = constants.SQUAD_SUICIDE_HUNT

local AI_TUNNEL_COST = constants.AI_TUNNEL_COST

local ENEMY_BASE_GENERATOR = constants.ENEMY_BASE_GENERATOR
local MAGIC_MAXIMUM_NUMBER = constants.MAGIC_MAXIMUM_NUMBER

local HALF_CHUNK_SIZE = constants.HALF_CHUNK_SIZE
local CHUNK_SIZE = constants.CHUNK_SIZE

local PLAYER_BASE_GENERATOR = constants.PLAYER_BASE_GENERATOR
local PLAYER_DEFENSE_GENERATOR = constants.PLAYER_DEFENSE_GENERATOR

local GROUP_STATE_FINISHED = defines.group_state.finished
local GROUP_STATE_GATHERING = defines.group_state.gathering
local GROUP_STATE_MOVING = defines.group_state.moving

local COMMAND_ATTACK_AREA = defines.command.attack_area
local COMMAND_ATTACK = defines.command.attack

local DISTRACTION_BY_ANYTHING = defines.distraction.by_anything

-- imported functions

local getCardinalChunks = mapUtils.getCardinalChunks
local positionToChunk = mapUtils.getChunkByPosition
local canMove = mapUtils.canMoveChunkDirectionCardinal
local addSquadMovementPenalty = unitGroupUtils.addSquadMovementPenalty
local lookupSquadMovementPenalty = unitGroupUtils.lookupSquadMovementPenalty
local positionDirectionToChunkCornerCardinal = mapUtils.positionDirectionToChunkCornerCardinal
local findDistance = mapUtils.euclideanDistanceNamed
                             
local mRandom = math.random

-- module code

function aiAttack.squadAttackLocation(regionMap, surface, natives)
    local squads = natives.squads
    for i=1, #squads do
        local squad = squads[i]
        local group = squad.group
        if group.valid and ((squad.status == SQUAD_RAIDING) or (squad.status == SQUAD_SUICIDE_RAID)) then
            local groupState = group.state
            if (groupState == GROUP_STATE_FINISHED) or (groupState == GROUP_STATE_GATHERING) or (groupState == GROUP_STATE_MOVING) then
                local chunk = positionToChunk(regionMap, group.position.x, group.position.y)
                addSquadMovementPenalty(squad, chunk.cX, chunk.cY)
                local attackLocationNeighbors = getCardinalChunks(regionMap, chunk.cX, chunk.cY)
                local attackChunk
                local attackScore = -MAGIC_MAXIMUM_NUMBER
                local attackDirection    
                local attackPosition = {x=0, y=0}
                -- print("------")
                for x=1, #attackLocationNeighbors do
                    local neighborChunk = attackLocationNeighbors[x]
                    if (neighborChunk ~= nil) and canMove(x, chunk, neighborChunk) then
                        attackPosition.x = neighborChunk.pX
                        attackPosition.y = neighborChunk.pY
                        local squadMovementPenalty = lookupSquadMovementPenalty(squad, neighborChunk.cX, neighborChunk.cY)
                        local damageScore = surface.get_pollution(attackPosition) + neighborChunk[PLAYER_BASE_PHEROMONE] + neighborChunk[PLAYER_PHEROMONE] + neighborChunk[PLAYER_DEFENSE_GENERATOR]
                        local avoidScore = neighborChunk[DEATH_PHEROMONE] + (neighborChunk[ENEMY_BASE_GENERATOR] * 2) --+ (neighborChunk[ENEMY_BASE_PHEROMONE] * 0.5)
                        local score = damageScore - avoidScore - squadMovementPenalty
                        if (score > attackScore) then
                            attackScore = score
                            attackChunk = neighborChunk
                            attackDirection = x
                        end
                        -- print(x, score, damageScore, avoidScore, neighborChunk.cX, neighborChunk.cY)
                    end
                end
                if (attackChunk ~= nil) then
                    -- print("==")
                    -- print (attackDirection, chunk.cX, chunk.cY)
                    if ((attackChunk[PLAYER_BASE_GENERATOR] == 0) or (attackChunk[PLAYER_DEFENSE_GENERATOR] == 0)) or 
                        ((groupState == GROUP_STATE_FINISHED) or (groupState == GROUP_STATE_GATHERING)) then
                        -- print("attacking")
                        attackPosition = positionDirectionToChunkCornerCardinal(attackDirection, attackChunk)
                        squad.cX = attackChunk.cX
                        squad.cY = attackChunk.cY
                        
                        group.set_command({type=COMMAND_ATTACK_AREA,
                                           destination=attackPosition,
                                           radius=HALF_CHUNK_SIZE,
                                           distraction=DISTRACTION_BY_ANYTHING})
                        group.start_moving()
                    end
                end
            end
        end
    end
end


function aiAttack.squadAttackPlayer(regionMap, surface, natives, players)
    local squads = natives.squads
    
    for si=1, #squads do
        local squad = squads[si]
        local group = squad.group
        if (group.valid) and (squad.status == SQUAD_GUARDING) then
            local closestPlayer
            local closestDistance = MAGIC_MAXIMUM_NUMBER
            for pi=1, #players do
                local player = players[pi]
                if (player.connected) then
                    local playerCharacer = player.character
                    if (playerCharacer ~= nil) then
                        local distance = findDistance(playerCharacer.position, group.position)
                        if (distance < closestDistance) then
                            closestPlayer = playerCharacer
                            closestDistance = distance
                        end
                    end
                end
            end
            if (closestDistance < 75) then
                local squadType = SQUAD_HUNTING
                if (mRandom() < 0.10) then -- TODO add sliding scale based on number of members and evolution
                    squadType = SQUAD_SUICIDE_HUNT
                end
                squad.status = squadType
                group.set_command({type=COMMAND_ATTACK,
                                   target=closestPlayer})
            end
        end
    end
end

function aiAttack.squadBeginAttack(natives)
    local squads = natives.squads
   
    for i=1,#squads do
        local squad = squads[i]
        if (squad.status == SQUAD_GUARDING) and (mRandom() < 0.7) then
            if (mRandom() < 0.05) then
                squad.status = SQUAD_SUICIDE_RAID
            else
                squad.status = SQUAD_RAIDING
            end
        end
    end
end

return aiAttack