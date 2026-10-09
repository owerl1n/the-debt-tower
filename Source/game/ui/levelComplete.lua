local pd   <const> = playdate
local gfx  <const> = playdate.graphics
local ease <const> = pd.easingFunctions

import "game/core/assets"

class('LevelComplete').extends()

-- Позиции текста порогов ОТНОСИТЕЛЬНО целевой (конечной) позиции картинки.
-- Порядок соответствует порядку порогов в self._thresholds.
local POS = {
    { x = 101, y = 64 },
    { x = 102, y = 80 },
}

-- ── Параметры анимации выезда снизу вверх ────────────────────────────────────
local TARGET_Y       = 60   -- конечная Y-позиция картинки (как было изначально)
local SLIDE_DISTANCE = 140  -- насколько ниже экрана стартует анимация — подстрой под себя
local SLIDE_DURATION = 400  -- мс — подстрой скорость выезда под себя

-- ── Алмаз слева от числа порога ───────────────────────────────────────────────
local GEM_OFFSET_X = -16    -- смещение алмаза по X относительно числа — подстрой
local GEM_OFFSET_Y = 0      -- смещение алмаза по Y относительно числа — подстрой

-- ── Надпись "Floor #x" над картинкой ──────────────────────────────────────────
local FLOOR_LABEL_OFFSET_Y = -42 -- насколько выше картинки рисуется надпись — подстрой

-- задержка перед тем как принимать ввод (чтобы не скипнуть случайно)
local INPUT_DELAY = 30  -- кадров


function LevelComplete:init(currentLevel, onNext, onRestart)
    self._active       = false
    self._image        = gfx.image.new("images/level_finished3")
    self._gemImage     = gfx.image.new("images/gem")
    assert(self._gemImage, "LevelComplete: не удалось загрузить images/gem")
    self._timer        = 0
    self._inputReady   = false
    self._currentLevel = currentLevel or 1
    self._onNext       = onNext    -- callback: следующий уровень
    self._onRestart    = onRestart -- callback: рестарт

    -- Пороги очков для звёзд этого уровня (см. game/core/scoreConfig.lua)
    self._thresholds = ScoreConfig.getStarThresholds(self._currentLevel)

    -- Текущая Y-позиция картинки/текста во время анимации выезда
    self._y          = TARGET_Y
    self._slideTimer = nil

    self._chosen = false
end

function LevelComplete:trigger()
    if self._active then return end
    self._active     = true
    self._chosen     = false
    self._timer      = 0
    self._inputReady = false

    if self._slideTimer then
        self._slideTimer:remove()
        self._slideTimer = nil
    end

    -- Стартуем ниже экрана и едем вверх к TARGET_Y через easeOut
    local startY = TARGET_Y + SLIDE_DISTANCE
    self._y = startY

    local timer = pd.timer.new(SLIDE_DURATION)
    self._slideTimer = timer

    timer.updateCallback = function(t)
        self._y = ease.outCubic(t.currentTime, startY, -SLIDE_DISTANCE, SLIDE_DURATION)
    end

    timer.timerEndedCallback = function()
        self._y = TARGET_Y
        self._slideTimer = nil
    end

    print("[LevelComplete] triggered")
end

function LevelComplete:isActive()
    return self._active
end

-- Сколько звёзд заработано при текущем счёте
function LevelComplete:getStarsEarned()
    local score = TreasureManager.score
    local stars = 0
    for i = 1, #self._thresholds do
        if score >= self._thresholds[i] then
            stars = i
        end
    end
    return stars
end

-- Мгновенно показывает экран финиша: без заезда снизу и без задержки
-- перед вводом. Используется при скипе игроком.
function LevelComplete:triggerInstant()
    if self._active then
        self:skipIntro()
        return
    end

    self._active     = true
    self._chosen     = false
    self._timer      = INPUT_DELAY
    self._inputReady = true

    if self._slideTimer then
        self._slideTimer:remove()
        self._slideTimer = nil
    end

    self._y = TARGET_Y

    print("[LevelComplete] triggered instantly (skip)")
end

-- Если экран уже активен, но ещё выезжает / ждёт задержки —
-- мгновенно доводит его до готового к вводу состояния.
function LevelComplete:skipIntro()
    if not self._active then return end

    if self._slideTimer then
        self._slideTimer:remove()
        self._slideTimer = nil
    end

    self._y          = TARGET_Y
    self._timer       = INPUT_DELAY
    self._inputReady  = true
end

function LevelComplete:isInputReady()
    return self._inputReady
end

function LevelComplete:update()
    if not self._active then return end
    if self._chosen then return end   -- выбор сделан, ждём конца фейда
    self._timer += 1

    if not self._inputReady and self._timer >= INPUT_DELAY then
        self._inputReady = true
    end

    if not self._inputReady then return end

    if pd.buttonJustPressed(pd.kButtonA) then
        self._chosen = true
        if self._onNext then self._onNext() end
    elseif pd.buttonJustPressed(pd.kButtonB) then
        self._chosen = true
        if self._onRestart then self._onRestart() end
    end
end

function LevelComplete:draw()
    if not self._active then return end

    local offsetY = self._y - TARGET_Y

    -- ── Надпись "Floor #x" ────────────────────────────────────────────────────
    local floorText   = "Floor #" .. tostring(self._currentLevel)
    local ftw, fth    = ScoreFont:getTextWidth(floorText), ScoreFont:getHeight()

    gfx.setImageDrawMode(gfx.kDrawModeFillBlack)
    ScoreFont:drawText(
        floorText,
        100 - ftw / 2,
        self._y + FLOOR_LABEL_OFFSET_Y - fth / 2
    )

    -- ── Картинка результата ───────────────────────────────────────────────────
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    self._image:drawCentered(100, self._y)

    -- ── Пороги очков + алмазы ─────────────────────────────────────────────────
    local entries = {
        { threshold = self._thresholds[1], textX = 101, textY = self._y + 4,  gemX = 85, gemY = self._y + 4 },
        { threshold = self._thresholds[2], textX = 102, textY = self._y + 20, gemX = 86, gemY = self._y + 20 },
    }
    LevelStatsPanel.draw(entries, TreasureManager.score, self._gemImage, MonogramFont)
end