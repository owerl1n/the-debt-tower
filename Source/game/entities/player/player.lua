local pd <const> = playdate
local gfx <const> = playdate.graphics

import "game/entities/player/scorePopup"
import "game/entities/player/promptHint"
import "game/entities/player/taxIndicator"

class('Player').extends(AnimatedSprite)

playerImageTable = gfx.imagetable.new("images/mage-table-32-32")
assert(playerImageTable, "playerImageTable not found")

local SHOOT_COOLDOWN          = 20

local BLOCK_SPELL_COST        = 60 --6
local DASH_SPELL_COST         = 75 --8
local ANCHOR_SPELL_COST       = 90 --14
local BOUNCE_BLOCK_SPELL_COST = 115 --16

function Player:init(x, y, levelComplete, onLevelPassed)
    Player.super.init(self, playerImageTable)

    self:addState("idle",  2, 2, { loop = true })
    self:addState("run",   3, 4, { tickStep = 4, loop = true })
    self:addState("jump",  5, 6, { tickStep = 4, loop = true })
    self:addState("fall",  7, 8, { tickStep = 4, loop = true })
    self:addState("dash",  7, 7, { loop = true })
    self:addState("death", 1, 1, { loop = true })
    self:addState("vanish", 9, 16, {
        tickStep = 3,
        loop     = false,
        onAnimationEndEvent = function(sprite)
            sprite:setVisible(false)
        end,
    })
    self:playAnimation()

    self.motionState = "idle"
    self._airFrames  = 0
    self._vanishing  = false

    self:moveTo(x, y)
    self:setZIndex(Z_INDEXES.Player)
    -- Спрайт 32x32, центр (16,16). Коллайдер тот же 10x13 и в том же месте
    -- относительно центра, что и раньше (было 3,3 на 17x17).
    self:setCollideRect(10.5, 10.5, 10, 13)
    self:setTag(TAGS.Player)

    -- Physics
    self.xVelocity             = 0
    self.yVelocity             = 0
    self.gravity               = 0.75
    self.maxSpeed              = 2
    self.jumpVelocity          = -4.05
    self.drag                  = 0.2
    self.minimumAirSpeed       = 0.5

    -- jump
    self.jumpBufferAmount      = 7
    self.jumpBuffer            = 0
    self.jumpHoldForce         = -0.35
    self.jumpHoldMaxFrames     = 7
    self.jumpHoldFrames        = 0
    self.jumpMinCutoffSpeed    = -1.4

    self.coyoteFrames          = 0
    self.coyoteMaxFrames       = 3

    -- Death
    self._deathBounceX         = 0
    self._deathBounceY         = 0
    self._restartTriggered     = false

    -- Abilities
    self.doubleJumpAbility     = false
    self.dashAbility           = false

    -- Double Jump
    self.doubleJumpAvailable   = true

    -- Dash
    self.dashAvailable         = true
    self.dashSpeed             = 8
    self.dashMinimumSpeed      = 3
    self.dashDrag              = 0.8

    -- State
    self.touchingGround        = false
    self.touchingCeiling       = false
    self.touchingWall          = false
    self.dead                  = false

    self.atExit                = false
    self._exitSprite           = nil

    self._portalCooldown       = 0

    self._nearbyNPC            = nil
    self.promptHint            = PromptHint(self) 

    self.taxIndicator          = TaxIndicator(self, self.promptHint)

    self.scorePopup            = ScorePopup(self, self.promptHint)

    -- Spell: projectile
    self.projectileAbility     = false
    self._shootCooldown        = 0

    self._lastProjectile       = nil

    -- Spell: anchor
    self.anchorAbility         = false
    self._anchorX              = nil
    self._anchorY              = nil
    self._anchorMarker         = nil

    -- BounceBlock
    self._fallFromY            = nil
    self._peakY                = nil
    self.bounceBlockAbility    = false
    self._lastBounceProjectile = nil
    self._bounceShootCooldown  = 0

    self.taxMultiplier         = 1

    self._blockIndicator       = nil

    self.levelComplete         = levelComplete
    self._onLevelPassed        = onLevelPassed
    
end

function Player:showScorePopup(amount)
    self.scorePopup:addScore(amount)
end

function Player:collisionResponse(other)
    local tag = other:getTag()
    if tag == TAGS.Pickup or tag == TAGS.Hazard or tag == TAGS.Exit then
        return gfx.sprite.kCollisionTypeOverlap
    end
    return gfx.sprite.kCollisionTypeSlide
end

function Player:update()
    if self.y > 140 or self.y < -20 or self.x < -20 or self.x > 220 then
        if not self._restartTriggered then
            self:die()
            self:_triggerRestart()
        end
        return
    end

    if self.dead then
        self:_clearBlockIndicator()
        self:_clearNearbyNPC()
        self:updateDeathBounce()
        return
    end

    if isGamePaused() then
        self:updateAnimation()
        return
    end

    if self._portalCooldown and self._portalCooldown > 0 then
        self._portalCooldown -= 1
    end

    self:updateAnimation()

    if not isGamePaused() then
        self:handleAbilityInput()
        self:_updateBlockIndicator()
    end

    self:updateJumpBuffer()
    self:handleState()
    self:handleMovementAndCollisions()
    self:_updateVisualState()
end

function Player:updateJumpBuffer()
    self.jumpBuffer -= 1
    if self.jumpBuffer <= 0 then self.jumpBuffer = 0 end
    if pd.buttonJustPressed(pd.kButtonA) then
        self.jumpBuffer = self.jumpBufferAmount
    end
end

function Player:playerJumped()
    return self.jumpBuffer > 0 and (self.touchingGround or self.coyoteFrames > 0)
end

function Player:handleState()
    if self.motionState == "idle" then
        self:applyGravity()
        if self.atExit then
            self.xVelocity = 0
        else
            self:handleGroundInput()
        end
    elseif self.motionState == "run" then
        self:applyGravity()
        if self.atExit then
            self:changeToIdleState()
        else
            self:handleGroundInput()
        end
    elseif self.motionState == "jump" then
        if self.touchingGround then self:changeToIdleState() end
        if self._peakY == nil or self.y < self._peakY then
            self._peakY = self.y
        end
        self:applyGravity()
        self:applyDrag(self.drag)

        -- Variable jump height
        if self.jumpHoldFrames > 0 then
            if pd.buttonIsPressed(pd.kButtonA) then
                self.yVelocity += self.jumpHoldForce
                self.jumpHoldFrames -= 1
            else
                self.jumpHoldFrames = 0
                if self.yVelocity < self.jumpMinCutoffSpeed then
                    self.yVelocity = self.jumpMinCutoffSpeed
                end
            end
        end

        if not self.atExit then
            self:handleAirInput()
        end
    elseif self.motionState == "dash" then
        self:applyDrag(self.dashDrag)
        if math.abs(self.xVelocity) <= self.dashMinimumSpeed then
            self:changeToFallState()
        end
    end
end

function Player:handleAbilityInput()
    self:handleAnchorInput()

    if self._shootCooldown > 0 then
        self._shootCooldown -= 1
    end

    if self.projectileAbility and pd.buttonJustPressed(pd.kButtonDown) then
        if self._lastProjectile and self._lastProjectile.x then
            local tileX = math.floor(self._lastProjectile.x / 16) * 16 + 8
            local tileY = math.floor(self._lastProjectile.y / 16) * 16 + 8

            local occupied = isAreaBlocked(tileX - 8, tileY - 8, 16, 16)

            if not occupied then
                PlacedBlock(tileX, tileY)
                self._lastProjectile:remove()
                self._lastProjectile = nil
                self:_clearBlockIndicator()
                print("[Player] блок размещён")
            else
                print("[Player] клетка занята — блок не поставлен")
            end
        elseif self._shootCooldown <= 0 then
            if self:_castSpell(BLOCK_SPELL_COST) then
                local dir            = (self.globalFlip == 1) and -1 or 1
                local p              = Projectile(self.x + dir * 10, self.y, dir)
                self._lastProjectile = p
                self._shootCooldown  = SHOOT_COOLDOWN
                print("[Player] выстрел dir=" .. dir)
            end
        end
    end

    if self._lastProjectile and self._lastProjectile.destroyed then
        self._lastProjectile = nil
    end

    if self._bounceShootCooldown > 0 then
        self._bounceShootCooldown -= 1
    end

    if self.bounceBlockAbility and pd.buttonJustPressed(pd.kButtonDown) then
        if self._lastBounceProjectile and self._lastBounceProjectile.x then
            local tileX = math.floor(self._lastBounceProjectile.x / 16) * 16 + 8
            local tileY = math.floor(self._lastBounceProjectile.y / 16) * 16 + 8

            local occupied = isAreaBlocked(tileX - 8, tileY - 8, 16, 16)

            if not occupied then
                BounceBlock(tileX, tileY)
                self._lastBounceProjectile:remove()
                self._lastBounceProjectile = nil
                self:_clearBlockIndicator()
            else
                print("[Player] клетка занята — BounceBlock не поставлен")
            end
        elseif self._bounceShootCooldown <= 0 then
            if self:_castSpell(BOUNCE_BLOCK_SPELL_COST) then
                local dir                  = (self.globalFlip == 1) and -1 or 1
                local p                    = Projectile(self.x + dir * 10, self.y, dir)
                self._lastBounceProjectile = p
                self._bounceShootCooldown  = SHOOT_COOLDOWN
            end
        end
    end

    if self._lastBounceProjectile and self._lastBounceProjectile.destroyed then
        self._lastBounceProjectile = nil
    end
end

function Player:clearAnchor()
    self._anchorX = nil
    self._anchorY = nil
    if self._anchorMarker then
        self._anchorMarker:remove()
        self._anchorMarker = nil
    end
end

function Player:handleAnchorInput()
    if not self.anchorAbility then return end
    if not pd.buttonJustPressed(pd.kButtonDown) then return end

    if self._anchorX then
        local tx, ty = self._anchorX, self._anchorY
        local blocked = isAreaBlocked(tx - 5, ty - 6.5, 3, 13, self._anchorMarker)
        if blocked then
            print("[Anchor] телепорт заблокирован — место занято")
            return
        end
        SmokeEffect(self.x, self.y, "anchor")
        self:clearAnchor()
        self:moveTo(tx, ty)
        self.xVelocity = 0
        SmokeEffect(tx, ty, "anchor")
        print("[Anchor] teleport to " .. tx .. "," .. ty)
    else
        if not self:_castSpell(ANCHOR_SPELL_COST) then
            print("[Anchor] недостаточно денег")
            return
        end
        self._anchorX = self.x
        self._anchorY = self.y
        self._anchorMarker = AnchorMarker(self.x, self.y)
        SmokeEffect(self.x, self.y, "anchor")
        print("[Anchor] placed at " .. self.x .. "," .. self.y)
    end
end

function Player:handleMovementAndCollisions()
    local wasOnGround = self.touchingGround
    local _, _, collisions, length = self:moveWithCollisions(self.x + self.xVelocity, self.y + self.yVelocity)

    if Game.instance and Game.instance.level then
        local colliderX = self.x - 5.5 -- -8.5 (половина 17) + 3 (offset коллайдера)
        local colliderY = self.y - 5.5
        self.taxMultiplier = Game.instance.level:getTaxMultiplierAt(colliderX, colliderY, 10, 13)
    end

    self.touchingGround = false
    self.touchingCeiling = false
    self.touchingWall = false
    local died = false
    local touchedExit = false
    local touchedNPC = nil

    for i = 1, length do
        local collision = collisions[i]
        local collisionType = collision.type
        local collisionObject = collision.other
        local collisionTag = collisionObject:getTag()

        if collisionType == gfx.sprite.kCollisionTypeSlide then
            if collision.normal.y == -1 then
                self.touchingGround = true
                self.doubleJumpAvailable = true
                self.dashAvailable = true
            elseif collision.normal.y == 1 then
                self.touchingCeiling = true
                self.jumpHoldFrames = 0
            end
            if collision.normal.x ~= 0 then
                self.touchingWall = true
            end
        end

        if collisionTag == TAGS.Hazard then
            if not self.atExit then
                died = true
            end
        elseif collisionTag == TAGS.CrumblingBlock then
            if collision.normal.y == -1 then
                self.touchingGround = true -- ← добавь это
                self.doubleJumpAvailable = true
                self.dashAvailable = true
                collisionObject:onPlayerLanded()
            elseif collision.normal.y == 1 then
                self.touchingCeiling = true
                self.jumpHoldFrames = 0
            end
            if collision.normal.x ~= 0 then
                self.touchingWall = true
            end
        elseif collisionTag == TAGS.Pickup then
            collisionObject:collect()
        elseif collisionTag == TAGS.Portal then
            collisionObject:teleport(self)
        elseif collisionTag == TAGS.NPC then
            touchedNPC = collisionObject
        elseif collisionTag == TAGS.Exit then
            touchedExit = true
            self._lastExitX = collisionObject.x + 8
            self._lastExitY = collisionObject.y
            self._exitSprite = collisionObject
        elseif collisionTag == TAGS.BounceBlock then
            if collision.normal.y == -1 then
                local targetY            = self._peakY or (self.y - 20) --TODO строка (self.y - x) где x - коэф который можно редактировать
                self.yVelocity           = BounceBlock.getBounceVelocity(self.gravity, targetY, self.y)
                self.doubleJumpAvailable = false
                self.dashAvailable       = true
                self._peakY              = targetY
                self.touchingGround      = false
                self.motionState = "jump"
                print("[BounceBlock] targetY=" .. math.floor(targetY) .. " v=" .. string.format("%.2f", self.yVelocity))
            end
        end
    end

    if self.touchingGround then
        self.coyoteFrames = self.coyoteMaxFrames
    else
        if self.coyoteFrames > 0 then
            self.coyoteFrames -= 1
        end
    end

    if touchedNPC then
        self._nearbyNPC = touchedNPC
        self.promptHint:show()
    else
        self:_clearNearbyNPC()
    end

    if self.xVelocity < 0 then
        self.globalFlip = 1
    elseif self.xVelocity > 0 then
        self.globalFlip = 0
    end

    if died then
        self:die()
    elseif touchedExit and not self.atExit then
        self:onExitTouch()
    end
end

function Player:onExitTouch()
    self.atExit = true
    self.xVelocity = 0

    if self._onLevelPassed then
        print("[Player] onExitTouch: вызываю onLevelPassed")  -- временный дебаг-принт
        self._onLevelPassed()
        self._onLevelPassed = nil
    else
        print("[Player] onExitTouch: onLevelPassed отсутствует!")  -- если видите это — колбэк не пришёл в конструктор
    end

    if self._exitSprite then
        self._exitSprite:playFinishAnimation(function(wasSkipped)
            if not self.levelComplete then return end
            if wasSkipped then
                self.levelComplete:triggerInstant()
            else
                self.levelComplete:trigger()
            end
        end)
    elseif self.levelComplete then
        self.levelComplete:trigger()
    end
end

function Player:die()
    if self.dead then return end

    self._restartTriggered = false
    self.dead = true
    self.atExit = false

    -- случайный отскок: X влево или вправо, Y всегда вверх
    local bounceX = (math.random(0, 1) == 0 and -1 or 1) * (1.5 + math.random() * 2.0)
    local bounceY = -(2.5 + math.random() * 2.0)
    self._deathBounceX = bounceX
    self._deathBounceY = bounceY

    self._facingBeforeDeath = self.globalFlip
    self.globalFlip = math.random(0, 1)

    self:changeState("death")

    -- отключаем коллизии
    self:setCollisionsEnabled(false)

    pd.timer.performAfterDelay(800, function()
        self:setCollisionsEnabled(true)
        self.dead = false
        self._deathBounceX = 0
        self._deathBounceY = 0
        if self._facingBeforeDeath then
            self.globalFlip = self._facingBeforeDeath
        end
        -- возвращаем анимацию
        self:playAnimation()
    end)
end

function Player:handleGroundInput()
    if self:playerJumped() then
        self:changeToJumpState()
    elseif pd.buttonJustPressed(pd.kButtonA) and self.dashAvailable and self.dashAbility
        and self:_castSpell(DASH_SPELL_COST) then
        self:changeToDashState()
    elseif pd.buttonIsPressed(pd.kButtonLeft) then
        self:changeToRunState("left")
    elseif pd.buttonIsPressed(pd.kButtonRight) then
        self:changeToRunState("right")
    else
        self:changeToIdleState()
    end
end

function Player:handleAirInput()
    if pd.buttonJustPressed(pd.kButtonA) and self.dashAvailable and self.dashAbility then
        if self.jumpHoldFrames <= 0 then
            if self:_castSpell(DASH_SPELL_COST) then
                self:changeToDashState()
                return
            end
        end
    end

    if self:playerJumped() and self.doubleJumpAvailable and self.doubleJumpAbility then
        self.doubleJumpAvailable = false
        self:changeToJumpState()
    elseif pd.buttonIsPressed(pd.kButtonLeft) then
        self.xVelocity = -self.maxSpeed
    elseif pd.buttonIsPressed(pd.kButtonRight) then
        self.xVelocity = self.maxSpeed
    end
end

function Player:changeToIdleState()
    self._peakY = nil
    self.xVelocity = 0
    self.motionState = "idle"
end

function Player:changeToRunState(direction)
    self._peakY = nil
    if direction == "left" then
        self.xVelocity = -self.maxSpeed
        self.globalFlip = 1
    elseif direction == "right" then
        self.xVelocity = self.maxSpeed
        self.globalFlip = 0
    end
    self.motionState = "run"
end

function Player:changeToJumpState()
    self._peakY = self.y
    self.yVelocity = self.jumpVelocity
    self.jumpBuffer = 0
    self.jumpHoldFrames = self.jumpHoldMaxFrames
    self.coyoteFrames = 0
    self.motionState = "jump"
end

function Player:changeToFallState()
    self.motionState = "jump"
end

function Player:changeToDashState()
    self.dashAvailable = false
    self.yVelocity = 0
    if pd.buttonIsPressed(pd.kButtonLeft) then
        self.xVelocity = -self.dashSpeed
    elseif pd.buttonIsPressed(pd.kButtonRight) then
        self.xVelocity = self.dashSpeed
    else
        if self.globalFlip == 1 then
            self.xVelocity = -self.dashSpeed 
        else
            self.xVelocity = self.dashSpeed
        end
    end
    self.motionState = "dash"
end

function Player:applyGravity()
    self.yVelocity += self.gravity
    if self.touchingGround or self.touchingCeiling then
        self.yVelocity = 0
    end
end

function Player:applyDrag(amount)
    if self.xVelocity > 0 then
        self.xVelocity -= amount
    elseif self.xVelocity < 0 then
        self.xVelocity += amount
    end
    if math.abs(self.xVelocity) < self.minimumAirSpeed or self.touchingWall then
        self.xVelocity = 0
    end
end

function Player:updateDeathBounce()
    -- гравитация применяется и во время смерти
    self._deathBounceY += self.gravity
    self:moveBy(self._deathBounceX, self._deathBounceY)
    -- горизонтальное затухание
    self._deathBounceX *= 0.92
end

function Player:_triggerRestart()
    if self._restartTriggered then return end
    self._restartTriggered = true

    if self.levelComplete and self.levelComplete._onRestart then
        self.levelComplete._onRestart()
    end
end

function Player:_updateBlockIndicator()
    local projectile = self._lastProjectile or self._lastBounceProjectile

    if projectile and projectile.x then
        local tileX = math.floor(projectile.x / 16) * 16 + 8
        local tileY = math.floor(projectile.y / 16) * 16 + 8

        if not self._blockIndicator then
            self._blockIndicator = BlockIndicator(tileX, tileY)
        else
            self._blockIndicator:moveTo(tileX, tileY)
        end

        local occupied = isAreaBlocked(tileX - 8, tileY - 8, 16, 16)
        self._blockIndicator:setBlocked(occupied)
    else
        self:_clearBlockIndicator()
    end
end

function Player:_clearBlockIndicator()
    if self._blockIndicator then
        self._blockIndicator:remove()
        self._blockIndicator = nil
    end
end

function Player:_clearNearbyNPC()
    if self._nearbyNPC then
        self._nearbyNPC = nil
        self.promptHint:hide()
    end
end

-- Пытается списать стоимость заклинания (с учётом self.taxMultiplier).
-- При успехе показывает над головой общий счёт игрока.
function Player:_castSpell(baseCost)
    local cost = baseCost * self.taxMultiplier
    if TreasureManager.trySpend(cost) then
        self:showScorePopup()
        return true
    end
    return false
end

function Player:skipExitSequence()
    if not self.atExit then return end

    if self._exitSprite and not self._exitSprite:isFinished() then
        self._exitSprite:skipFinishAnimation()
        return
    end

    if self.levelComplete and self.levelComplete:isActive() and not self.levelComplete:isInputReady() then
        self.levelComplete:skipIntro()
    end
end

function Player:_updateVisualState()
    if self.dead or self._vanishing then return end

    -- Из-за гравитации touchingGround мигает true/false на земле,
    -- поэтому "в воздухе" считаем только после 2+ кадров подряд без опоры.
    if self.touchingGround then
        self._airFrames = 0
    else
        self._airFrames += 1
    end

    local anim
    if self.motionState == "dash" then
        anim = "dash"
    elseif self.yVelocity < 0 then
        anim = "jump"
    elseif self._airFrames >= 2 then
        anim = "fall"
    elseif self.motionState == "run" then
        anim = "run"
    else
        anim = "idle"
    end

    self:changeState(anim)
end

function Player:playVanish()
    if self._vanishing then return end
    self._vanishing = true
    self.xVelocity = 0
    self:changeState("vanish")
end

function Player:collisionResponse(other)
    local tag = other:getTag()
    if tag == TAGS.Pickup or tag == TAGS.Hazard or tag == TAGS.Exit
        or tag == TAGS.Projectile or tag == TAGS.AnchorMark or tag == TAGS.Portal
        or tag == TAGS.NPC then
        return gfx.sprite.kCollisionTypeOverlap
    end
    return gfx.sprite.kCollisionTypeSlide
end