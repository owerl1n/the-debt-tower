local gfx <const> = playdate.graphics



Tileset = gfx.imagetable.new("level/tileset-table-16-16")
assert(Tileset, "Tileset: не удалось загрузить level/tileset-table-16-16")


Glyphs = gfx.imagetable.new("images/glyphs-table-16-16")
assert(Glyphs, "Assets: не удалось загрузить images/glyphs-table-16-16")

ScoreFont = gfx.font.new("fonts/Bongo-8-Mono")
assert(ScoreFont, "failed to load fonts/MyFont")

MonogramFont = gfx.font.new("fonts/monogram")
assert(MonogramFont, "failed to load fonts/monogram")

-- Мелкий пиксельный шрифт для даты/времени на чеке главного меню
Font3x3Mono = gfx.font.new("fonts/3x3-Mono")
assert(Font3x3Mono, "failed to load fonts/3x3-Mono")