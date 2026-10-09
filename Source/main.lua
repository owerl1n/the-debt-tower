import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"
import "CoreLibs/crank"
import "CoreLibs/nineslice"

import "libs/AnimatedSprite"
import "libs/SceneManager"
import "libs/LDtk"
import "libs/pdDialogue"

import "game/core/game"
import "game/core/assets"
import "game/core/level"
import "game/core/treasureManager"
import "game/core/scoreConfig"
import "game/core/saveManager"

import "game/entities/player/player"
import "game/entities/player/promptHint"
import "game/entities/player/scorePopup"
import "game/entities/player/taxIndicator"
import "game/entities/player/projectile"
import "game/entities/hazards/crumblingBlock"
import "game/entities/hazards/exit"
import "game/entities/hazards/spike"
import "game/entities/hazards/portal"
import "game/entities/hazards/bounceBlock"
import "game/entities/hazards/keyBlock"
import "game/entities/pickups/treasure"
import "game/entities/pickups/key"
import "game/entities/npc/npc"
import "game/entities/enemies/flyingEnemy"
import "game/entities/enemies/debtCollector"
import "game/entities/effects/taxZoneTile"
import "game/entities/effects/smokeEffect"
import "game/entities/blocks/placedBlock"
import "game/entities/blocks/anchorMarker"
import "game/entities/blocks/blockIndicator"

import "game/ui/levelComplete"
import "game/ui/levelStatsPanel"

import "game/spells/spellbook"


import "scenes/SplashScene"
import "scenes/GameScene"
import "scenes/TitleScene"
import "scenes/LevelSelectScene"

local pd  <const> = playdate
local gfx <const> = pd.graphics

local myFont = gfx.font.new("fonts/Bongo-8-Mono")
assert(myFont, "failed to load fonts/MyFont")
local dialogueFrame = gfx.nineSlice.new("images/nineslice-kenney-2", 6, 6, 4, 4)
assert(dialogueFrame, "cant find nineslice-kenney-2")

SceneManager.register("splash", SplashScene)
SceneManager.register("game",   GameScene)
SceneManager.register("title", TitleScene)
SceneManager.register("levelSelect", LevelSelectScene)


pdDialogue.set("width", 190)
pdDialogue.set("height", 28)
pdDialogue.set("x", 5)
pdDialogue.set("y", 90)
pdDialogue.set("padding", 6)
pdDialogue.set("font", ScoreFont)
pdDialogue.set("drawPrompt", function(self, x, y) end)
pdDialogue.set("nineSlice", dialogueFrame)

SaveManager.load()

pd.display.setScale(2)
--gfx.setDrawOffset(0, 0)
SceneManager.go("splash", nil, SceneManager.transitions.cut)


function pd.update()
    SceneManager.update()
    gfx.sprite.update()
    SceneManager.drawOverlay()
    pdDialogue.update()
    pd.timer.updateTimers()
    pd.drawFPS(1,1)
end

function pd.cranked(change, acceleratedChange)
    SceneManager.cranked(change, acceleratedChange)
end