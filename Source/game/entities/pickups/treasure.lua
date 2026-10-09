local pd  <const> = playdate
local gfx <const> = playdate.graphics

import "libs/AnimatedSprite"
import "game/core/treasureManager"

-- game/entities/pickups/treasure.lua
-- Заменяет Coin. Все типы сокровищ используют один imagetable
-- treasure-table-16-16, различаются только диапазоном кадров и ценностью.
-- Парение вверх-вниз реализовано кодом (синус), а не спрайт-анимацией позиции.

class('Treasure').extends(AnimatedSprite)

local treasureImagetable = nil
treasureImagetable = gfx.imagetable.new("images/treasure-table-16-16")
assert(treasureImagetable, "Treasure: не удалось загрузить images/treasure-table-16-16")

-- ── Конфигурация типов ────────────────────────────────────────────────────────
-- first/last — диапазон кадров этого типа внутри общего imagetable (1-based)
local TREASURE_TYPES = {
    coin = {
        value = 50, --2
        first = 1, last = 1, tickStep = 4,
    },
    ring = {
        value = 80, --8
        first = 2, last = 2, tickStep = 4,
    },
    diamond = {
        value = 150, --18
        first = 3, last = 3, tickStep = 4,
    },
    crown = {
        value = 200, --28
        first = 4, last = 4, tickStep = 4,
    },
}

-- ── Параметры парения вверх-вниз ──────────────────────────────────────────────
local FLOAT_AMPLITUDE = 1.1     -- на сколько пикселей отклоняется от базовой Y
local FLOAT_SPEED     = 0.11  -- скорость колебания (рад/кадр)

function Treasure:init(x, y, kind, entity)
    kind = kind or "coin"
    local config = TREASURE_TYPES[kind]
    assert(config, "Treasure: неизвестный тип '" .. tostring(kind) .. "'")

    Treasure.super.init(self, treasureImagetable)

    self:addState("idle", config.first, config.last, {
        tickStep = config.tickStep,
        loop     = true,
    })

    self._kind  = kind
    self._value = config.value

    self._baseX      = x
    self._baseY      = y
    self._floatPhase = math.random() * math.pi * 2 -- случайная фаза, чтобы не парили синхронно

    self:setCenter(0.5, 0.5)
    self:moveTo(x, y)
    self:setCollideRect(4, 4, 8, 8) -- под 16x16 кадр, подгони при необходимости
    self:setZIndex(Z_INDEXES.Pickup)
    self:setTag(TAGS.Pickup)

    self.collected = false

    self:changeState("idle")
    self:playAnimation()

    print("[Treasure] spawned kind=" .. kind .. " value=" .. self._value .. " x=" .. x .. " y=" .. y)
end

function Treasure:getValue()
    return self._value
end

function Treasure:getKind()
    return self._kind
end

function Treasure:update()
    if isGamePaused() then
        return -- парение и анимация замирают, пока открыта книга или идёт диалог
    end

    -- Парение вверх-вниз через синус — плавно, без доп. кадров анимации
    self._floatPhase += FLOAT_SPEED
    local offsetY = math.sin(self._floatPhase) * FLOAT_AMPLITUDE
    self:moveTo(self._baseX, self._baseY + offsetY)

    self:updateAnimation()
end

-- Подбор игроком: начисляет очки и показывает всплывающий текст
function Treasure:collect()
    if self.collected then return end
    self.collected = true

    TreasureManager.addScore(self._value)

    if Game.instance and Game.instance.player then
        Game.instance.player:showScorePopup(self._value)
    end

    self:remove()
end

-- Тихое уничтожение без начисления очков и без попапа.
-- Используется, например, летающим врагом, который "съедает" монетки на своём пути.
function Treasure:destroy()
    if self.collected then return end
    self.collected = true

    print("[Treasure] уничтожено без начисления очков x=" .. self.x .. " y=" .. self.y)

    self:remove()
end