-- Source/scenes/LevelSelectScene.lua
local pd  <const> = playdate
local gfx <const> = pd.graphics

LevelSelectScene = {}

local SCREEN_HEIGHT = 120

local SLIDE_IN_MS  = 450 -- выезд снизу при входе с титульника
local SLIDE_OUT_MS = 450 -- уезжание вниз при выходе на титульник

-- ── PSP-style повтор кнопок ───────────────────────────────────────────────────
local INITIAL_REPEAT_DELAY = 300 -- мс до начала быстрого повтора
local REPEAT_INTERVAL      = 60  -- мс между повторами во время быстрой фазы

-- ── Кранк → выбор уровня (по чуть-чуть, не свободный скролл) ─────────────────
local CRANK_DEGREES_PER_STEP = 20 -- градусов кранка на один уровень — подстрой

-- ── Панель стрелок + статистики уровня (справа от центра экрана) ────────────
local ARROW_UP_IDLE      = 1
local ARROW_UP_PRESSED   = 2
local ARROW_DOWN_IDLE    = 3
local ARROW_DOWN_PRESSED = 4

local PANEL_X   = 100 -- X-центр блока (стрелки + статистика) — подстрой
local PANEL_GAP = 4   -- зазор между стрелками и картинкой статистики — подстрой

-- ── Надпись текущего уровня ───────────────────────────────────────────────────
local LEVEL_LABEL_X = 160 -- X-центр надписи "#N" — подстрой
local LEVEL_LABEL_Y = 42  -- Y надписи "#N" — подстрой

function LevelSelectScene:_loadAssets()
    -- self._image = gfx.image.new("images/level_select2")
    -- assert(self._image, "LevelSelectScene: не удалось загрузить images/level_select2")

    self._arrowTable = gfx.imagetable.new("images/arrow-table-21-9")
    assert(self._arrowTable, "LevelSelectScene: не удалось загрузить images/arrow-table-21-9")

    self._statsImage = gfx.image.new("images/level_select2")
    assert(self._statsImage, "LevelSelectScene: не удалось загрузить images/level_finished3")

    self._gemImage = gfx.image.new("images/gem")
    assert(self._gemImage, "LevelSelectScene: не удалось загрузить images/gem")

    self._monogramFont = gfx.font.new("fonts/monogram")
    assert(self._monogramFont, "LevelSelectScene: не удалось загрузить fonts/monogram")
end

function LevelSelectScene:enter(params)
    gfx.setDrawOffset(0, 0)
    gfx.sprite.removeAll()

    self._image        = nil
    self._arrowTable   = nil
    self._statsImage   = nil
    self._gemImage     = nil
    self._monogramFont = nil

    local world = json.decodeFile("level/world.ldtk")
    self._totalLevels = (world and #world.levels) or 1

    local saved = SaveManager.getCurrentLevel()
    self._selectedLevel = math.max(1, math.min(self._totalLevels, saved))

    self._upState    = { heldSince = nil, nextRepeat = nil }
    self._downState  = { heldSince = nil, nextRepeat = nil }
    self._crankAccum = 0

    self._offsetY    = 0     -- общий вертикальный сдвиг сцены при анимациях
    self._slideTimer = nil
    self._leaving    = false

    if params and params.fromTitle then
        -- пришли с титульника: грузим сразу и выезжаем снизу
        self:_loadAssets()

        self._offsetY = SCREEN_HEIGHT
        local timer = pd.timer.new(SLIDE_IN_MS, SCREEN_HEIGHT, 0)
        timer.easingFunction = pd.easingFunctions.outCubic
        timer.updateCallback = function(t)
            self._offsetY = t.value
        end
        timer.timerEndedCallback = function()
            self._offsetY    = 0
            self._slideTimer = nil
        end
        self._slideTimer = timer
    else
        -- из других мест (например, из игры) поведение прежнее
        SceneManager.flashBlack(1, function()
            self:_loadAssets()
        end)
    end
end

function LevelSelectScene:exit()
    if self._slideTimer then
        self._slideTimer:remove()
        self._slideTimer = nil
    end
end

function LevelSelectScene:_changeSelection(delta)
    local newLevel = math.max(1, math.min(self._totalLevels, self._selectedLevel + delta))
    if newLevel == self._selectedLevel then return end
    self._selectedLevel = newLevel
end

-- Уезжаем вниз и без перехода включаем титульник, который выедет снизу
function LevelSelectScene:_slideOutToTitle()
    if self._leaving then return end
    self._leaving = true

    local timer = pd.timer.new(SLIDE_OUT_MS, 0, SCREEN_HEIGHT)
    timer.easingFunction = pd.easingFunctions.inCubic
    timer.updateCallback = function(t)
        self._offsetY = t.value
    end
    timer.timerEndedCallback = function()
        self._offsetY    = SCREEN_HEIGHT
        self._slideTimer = nil
        SceneManager.go("title", { fromLevelSelect = true }, SceneManager.transitions.cut)
    end
    self._slideTimer = timer
end

-- Обрабатывает одну кнопку с PSP-style повтором: сразу шаг на 1,
-- затем пауза, затем быстрый повтор пока кнопка удерживается.
function LevelSelectScene:_handleRepeatButton(button, sign, state, now)
    if pd.buttonJustPressed(button) then
        self:_changeSelection(sign)
        state.heldSince  = now
        state.nextRepeat = now + INITIAL_REPEAT_DELAY
    elseif pd.buttonIsPressed(button) then
        if state.heldSince and now >= state.nextRepeat then
            self:_changeSelection(sign)
            state.nextRepeat = now + REPEAT_INTERVAL
        end
    elseif pd.buttonJustReleased(button) then
        state.heldSince  = nil
        state.nextRepeat = nil
    end
end

function LevelSelectScene:update()
    if SceneManager.isTransitioning() then return end
    if self._slideTimer or self._leaving then return end -- ввод заблокирован на время анимации

    local now = pd.getCurrentTimeMilliseconds()
    self:_handleRepeatButton(pd.kButtonUp,   1, self._upState,   now)
    self:_handleRepeatButton(pd.kButtonDown, -1, self._downState, now)

    if pd.buttonJustPressed(pd.kButtonA) then
        SceneManager.go("game", { level = self._selectedLevel }, SceneManager.transitions.fade)
    elseif pd.buttonJustPressed(pd.kButtonB) then
        self:_slideOutToTitle()
    end
end

function LevelSelectScene:cranked(change, acceleratedChange)
    if self._slideTimer or self._leaving then return end

    self._crankAccum += change

    while self._crankAccum >= CRANK_DEGREES_PER_STEP do
        self._crankAccum -= CRANK_DEGREES_PER_STEP
        self:_changeSelection(1)
    end
    while self._crankAccum <= -CRANK_DEGREES_PER_STEP do
        self._crankAccum += CRANK_DEGREES_PER_STEP
        self:_changeSelection(-1)
    end
end

function LevelSelectScene:draw()
    local shifted = self._offsetY ~= 0
    if shifted then
        gfx.clear(gfx.kColorWhite) -- тот же цвет фона, что и в TitleScene
        gfx.setDrawOffset(0, self._offsetY)
    end

    -- if self._image then
    --     self._image:draw(0, 0)
    -- end

    self:_drawSidePanel()
    self:_drawLevelLabel()

    if shifted then
        gfx.setDrawOffset(0, 0)
    end
end

function LevelSelectScene:_drawLevelLabel()
    if not self._monogramFont then return end

    local text = "#" .. tostring(self._selectedLevel)
    local tw   = self._monogramFont:getTextWidth(text)

    gfx.setImageDrawMode(gfx.kDrawModeFillBlack)
    self._monogramFont:drawText(text, LEVEL_LABEL_X - tw / 2, LEVEL_LABEL_Y)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

function LevelSelectScene:_drawSidePanel()
    if not self._arrowTable or not self._statsImage then return end

    local upFrame   = pd.buttonIsPressed(pd.kButtonUp)   and ARROW_UP_PRESSED   or ARROW_UP_IDLE
    local downFrame = pd.buttonIsPressed(pd.kButtonDown) and ARROW_DOWN_PRESSED or ARROW_DOWN_IDLE

    local upImg   = self._arrowTable[upFrame]
    local downImg = self._arrowTable[downFrame]

    local _, upH    = upImg:getSize()
    local _, downH  = downImg:getSize()
    local _, statsH = self._statsImage:getSize()

    local totalHeight = upH + PANEL_GAP + statsH + PANEL_GAP + downH
    local topY        = 60 - totalHeight / 2

    local upY    = topY
    local statsY = upY + upH + PANEL_GAP
    local downY  = statsY + statsH + PANEL_GAP

    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    upImg:drawCentered(PANEL_X, upY + upH / 2)
    self._statsImage:drawCentered(PANEL_X, statsY + statsH / 2)
    downImg:drawCentered(PANEL_X, downY + downH / 2)

    -- ── Пороги очков + алмазы для выбранного уровня ─────────────────────────
    if self._gemImage and self._monogramFont then
        local thresholds = ScoreConfig.getStarThresholds(self._selectedLevel)
        local savedScore = SaveManager.getLevelScore(self._selectedLevel)

        local entries = {
            { threshold = thresholds[1], textX = 122, textY = 62, gemX = 163, gemY = 62 },
            { threshold = thresholds[2], textX = 122, textY = 75, gemX = 163, gemY = 75 },
        }
        LevelStatsPanel.draw(entries, savedScore, self._gemImage, MonogramFont)
    end
end

return LevelSelectScene