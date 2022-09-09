local Blitbuffer = require("ffi/blitbuffer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local Widget = require("ui/widget/widget")

-- reserve 2d space w/ bg
local Rect = FrameContainer:new{
    width = 0,
    height = 0,
    background = Blitbuffer.Color8(0xFF),
    bordersize = 0,
    padding = 0,
    Widget:new{ dimen = Geom:new{ w = 0, h = 0 } },
}

function Rect:init()
    self[1].dimen.w = self.width
    self[1].dimen.h = self.height
end

return Rect