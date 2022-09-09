local Device = require("device")

if not Device:isTouchDevice() then
    return { disabled = true }
end

local Editor = require("editor")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local PixelArt = WidgetContainer:new{
    name = "pixelart",
    is_doc_only = false,
}

function PixelArt:init()
    self.ui.menu:registerToMainMenu(self)
end

function PixelArt:addToMainMenu(menu_items)
    menu_items.pixelart = {
        text = "Pixel Art",
        sorting_hint = "more_tools",
        keep_menu_open = true,
        callback = function() self:onOpen() end,
    }
end

function PixelArt:onOpen()
    UIManager:show(Editor:new{})
end

return PixelArt