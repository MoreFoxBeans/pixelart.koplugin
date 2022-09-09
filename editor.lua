local Blitbuffer = require("ffi/blitbuffer")
local Canvas = require("canvas")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Event = require("ui/event")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local Item = require("item")
local OverlapGroup = require("ui/widget/overlapgroup")
local PathChooser = require("ui/widget/pathchooser")
local Rect = require("rect")
local Screen = Device.screen
local SubMenu = require("submenu")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiutil = require("ffi/util")

local dark = false -- hidden dark mode? might make an official feature

local colors = { 0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF }
local sizes = { 1, 2, 3, 4, 5, 6, 8, 10, 20 }

--[[ Sidebar buttons (try adding one!)
    icon (load icon from plugins/pixelart.koplugin/icons)
    text (ugly text, use only as a placeholder)
    tool (select this tool when tapped)
    menu (open this menu when tapped)
    callback (run this when tapped)
    dim (draw grey border if true)
    background (set the button background)
    size (draw a black circle this size)
    seperator (add a gap after this button)
]]
local button_info = {
    {
        icon = "menu",
        menu = "menu",
        seperator = true,
    },
    {
        icon = "pencil",
        tool = "pencil",
    },
    {
        icon = "eraser",
        tool = "eraser",
    },
    {
        icon = "eyedropper",
        tool = "picker",
    },
    {
        icon = "line",
        tool = "line",
    },
    {
        icon = function (self) return self.fill and "rectanglefill" or "rectangle" end,
        tool = "rect",
    },
    {
        icon = function (self) return self.fill and "circlefill" or "circle" end,
        tool = "circle",
    },
    {
        icon = function (self) return self.fill_tool end,
        menu = "fill",
        callback = function (self) if self.tool == self.fill_tool then self:updateMenu("fill") else self.tool = self.fill_tool end end,
        dim = function (self) return self.tool == "fill" or self.tool == "filldiag" or self.tool == "fillall" end,
    },
    {
        icon = "pan",
        tool = "pan",
        seperator = true,
    },
    {
        icon = "view",
        menu = "view",
    },
    {
        icon = "grid",
        callback = function (self) self.canvas:setGrid(not self.canvas:getGrid()) end,
        dim = function (self) return self.canvas:getGrid() end,
    },
    {
        icon = "refresh",
        callback = function (self) self:refresh() end,
        seperator = true,
    },
    {
        menu = "sizes",
        size = function (self) return self.size end,
    },
    {
        menu = "colors",
        background = function (self) return Blitbuffer.Color8(self.color) end,
    },
}

-- Submenus (ibid.)
local menu_buttons = {
    ["colors"] = {
        {
            icon = "fill",
            callback = function (self) self.fill = not self.fill end,
            dim = function (self) return self.fill end,
        },
    },
    ["sizes"] = {},
    ["menu"] = {
        {
            icon = "resize",
            callback = function (self) self:resizeCanvas() end,
        },
        {
            icon = "grid",
            callback = function (self) self:resizeGrid() end,
        },
        {
            icon = "new",
            callback = function (self) self:newImage() end,
        },
        {
            icon = "save",
            callback = function (self) self:saveImage() end,
        },
        {
            icon = "load",
            callback = function (self) self:loadImage() end,
        },
        {
            icon = "close",
            callback = function (self) self:quit() end,
        },
    },
    ["fill"] = {
        {
            icon = "fill",
            callback = function (self) self.tool = "fill" self.fill_tool = "fill" self:updateMenu("none") end,
            dim = function (self) return self.tool == "fill" end,
        },
        {
            icon = "filldiag",
            callback = function (self) self.tool = "filldiag" self.fill_tool = "filldiag" self:updateMenu("none") end,
            dim = function (self) return self.tool == "filldiag" end,
        },
        {
            icon = "fillall",
            callback = function (self) self.tool = "fillall" self.fill_tool = "fillall" self:updateMenu("none") end,
            dim = function (self) return self.tool == "fillall" end,
        },
    },
    ["view"] = {
        {
            icon = "minus",
            callback = function (self) self.canvas:zoomOut() end,
        },
        {
            icon = "plus",
            callback = function (self) self.canvas:zoomIn() end,
        },
        {
            icon = "center",
            callback = function (self) self.canvas:center() end,
        },
    },
}

local button_size = 108 -- self-explanatory
local sep_size = (Screen:getHeight() - #button_info * button_size) / 3 -- Even space btwn button groups

-- Add color options
for i = 1, #colors do
    table.insert(menu_buttons["colors"], #menu_buttons["colors"], {
        callback = function (self) self.color = colors[i] end,
        dim = function (self) return self.color == colors[i] end,
        background = Blitbuffer.Color8(colors[i]),
        width = button_size / 1.75,
    })
end

-- Add size options
for i = 1, #sizes do
    table.insert(menu_buttons["sizes"], {
        callback = function (self) self.size = sizes[i] end,
        dim = function (self) return self.size == sizes[i] end,
        size = sizes[i],
    })
end

local night = false

local function setNight(night)
    if not(G_reader_settings:nilOrFalse("night_mode")) ~= night then
        UIManager:broadcastEvent(Event:new("ToggleNightMode"))
    end
end

local Editor = InputContainer:new{
    title = "Pixel Art",
    covers_fullscreen = true,

    tool = "pencil",
    color = 0x00,
    size = 1,
    fill = false,
    fill_tool = "fill",

    top = "colors",
    last_path = ffiutil.realpath(DataStorage:getDataDir()),
}

function Editor:init()
    self.dimen = Geom:new{
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }

    self.canvas = Canvas:new{
        width = self.dimen.w - button_size,
        height = self.dimen.h,
        show_parent = self,
        dark = dark,

        image_w = 64,
        image_h = 64,
    }

    self.buttons = VerticalGroup:new{ show_parent = self, }
    self:addButtons()

    local content = HorizontalGroup:new{
        show_parent = self,
        align = "top",
        self.buttons,
        Rect:new{ width = 4, height = self.dimen.h, background = Blitbuffer.Color8(dark and 0x55 or 0xBB) },
        self.canvas,
    }

    self.submenu = SubMenu:new{ dark = dark, show_parent = self, }
    self:updateMenu(self.menu)

    self.submenu_y = VerticalSpan:new{ width = 0 }

    self.submenu_overlay = VerticalGroup:new{
        show_parent = self,
        self.submenu_y,
        self.submenu,
    }

    local overlay = OverlapGroup:new{
        dimen = Geom:new{
            w = self.dimen.w,
            h = self.dimen.h,
        },
        show_parent = self,
        content,
        HorizontalGroup:new{
            show_parent = self,
            HorizontalSpan:new{ width = button_size },
            self.submenu_overlay,
        },
    }

    self[1] = FrameContainer:new{
        width = self.dimen.w,
        height = self.dimen.h,
        padding = 0,
        margin = 0,
        bordersize = 0,
        background = dark and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
        overlay,
    }

    -- turn to day mode
    night = not(G_reader_settings:nilOrFalse("night_mode"))
    setNight(false)

    self:refresh()
end

-- Generate callback and dim for menu and tool values
function Editor:getCallback(item)
    local callback, dim

    if item.menu then
        callback = function (self) self:updateMenu(item.menu) end
        dim = function (self) return self.menu == item.menu end
    elseif item.tool then
        callback = function (self) self.tool = item.tool end
        dim = function (self) return self.tool == item.tool end
    else
        callback = item.callback
        dim = item.dim
    end

    return { callback = item.callback or callback, dim = item.dim or dim }
end

-- Add buttons to left bar
function Editor:addButtons()
    self.buttons:clear()

    local y = 0
    
    for i = 1, #button_info do
        local f = self:getCallback(button_info[i])

        local item = Item:new{
            text = button_info[i].name,
            icon = button_info[i].icon,
            callback = f.callback,
            dim = f.dim,
            width = button_info[i].width or button_size,
            height = button_info[i].height or button_size,
            background = button_info[i].background,
            size = button_info[i].size,
            menu = button_info[i].menu,
            dark = dark,
            show_parent = self,
        }

        table.insert(self.buttons, item)

        -- Tell the submenu what its parent is
        if button_info[i].menu then
            menu_buttons[button_info[i].menu].index = i
        end

        -- Y pos for submenu
        button_info[i].y = y

        y = y + (button_info[i].height or button_size)

        if button_info[i].seperator then
            table.insert(self.buttons, VerticalSpan:new{ width = sep_size })
            y = y + sep_size
        end
    end
end

-- Update submenu
function Editor:updateMenu(page)
    if self.menu == page then
        page = "none"
    end

    local p = menu_buttons[page]

    if p then
        self.menu = page
        self.submenu:clear()

        self.submenu_y.width = button_info[p.index].y
        self.submenu_overlay:resetLayout()

        for i = 1, #p do
            local f = self:getCallback(p[i])

            table.insert(self.submenu, Item:new{
                text = p[i].name,
                icon = p[i].icon,
                callback = f.callback,
                dim = f.dim,
                width = p[i].width or button_size,
                height = p[i].height or button_size,
                background = p[i].background,
                size = p[i].size,
                index = p.index,
                dark = dark,
                show_parent = self,
            })

            if p[i].seperator then
                table.insert(self.submenu, HorizontalSpan:new{ width = sep_size })
            end
        end
    elseif page == "none" then
        self.menu = "none"
        self.submenu:clear()
    end

    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
end

function Editor:newImage()
    UIManager:show(ConfirmBox:new{
        text = "Are you sure you would like to clear your drawing?",
        ok_text = "Clear",
        cancel_text = "Keep",
        ok_callback = function() self:updateMenu("none") self.canvas:newImage() end,
    })
end

function Editor:saveImage()
    local chooser = PathChooser:new{
        title = "Which folder?",
        path = self.last_path,
        select_directory = true,
        select_file = false,
        onConfirm = function(dir_path)
            local file_input
            file_input = InputDialog:new{
                title =  "Enter name",
                input = "",
                buttons = {{
                    {
                        text = "Cancel",
                        callback = function() UIManager:close(file_input) end,
                    },
                    {
                        text = "Save",
                        callback = function()
                            local file_path = file_input:getInputText()
                            local fp = (dir_path == "/" and "/" or dir_path .. "/") .. file_path .. ".png"
                            UIManager:close(file_input)
                            self.last_path = fp:match("(.*)/")
                            if self.last_path == "" then self.last_path = "/" end
                            self.canvas:saveImage(fp)
                            self:updateMenu("none")
                        end,
                    },
                }},
            }

            UIManager:show(file_input)
            file_input:onShowKeyboard()
        end,
    }

    UIManager:show(chooser)
end

function Editor:loadImage()
    local chooser = PathChooser:new{
        title = "Which image?",
        path = self.last_path,
        select_file = true,
        select_directory = false,
        detailed_file_info = true,
        file_filter = function (path)
            local itype = string.lower(string.match(path, ".+%.([^.]+)") or "")

            return itype == "svg" or itype == "png" or itype == "jpg" or itype == "jpeg" or itype == "gif" or itype == "tiff" or itype == "tif"
        end,
        onConfirm = function (file_path)
            self.canvas:loadImage(file_path)
            self:updateMenu("none")
        end,
    }

    UIManager:show(chooser)
end

function Editor:resizeCanvas()
    local width, height, nw, nh

    width = InputDialog:new{
        title =  "Enter image width",
        input = tostring(self.canvas:getCanvasSize().w),
        buttons = {{
            {
                text = "Cancel",
                callback = function() UIManager:close(width) end,
            },
            {
                text = "Next",
                callback = function()
                    nw = tonumber(width:getInputText())

                    if nw then
                        UIManager:close(width)
                        UIManager:show(height)
                        height:onShowKeyboard()
                    end
                end,
            },
        }},
    }

    height = InputDialog:new{
        title =  "Enter image height",
        input = tostring(self.canvas:getCanvasSize().h),
        buttons = {{
            {
                text = "Cancel",
                callback = function() UIManager:close(height) end,
            },
            {
                text = "Resize",
                callback = function()
                    nh = tonumber(height:getInputText())

                    if nh then
                        UIManager:close(height)
                        self.canvas:resizeCanvas(nw, nh)
                        self:updateMenu("none")
                    end
                end,
            },
        }},
    }

    UIManager:show(width)
    width:onShowKeyboard()
end

-- Change the big grid size
function Editor:resizeGrid()
    local width, height, nw, nh

    width = InputDialog:new{
        title =  "Enter grid width",
        input = tostring(self.canvas:getGridSize().w),
        buttons = {{
            {
                text = "Cancel",
                callback = function() UIManager:close(width) end,
            },
            {
                text = "Next",
                callback = function()
                    nw = tonumber(width:getInputText())

                    if nw then
                        UIManager:close(width)
                        UIManager:show(height)
                        height:onShowKeyboard()
                    end
                end,
            },
        }},
    }

    height = InputDialog:new{
        title =  "Enter grid height",
        input = tostring(self.canvas:getGridSize().h),
        buttons = {{
            {
                text = "Cancel",
                callback = function() UIManager:close(height) end,
            },
            {
                text = "Resize",
                callback = function()
                    nh = tonumber(height:getInputText())

                    if nh then
                        UIManager:close(height)
                        self.canvas:resizeGrid(nw, nh)
                        self:updateMenu("none")
                    end
                end,
            },
        }},
    }

    UIManager:show(width)
    width:onShowKeyboard()
end

function Editor:refresh()
    setNight(false)
    UIManager:setDirty(self, function()
        return "flashui", self.dimen
    end)
end

function Editor:quit()
    UIManager:show(ConfirmBox:new{
        text = "Are you sure you would like to quit?",
        ok_text = "Quit",
        cancel_text = "Stay",
        ok_callback = function() self:onClose() end,
    })
end

function Editor:onClose()
    self.canvas:free() -- ayyyyy being responsible with memoryyyyyy
    UIManager:close(self)

    setNight(night)

    self:refresh()

    return true
end

return Editor