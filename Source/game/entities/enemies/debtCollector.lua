local pd  <const> = playdate
local gfx <const> = playdate.graphics

import "libs/AnimatedSprite"
import "game/entities/hazards/bounceBlock"

class('DebtCollector').extends(AnimatedSprite)

local imagetable = gfx.imagetable.new("images/debt_collector-table-16-16")
assert(imagetable, "DebtCollector: не удалось загрузить debt_collector-table-16-16")

local DEFAULT_SPEED = 1
local GRAVITY = 0.75
local TELEPORT_COOLDOWN = 35

-- Коллайдер: setCollideRect(2, 2, 12, 12) на спрайте 16x16 с center(0.5, 0.5)
-- => половина ширины хитбокса = 6px, нижняя грань хитбокса = self.y + 6
local COLLIDER_HALF_W = 6
local COLLIDER_BOTTOM = 6

local GROUND_PROBE_DEPTH = 3  -- насколько ниже ног проверяем опору
local LEDGE_PROBE_AHEAD  = 8  -- на сколько пикселей вперёд смотрим при поиске обрыва
local LEDGE_PROBE_WIDTH  = 6

local PROBE_EPSILON = 1

-- Авторитетная проверка "есть ли твёрдая опора прямо под ногами сейчас".
-- Не зависит от того, что вернула коллизия в этом кадре — читает мир напрямую.
local function hasGroundBelow(self)
    local left = self.x - COLLIDER_HALF_W - PROBE_EPSILON
    local w    = COLLIDER_HALF_W * 2 + PROBE_EPSILON * 2
    local y    = self.y + COLLIDER_BOTTOM
    return isAreaBlocked(left, y, w, GROUND_PROBE_DEPTH, self)
end

-- Проверка "есть ли опора немного впереди по направлению движения".
-- Если нет — там обрыв/пропасть, нужно развернуться, не дожидаясь падения.
local function hasGroundAhead(self, direction)
    local aheadX = self.x + direction * LEDGE_PROBE_AHEAD
    local left   = aheadX - LEDGE_PROBE_WIDTH / 2 - PROBE_EPSILON
    local width  = LEDGE_PROBE_WIDTH + PROBE_EPSILON * 2
    local y      = self.y + COLLIDER_BOTTOM
    return isAreaBlocked(left, y, width, GROUND_PROBE_DEPTH, self)
end

function DebtCollector:init(x, y, entity)
    DebtCollector.super.init(self, imagetable)

    self:addState("walk", 1, 1, {
        loop = true,
    })

    self._direction = 1
    if entity and entity.fields and entity.fields.Direction then
        if string.lower(entity.fields.Direction) == "left" then
            self._direction = -1
        end
    end

    self._speed = DEFAULT_SPEED
    if entity and entity.fields and entity.fields.Speed then
        self._speed = entity.fields.Speed
    end

    self:setCenter(0.5, 0.5)
    self:moveTo(x, y)
    self:setZIndex(Z_INDEXES.NPC)
    self:setCollideRect(2, 2, 12, 12)
    self:setTag(TAGS.Hazard)
    self:add()

    self.yVelocity      = 0
    self.touchingGround = false
    self._peakY         = nil

    self._portalCooldown = 0

    self:changeState("walk")
    self:playAnimation()

    print("[DebtCollector] spawned x=" .. x .. " y=" .. y)
end

function DebtCollector:update()
    if isGamePaused() then
        return
    end

    if self._portalCooldown > 0 then
        self._portalCooldown -= 1
    end

    self:updateAnimation()

    if not self.touchingGround then
        if self._peakY == nil or self.y < self._peakY then
            self._peakY = self.y
        end
    end

    self.yVelocity += GRAVITY
    if self.touchingGround then
        self.yVelocity = 0
    end

    -- ← НОВОЕ: если стоим на земле и впереди по курсу — обрыв, разворачиваемся
    -- ДО того, как сделаем шаг, чтобы не зависать на краю и не падать зря.
    if self.touchingGround and not hasGroundAhead(self, self._direction) then
        self._direction = -self._direction
    end

    local newX = self.x + self._direction * self._speed
    local newY = self.y + self.yVelocity

    local _, _, collisions, len = self:moveWithCollisions(newX, newY)

    self.touchingGround = false

    for i = 1, len do
        local col   = collisions[i]
        local other = col.other
        local tag   = other.getTag and other:getTag()

        if col.type == gfx.sprite.kCollisionTypeSlide then
            if col.normal.y == -1 then
                self.touchingGround = true
                self._peakY = nil
            end
            if col.normal.x ~= 0 then
                self._direction = -self._direction
            end
        end

        if tag == TAGS.Portal then
            if self._portalCooldown <= 0 then
                other:teleport(self)
                self._portalCooldown = TELEPORT_COOLDOWN
            end
            return
        elseif tag == TAGS.Pickup then
            if other.getValue then
                other:destroy()
            end
        elseif tag == TAGS.CrumblingBlock then
            if col.normal.y == -1 then
                self.touchingGround = true
                self._peakY = nil
            end
            if other.onPlayerLanded then
                other:onPlayerLanded()
            end
        elseif tag == TAGS.BounceBlock then
            if col.normal.y == -1 then
                local targetY = self._peakY or (self.y - 20)
                self.yVelocity = BounceBlock.getBounceVelocity(GRAVITY, targetY, self.y)
                self._peakY    = targetY
                self.touchingGround = false
            end
        end
    end

    -- ← НОВОЕ: перепроверяем реальность после движения. Даже если коллизия
    -- в этом кадре сказала "приземлился" (что может быть неоднозначно из-за
    -- пограничного пересечения с только что созданным блоком), убеждаемся,
    -- что под ногами правда что-то есть.
    if self.touchingGround and not hasGroundBelow(self) then
        self.touchingGround = false
        self._peakY = self.y
    end
end

function DebtCollector:collisionResponse(other)
    if other.type == "Solid" then
        return gfx.sprite.kCollisionTypeSlide
    end

    local tag = other.getTag and other:getTag()
    if tag == TAGS.Block or tag == TAGS.BounceBlock
        or tag == TAGS.CrumblingBlock or tag == TAGS.KeyBlock then
        return gfx.sprite.kCollisionTypeSlide
    end

    return gfx.sprite.kCollisionTypeOverlap
end