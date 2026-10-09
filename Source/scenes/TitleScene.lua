-- Source/scenes/TitleScene.lua
local pd  <const> = playdate
local gfx <const> = pd.graphics

TitleScene = {}

local SCREEN_HEIGHT = 120
local SLIDE_OUT_MS  = 450 -- уезжание вниз при переходе в выбор уровня
local SLIDE_IN_MS   = 450 -- выезд снизу при возврате из выбора уровня

local function loadImage(self)
    self._image = gfx.image.new("images/splash2")
    assert(self._image, "TitleScene: не удалось загрузить images/splash")
end

function TitleScene:enter(params)
    gfx.setDrawOffset(0, 0)
    gfx.sprite.removeAll()

    self._image      = nil
    self._ready      = false
    self._leaving    = false
    self._offsetY    = 0
    self._slideTimer = nil
    self._introTimer = nil

    if params and params.fromLevelSelect then
        -- возврат из выбора уровня: грузим сразу и выезжаем снизу
        loadImage(self)

        self._offsetY = SCREEN_HEIGHT
        local timer = pd.timer.new(SLIDE_IN_MS, SCREEN_HEIGHT, 0)
        timer.easingFunction = pd.easingFunctions.outCubic
        timer.updateCallback = function(t)
            self._offsetY = t.value
        end
        timer.timerEndedCallback = function()
            self._offsetY    = 0
            self._introTimer = nil
            self._ready      = true
        end
        self._introTimer = timer
    else
        -- после loading-картинки: грузим меню за чёрным кадром
        SceneManager.flashBlack(1, function()
            loadImage(self)
        end)

        self._inputTimer = pd.timer.performAfterDelay(300, function()
            self._ready = true
        end)
    end

    -- DEBUG: сброс сейва, доступен только в симуляторе
    if pd.isSimulator then
        self._debugMenuItem = pd.getSystemMenu():addMenuItem("Reset Save (DEBUG)", function()
            SaveManager.reset()
            print("[DEBUG] сейв сброшен")
        end)
    end
end

function TitleScene:exit()
    if self._inputTimer then
        self._inputTimer:remove()
        self._inputTimer = nil
    end
    if self._slideTimer then
        self._slideTimer:remove()
        self._slideTimer = nil
    end
    if self._introTimer then
        self._introTimer:remove()
        self._introTimer = nil
    end

    if self._debugMenuItem then
        pd.getSystemMenu():removeMenuItem(self._debugMenuItem)
        self._debugMenuItem = nil
    end
end

function TitleScene:update()
    if not self._ready then return end
    if SceneManager.isTransitioning() then return end

    if pd.buttonJustPressed(pd.kButtonA) then
        self._ready = false
        SceneManager.go("game", { level = SaveManager.getCurrentLevel() }, SceneManager.transitions.fade)
    elseif pd.buttonJustPressed(pd.kButtonB) then
        self._ready = false
        self:_slideOutToLevelSelect()
    end
end

function TitleScene:_slideOutToLevelSelect()
    if self._leaving or not self._image then return end
    self._leaving = true

    local timer = pd.timer.new(SLIDE_OUT_MS, 0, SCREEN_HEIGHT)
    timer.easingFunction = pd.easingFunctions.inCubic
    timer.updateCallback = function(t)
        self._offsetY = t.value
    end
    timer.timerEndedCallback = function()
        self._offsetY    = SCREEN_HEIGHT
        self._slideTimer = nil
        SceneManager.go("levelSelect", { fromTitle = true }, SceneManager.transitions.cut)
    end
    self._slideTimer = timer
end

function TitleScene:draw()
    if self._offsetY ~= 0 then
        gfx.clear(gfx.kColorWhite) -- цвет фона твоих картинок
    end
    if self._image then
        local w, h = self._image:getSize()
        self._image:draw(100 - w / 2, 60 - h / 2 + self._offsetY)
    end
end

return TitleScene