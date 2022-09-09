local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Screen = Device.screen
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local Widget = require("ui/widget/widget")

local Item = InputContainer:new{
    text = nil,
    icon = nil,
    callback = function () end,
    dim = function () return false end,
    width = nil,
    height = nil,
    background = nil,
    size = nil,
    dark = nil,
    show_parent = nil,
}

function Item:init()
    self.dimen = Geom:new{
        w = self.width,
        h = self.height,
    }

    self.ges_events = {
        TapButton = {
            GestureRange:new{
                ges = "tap",
                range = function () return self.dimen end,
            },
        },
    }

    if self.icon then
        self.content = ImageWidget:new{
            file = "plugins/pixelart.koplugin/icons/" .. (type(self.icon) == "function" and self.icon(self.show_parent) or self.icon) .. ".png",
            width = 72,
            height = 72,
            alpha = true,
            show_parent = self.show_parent,
        }
    else
        self.content = TextWidget:new{
            text = self.text or "",
            face = Font:getFace("infofont", 24),
            show_parent = self.show_parent,
        }
    end

    self[1] = FrameContainer:new{
        width = self.dimen.w,
        height = self.dimen.h,
        padding = 0,
        margin = 0,
        bordersize = 0,
        background = (self.background and type(self.background) ~= "function") and (self.dark and self.background:invert() or self.background) or Blitbuffer.COLOR_WHITE,
        show_parent = self.show_parent,
        CenterContainer:new{
            dimen = Geom:new{
                w = self.dimen.w,
                h = self.dimen.h,
            },
            show_parent = self.show_parent,
            self.content,
        },
    }
end

function Item:paintTo(bb, x, y)
    if type(self.background) == "function" then -- background needs updating
        self[1].background = self.background(self.show_parent)
        if self.dark then self[1].background = self[1].background:invert() end
    end

    if type(self.icon) == "function" and ("plugins/pixelart.koplugin/icons/" .. self.icon(self.show_parent) .. ".png") ~= self.content.file then -- icon needs updating
        self.content:free()
        self.content = ImageWidget:new{
            file = "plugins/pixelart.koplugin/icons/" .. self.icon(self.show_parent) .. ".png",
            width = 72,
            height = 72,
            alpha = true,
            show_parent = self.show_parent,
        }
        self[1][1][1] = self.content
    end

    InputContainer.paintTo(self, bb, x, y) -- paint image/text

    if self.size then -- draw size circle
        bb:paintCircle(x + self.dimen.w / 2, y + self.dimen.h / 2, (type(self.size) == "function" and self.size(self.show_parent) or self.size) * 2, Blitbuffer.COLOR_BLACK)
    end

    if self.icon or self.size then -- lower contrast for more modern design
        bb:dimRect(x, y, self.dimen.w, self.dimen.h, 0.2)
    end

    if self[1].background ~= Blitbuffer.COLOR_WHITE then -- make bg have rounded edges
        bb:paintBorder(x, y, self.dimen.w, self.dimen.h, 12, Blitbuffer.COLOR_WHITE)
        bb:paintBorder(x + 4, y + 4, self.dimen.w - 8, self.dimen.h - 8, 8, Blitbuffer.COLOR_WHITE, 20)
    end

    if self.menu then -- menu arrow thingy!
        for i = 0, 16 do
            bb:paintRect(x + 16 - i + self.dimen.w - 16, y + i + self.dimen.h - 16, i, 1, Blitbuffer.Color8(0xFF * 0.2))
        end
    end

    if self.dark then -- hidden dark mode
        bb:invertRect(x, y, self.dimen.w, self.dimen.h)
    end

    if self.dim(self.show_parent) then -- outline if selected
        bb:paintBorder(x + 8, y + 8, self.dimen.w - 16, self.dimen.h - 16, 4, Blitbuffer.Color8(self.dark and 0x55 or 0xBB), 16)
    end
end

function Item:onTapButton()
    self.callback(self.show_parent)

    UIManager:setDirty(self.show_parent, function ()
        return "ui", self.show_parent.dimen
    end)

    return true
end

return Item