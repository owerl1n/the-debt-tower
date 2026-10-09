local pd  <const> = playdate
local gfx <const> = playdate.graphics
local ease <const> = pd.easingFunctions

import "libs/AnimatedSprite"
import "game/spells/spells"
import "game/core/assets"

class('SpellBook').extends(AnimatedSprite)

local BOOK_W       = 107
local TARGET_X     = 100
local TARGET_Y     = 50
local OFFSCREEN_X  = 204 + BOOK_W / 2

local SLIDE_IN_MS  = 350
local SLIDE_OUT_MS = 250

-- Позиции иконок внутри книги (относительно центра книги)
local ICON_OFFSET_Y_TOP    = -28
local ICON_OFFSET_Y_MID    =  -4
local ICON_OFFSET_Y_BOTTOM =  20
local ICON_SCALE           = 1.0

imagetable = gfx.imagetable.new("images/book-table-113-108")
assert(imagetable, "SpellBook: не удалось загрузить images/book-table-113-108")

-- ── SpellBook ─────────────────────────────────────────────────────────────────

function SpellBook:init(levelComplete, onSpellSelected)

    SpellBook.super.init(self, imagetable)

    self._levelComplete = levelComplete

    self:addState("opening", 1, 9, {
        tickStep = 4,
        loop = false,
        onAnimationEndEvent = function(sprite)
            sprite:changeState("open")
        end
    })

    self:addState("open", 10, 10, {})

    self:addState("closing", 11, 14, {
        tickStep = 4,
        loop = false,
        onAnimationEndEvent = function(sprite)
            sprite:_startSlideOut()
        end
    })

    self:setCenter(0.5, 0.5)
    self:moveTo(OFFSCREEN_X, TARGET_Y)
    self:setZIndex(500)

    self._bookState  = "closed"
    self._slideTimer = nil

    self._glyphs = Glyphs

    self._selectedSlot    = 1

    self._onSpellSelected = onSpellSelected
end

-- ── Публичный API ─────────────────────────────────────────────────────────────

function SpellBook:isActive()
    return self._bookState ~= "closed"
end

function SpellBook:onButtonB()
    if self._bookState == "closed" then
        if self._levelComplete and self._levelComplete:isActive() then return end
        self:_open()
    elseif self._bookState == "sliding_in" or self._bookState == "open" then
        self:_close()
    end
end

function SpellBook:onButtonA()
    if self._bookState == "sliding_in" or self._bookState == "open" then
        self:_close()
    end
end

-- Вызывать из Game:handleInput() когда книга открыта
function SpellBook:onUp()
    if self._bookState ~= "open" then return end
    local prev = (self._selectedSlot - 2) % #SPELLS + 1
    self:_selectSlot(prev)
end

function SpellBook:onDown()
    if self._bookState ~= "open" then return end
    local next = self._selectedSlot % #SPELLS + 1
    self:_selectSlot(next)
end

function SpellBook:update()
    self:updateAnimation()
end

function SpellBook:draw()
    if self._bookState == "closed" then return end

    local img = self._image
    if img then
        img:drawCentered(math.floor(self.x), math.floor(self.y))
    end

    if self._bookState == "open" then
        self:_drawIcons()
    end
end

-- ── Внутренние: выбор слота ───────────────────────────────────────────────────

function SpellBook:_selectSlot(slot)
    if self._selectedSlot == slot then return end
    self._selectedSlot = slot
    print("[SpellBook] выбрано: слот " .. slot .. " (" .. (SPELLS[slot] and SPELLS[slot].name or "?") .. ")")
end

function SpellBook:_drawIcons()
    if not self._glyphs then return end

    local bx = math.floor(self.x)
    local by = math.floor(self.y)

    local offsets = {
        ICON_OFFSET_Y_TOP,
        ICON_OFFSET_Y_MID,
        ICON_OFFSET_Y_BOTTOM,
    }

    local xOffsets = { 30, 18, 0 }

    for i = 1, math.min(#SPELLS, 3) do
        local spell = SPELLS[i]
        local icon  = self._glyphs[spell.glyph]
        if not icon then goto continue end

        local iw, ih = icon:getSize()
        local cx = bx + xOffsets[i]
        local cy = by + offsets[i]

        icon:draw(math.floor(cx - iw / 2), math.floor(cy - ih / 2))

        if self._selectedSlot == i then
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRect(
                math.floor(cx - iw / 2) - 6,
                math.floor(cy - 3),
                4, 6
            )
        end

        ::continue::
    end
end

-- ── Внутренние: анимация ──────────────────────────────────────────────────────

function SpellBook:_open()
    self._bookState  = "sliding_in"
    self:moveTo(OFFSCREEN_X, TARGET_Y)
    self:changeState("opening")
    self:playAnimation()
    self:_startSlideIn()
end

function SpellBook:_close()
    if self._slideTimer then
        self._slideTimer:remove()
        self._slideTimer = nil
    end
    if self._onSpellSelected then
        self._onSpellSelected(self._selectedSlot)
    end
    self._bookState = "closing"
    self:moveTo(TARGET_X, TARGET_Y)
    self:changeState("closing")
    self:playAnimation()
end

function SpellBook:_startSlideIn()
    if self._slideTimer then self._slideTimer:remove() end

    local startX = OFFSCREEN_X
    local dist   = TARGET_X - startX

    local timer = pd.timer.new(SLIDE_IN_MS)
    self._slideTimer = timer

    timer.updateCallback = function(t)
        local x = ease.outBack(t.currentTime, startX, dist, SLIDE_IN_MS)
        self:moveTo(x, TARGET_Y)
    end

    timer.timerEndedCallback = function()
        self:moveTo(TARGET_X, TARGET_Y)
        self._bookState  = "open"
        self._slideTimer = nil
    end
end

function SpellBook:_startSlideOut()
    if self._slideTimer then self._slideTimer:remove() end

    self._bookState = "sliding_out"
    local startX = TARGET_X
    local dist   = OFFSCREEN_X - startX

    local timer = pd.timer.new(SLIDE_OUT_MS)
    self._slideTimer = timer

    timer.updateCallback = function(t)
        local x = ease.inCubic(t.currentTime, startX, -dist, SLIDE_OUT_MS)
        self:moveTo(x, TARGET_Y)
    end

    timer.timerEndedCallback = function()
        self:moveTo(OFFSCREEN_X, TARGET_Y)
        self._bookState  = "closed"
        self._slideTimer = nil
    end
end