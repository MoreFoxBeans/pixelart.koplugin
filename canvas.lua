local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderImage = require("ui/renderimage")
local UIManager = require("ui/uimanager")

-- Get the value at v% between a and b
local function lerp(a, b, v) return (b - a) * v + a end

-- Calculate the distance between two points
local function dist(x1, y1, x2, y2)
    return math.sqrt(math.pow(math.abs(x2 - x1), 2) + math.pow(math.abs(y2 - y1), 2))
end

-- Draw a line using linear interpolation [SLOW BUT EASY]
local function paintLine(bb, x1, y1, x2, y2, c, s)
    for i = 0, 1, 1 / dist(x1, y1, x2, y2) do
        local lx = math.floor(lerp(x1, x2, i) + 0.5)
        local ly = math.floor(lerp(y1, y2, i) + 0.5)

        if lx >= 0 and ly >= 0 and lx < bb:getWidth() and ly < bb:getHeight() then
            if s == 1 then
                bb:setPixel(lx, ly, Blitbuffer.Color8(c))
            else
                bb:paintCircle(lx, ly, math.floor(s / 2), Blitbuffer.Color8(c))
            end
        end
    end
end

-- Paint a rectangle in any quadrant
local function paintRect(bb, x1, y1, x2, y2, c, s)
    if s then
        if x2 >= x1 and y2 >= y1 then
            bb:paintBorder(x1, y1, x2 - x1 + 1, y2 - y1 + 1, s, Blitbuffer.Color8(c))
        elseif x2 >= x1 and y2 < y1 then
            bb:paintBorder(x1, y2, x2 - x1 + 1, y1 - y2 + 1, s, Blitbuffer.Color8(c))
        elseif x2 < x1 and y2 >= y1 then
            bb:paintBorder(x2, y1, x1 - x2 + 1, y2 - y1 + 1, s, Blitbuffer.Color8(c))
        elseif x2 < x1 and y2 < y1 then
            bb:paintBorder(x2, y2, x1 - x2 + 1, y1 - y2 + 1, s, Blitbuffer.Color8(c))
        end
    else
        if x2 >= x1 and y2 >= y1 then
            bb:paintRect(x1, y1, x2 - x1 + 1, y2 - y1 + 1, Blitbuffer.Color8(c))
        elseif x2 >= x1 and y2 < y1 then
            bb:paintRect(x1, y2, x2 - x1 + 1, y1 - y2 + 1, Blitbuffer.Color8(c))
        elseif x2 < x1 and y2 >= y1 then
            bb:paintRect(x2, y1, x1 - x2 + 1, y2 - y1 + 1, Blitbuffer.Color8(c))
        elseif x2 < x1 and y2 < y1 then
            bb:paintRect(x2, y2, x1 - x2 + 1, y1 - y2 + 1, Blitbuffer.Color8(c))
        end
    end
end

-- Flood/bucket fill at a point
local function floodFill(bb, x, y, c, diag)
    local cur = bb:getPixel(x, y).a
    if cur == c then return end
    fill(bb, x, y, c, cur, diag)
end

function fill(bb, x, y, c, cur, diag)
    if x < 0 or y < 0 or x > bb:getWidth() - 1 or y > bb:getHeight() - 1 or bb:getPixel(x, y).a ~= cur then return end

    bb:setPixel(x, y, Blitbuffer.Color8(c))
    fill(bb, x, y - 1, c, cur, diag)
    fill(bb, x, y + 1, c, cur, diag)
    fill(bb, x - 1, y, c, cur, diag)
    fill(bb, x + 1, y, c, cur, diag)

    if diag then
        fill(bb, x - 1, y - 1, c, cur, diag)
        fill(bb, x + 1, y + 1, c, cur, diag)
        fill(bb, x - 1, y + 1, c, cur, diag)
        fill(bb, x + 1, y - 1, c, cur, diag)
    end
end

local Canvas = InputContainer:new{
    width = nil,
    height = nil,
    dark = nil,
    show_parent = nil,

    image_w = 64,
    image_h = 64,
    zoom = 40,
    grid = true,
    grid_w = 8,
    grid_h = 8,
    pattern = false,
    view_x = 0,
    view_y = 0,

    _touch_ix = nil, -- Initial touch point
    _touch_iy = nil,
    _touch_px = nil, -- Previous touch point
    _touch_py = nil,
    _touch_x = nil, -- Current touch point
    _touch_y = nil,

    _view_ix = nil, -- Initial view pos for pan tool
    _view_iy = nil,

    _image = nil,
    _preview = nil,
    _disp_preview = false,
    _bb = nil,
}

function Canvas:init()
    self.dimen = Geom:new{
        x = 0, y = 0,
        w = self.width or self.show_parent.dimen.w,
        h = self.height or self.show_parent.dimen.h,
    }

    self.drag_callback = function () self:doDrag() end

    self.ges_events = {
        TouchCanvas = {
            GestureRange:new{
                ges = "touch",
                range = function () return self.dimen end,
            },
        },
    }

    self:createCanvas(self.image_w, self.image_h)
    self:center()
end

-- Create a new canvas + free old + update!
function Canvas:createCanvas(w, h)
    self.image_w = w
    self.image_h = h

    if self._image then self._image:free() end
    self._image = Blitbuffer.new(self.image_w, self.image_h, Blitbuffer.TYPE_BB8)
    self._image:fill(Blitbuffer.COLOR_WHITE)

    if self._preview then self._preview:free() end
    self._preview = Blitbuffer.new(self.image_w, self.image_h, Blitbuffer.TYPE_BB8)

    self:_update()
end

-- Resize the canvas anchored to (0, 0)
function Canvas:resizeCanvas(nw, nh)
    local ow, oh = self.image_w, self.image_h
    local old = Blitbuffer.new(ow, oh, Blitbuffer.TYPE_BB8)
    old:blitFrom(self._image, 0, 0, 0, 0, ow, oh)
    self:createCanvas(nw, nh)
    self._image:blitFrom(old, 0, 0, 0, 0, ow, oh)
    old:free()
    old = nil

    self:_update("flashui")
end

-- Probably don't need this but it cools cool ig
function Canvas:getCanvasSize() return { w = self.image_w, h = self.image_h } end

-- Auto zoom/pos the canvas to fit screen
function Canvas:center()
    if self.dimen.w / self.dimen.h <= self.image_w / self.image_h then
        self.zoom = math.floor(self.dimen.w / self.image_w)
    else
        self.zoom = math.floor(self.dimen.h / self.image_h)
    end

    self.view_x = math.floor((self.dimen.w - self.image_w * self.zoom) / 2)
    self.view_y = math.floor((self.dimen.h - self.image_h * self.zoom) / 2)

    self:_update("flashui")
end

function Canvas:setZoom(z) self.zoom = z self:_update() end
function Canvas:getZoom() return self.zoom end
function Canvas:zoomIn() self:setZoom(math.min(math.ceil(self.zoom * 1.5), 200)) end
function Canvas:zoomOut() self:setZoom(math.max(math.floor(self.zoom / 1.5), 1)) end

function Canvas:setGrid(g) self.grid = g self:_update() end
function Canvas:getGrid() return self.grid end
function Canvas:resizeGrid(nw, nh) self.grid_w, self.grid_h = nw, nh self:_update() end
function Canvas:getGridSize() return { w = self.grid_w, h = self.grid_h } end

-- Refresh the canvas using canvas coords, not screen coords
function Canvas:_refresh(x, y, w, h, type)
    if x and y and w and h then
        UIManager:setDirty(self.show_parent, function ()
            return (type or "ui"), Geom:new{
                x = x * self.zoom + self.dimen.x + self.view_x,
                y = y * self.zoom + self.dimen.y + self.view_y,
                w = w * self.zoom,
                h = h * self.zoom,
            }
        end)
    else
        UIManager:setDirty(self.show_parent, function ()
            return (x or type or "ui"), self.dimen
        end)
    end
end

-- If canvas changed, redraw and refresh
function Canvas:_update(x, y, w, h, type)
    if self._bb then
        self._bb:free()
        self._bb = nil

        self:_refresh(x, y, w, h, type)
    end
end

function Canvas:paintTo(bb, x, y)
    self.dimen = Geom:new{
        x = x, y = y,
        w = self.dimen.w,
        h = self.dimen.h
    }

    if not self._bb then
        self._bb = Blitbuffer.new(self.dimen.w, self.dimen.h, bb:getType())
        self._bb:fill(Blitbuffer.Color8(self.dark and 0x33 or 0x99))
        self._bb:paintRect(self.view_x, self.view_y, self.image_w * self.zoom, self.image_h * self.zoom, Blitbuffer.Color8(0x77))

        -- Get draw pixel size (make smaller pixels instead of drawing lines for grid for faster painting
        local z = self.zoom - ((self.grid and self.zoom > 4) and 1 or 0)

        -- If preview image (line, rect, circle), then use that one
        local img = self._disp_preview and self._preview or self._image

        for iy = 0, self.image_h - 1 do
            for ix = 0, self.image_w - 1 do
                local vx = ix * self.zoom + self.view_x
                local vy = iy * self.zoom + self.view_y

                -- Bigger grid lines every few pixels
                local zw = self.grid_w == 1 and z or (z == self.zoom and self.zoom or (z - (ix % self.grid_w == self.grid_w - 1 and 1 or 0)))
                local zh = self.grid_h == 1 and z or (z == self.zoom and self.zoom or (z - (iy % self.grid_h == self.grid_h - 1 and 1 or 0)))

                if self.pattern then -- Hidden feature?
                    for pix = -1, 1 do
                        for piy = -1, 1 do
                            self._bb:paintRect(vx + (self.image_w * self.zoom) * pix, vy + (self.image_h * self.zoom) * piy, (pix == 0 and piy == 0) and zw or self.zoom, (pix == 0 and piy == 0) and zh or self.zoom, img:getPixel(ix, iy))
                        end
                    end
                else
                    self._bb:paintRect(vx, vy, zw, zh, img:getPixel(ix, iy))
                end
            end
        end

        -- Looks cool, mostly for if self.pattern
        self._bb:paintBorder(self.view_x - 4, self.view_y - 4, self.image_w * self.zoom + 8, self.image_h * self.zoom + 8, 4, Blitbuffer.Color8(0x66), 8)
    end

    bb:blitFrom(self._bb, x, y, 0, 0, self.dimen.w, self.dimen.h)
end

-- Convert screen coords to pixel coords
function Canvas:tx(v) return math.floor((v - self.dimen.x - self.view_x) / self.zoom) end
function Canvas:ty(v) return math.floor((v - self.dimen.y - self.view_y) / self.zoom) end

-- When canvas first touched
function Canvas:onTouchCanvas(arg, ges)
    if not(ges.pos.x >= 108 and ges.pos.y >= self.show_parent.submenu_y.width and ges.pos.x < 108 + self.show_parent.submenu:getSize().w and ges.pos.y < self.show_parent.submenu_y.width + 108) and ges.pos.x >= self.dimen.x + self.view_x and ges.pos.y >= self.dimen.y + self.view_y and ges.pos.x < self.dimen.x + self.view_x + self.image_w * self.zoom and ges.pos.y < self.dimen.y + self.view_y + self.image_h * self.zoom then -- Check if touching canvas and not touching submenu
        local tool = self.show_parent.tool -- alias
        local x, y = self:tx(ges.pos.x), self:ty(ges.pos.y)

        if tool == "picker" then
            self.show_parent.color = self._image:getPixel(x, y).a

            UIManager:setDirty(self.show_parent, function ()
                return "ui", self.show_parent.dimen
            end)
        elseif tool == "fill" or tool == "filldiag" or tool == "fillall" then
            if tool == "fill" then
                floodFill(self._image, x, y, self.show_parent.color, false)
            elseif tool == "filldiag" then
                floodFill(self._image, x, y, self.show_parent.color, true)
            elseif tool == "fillall" then
                local fillcur = self._image:getPixel(x, y).a

                for hyi = 0, self.image_h - 1 do
                    for wxi = 0, self.image_w - 1 do
                        if self._image:getPixel(wxi, hyi).a == fillcur then
                            self._image:setPixel(wxi, hyi, Blitbuffer.Color8(self.show_parent.color))
                        end
                    end
                end
            end

            self:_update()

            UIManager:setDirty(self.show_parent, function ()
                return "ui", self.show_parent.dimen
            end)
        else
            if tool == "line" or tool == "circle" or tool == "rect" then
                self._touch_ix = x -- Store initial coords
                self._touch_iy = y

                self._disp_preview = true
            end

            if tool == "pan" then
                self._touch_ix = ges.pos.x -- Store initial screen coords
                self._touch_iy = ges.pos.y

                self._view_ix = self.view_x -- Store initial view coords
                self._view_iy = self.view_y
            end

            self._touch_x = nil
            self._touch_y = nil

            self:doDrag()
        end

        return true
    end
end

function Canvas:dragLine()
    local ix, iy = self._touch_ix, self._touch_iy
    local px, py = self._touch_px, self._touch_py
    local x, y = self._touch_x, self._touch_y

    local nx, xx, ny, xy = math.min(ix, px, x), math.max(ix, px, x), math.min(iy, py, y), math.max(iy, py, y) -- Get full boundaries to refresh

    self._preview:blitFrom(self._image, 0, 0, 0, 0, self.image_w, self.image_h)
    paintLine(self._preview, ix, iy, x, y, self.show_parent.color, self.show_parent.size)

    local s = self.show_parent.size
    self:_update(nx - math.floor(s / 2), ny - math.floor(s / 2), xx - nx + s + 1, xy - ny + s + 1)
end

function Canvas:releaseLine()
    local ix, iy = self._touch_ix, self._touch_iy
    local px, py = self._touch_px, self._touch_py
    local x, y = self._touch_x, self._touch_y

    local nx, xx, ny, xy = math.min(ix, px, x), math.max(ix, px, x), math.min(iy, py, y), math.max(iy, py, y) -- Get full boundaries to refresh

    paintLine(self._image, ix, iy, x, y, self.show_parent.color, self.show_parent.size)

    self._disp_preview = false

    local s = self.show_parent.size
    self:_update(nx - math.floor(s / 2), ny - math.floor(s / 2), xx - nx + s + 1, xy - ny + s + 1)
end

function Canvas:dragRect()
    local ix, iy = self._touch_ix, self._touch_iy
    local px, py = self._touch_px, self._touch_py
    local x, y = self._touch_x, self._touch_y

    local nx, xx, ny, xy = math.min(ix, px, x), math.max(ix, px, x), math.min(iy, py, y), math.max(iy, py, y) -- Get full boundaries to refresh

    self._preview:blitFrom(self._image, 0, 0, 0, 0, self.image_w, self.image_h)

    paintRect(self._preview, ix, iy, x, y, self.show_parent.color, not self.show_parent.fill and self.show_parent.size or nil)

    self:_update(nx, ny, xx - nx + 1, xy - ny + 1)
end

function Canvas:releaseRect()
    local ix, iy = self._touch_ix, self._touch_iy
    local px, py = self._touch_px, self._touch_py
    local x, y = self._touch_x, self._touch_y

    local nx, xx, ny, xy = math.min(ix, px, x), math.max(ix, px, x), math.min(iy, py, y), math.max(iy, py, y) -- Get full boundaries to refresh

    paintRect(self._image, ix, iy, x, y, self.show_parent.color, not self.show_parent.fill and self.show_parent.size or nil)

    self._disp_preview = false

    self:_update(nx, ny, xx - nx + 1, xy - ny + 1)
end

function Canvas:dragCircle()
    local ix, iy = self._touch_ix, self._touch_iy
    local px, py = self._touch_px, self._touch_py
    local x, y = self._touch_x, self._touch_y

    local s = math.floor(dist(ix, iy, x, y))
    local ms = math.max(math.floor(dist(ix, iy, px, py)), s)

    self._preview:blitFrom(self._image, 0, 0, 0, 0, self.image_w, self.image_h)

    self._preview:paintCircle(ix, iy, s, Blitbuffer.Color8(self.show_parent.color), not self.show_parent.fill and self.show_parent.size or nil)

    self:_update(ix - ms, iy - ms, ms * 2 + 1, ms * 2 + 1)
end

function Canvas:releaseCircle()
    local ix, iy = self._touch_ix, self._touch_iy
    local px, py = self._touch_px, self._touch_py
    local x, y = self._touch_x, self._touch_y

    local s = math.floor(dist(ix, iy, x, y))
    local ms = math.max(math.floor(dist(ix, iy, px, py)), s)

    self._image:paintCircle(ix, iy, s, Blitbuffer.Color8(self.show_parent.color), not self.show_parent.fill and self.show_parent.size or nil)

    self._disp_preview = false

    self:_update(ix - ms, iy - ms, ms * 2 + 1, ms * 2 + 1)
end

function Canvas:dragPencil()
    local px, py = self._touch_px, self._touch_py
    local x, y = self._touch_x, self._touch_y

    for i = 0, 1, 1 / dist(px, py, x, y) do -- Interpolate (pixels between touch coords for smooth lines)
        local lx = math.floor(lerp(px, x, i))
        local ly = math.floor(lerp(py, y, i))

        if self.show_parent.size == 1 then
            if lx >= 0 and ly >= 0 and lx < self.image_w and ly < self.image_h then
                self._image:setPixel(lx, ly, self.show_parent.tool == "pencil" and Blitbuffer.Color8(self.show_parent.color) or Blitbuffer.COLOR_WHITE)
            end
        else
            self._image:paintCircle(lx, ly, math.floor(self.show_parent.size / 2), self.show_parent.tool == "pencil" and Blitbuffer.Color8(self.show_parent.color) or Blitbuffer.COLOR_WHITE)
        end
    end

    local nx, xx, ny, xy = math.min(px, x), math.max(px, x), math.min(py, y), math.max(py, y) -- Get full boundaries to refresh
    local s = self.show_parent.size
    self:_update(nx - math.floor(s / 2), ny - math.floor(s / 2), xx - nx + s + 1, xy - ny + s + 1)
end

function Canvas:dragPan()
    local ix, iy = self._touch_ix, self._touch_iy
    local x, y = Device.input:getCurrentMtSlotData("x"), Device.input:getCurrentMtSlotData("y")

    self.view_x = self._view_ix + x - ix
    self.view_y = self._view_iy + y - iy

    self:_update()
end

function Canvas:releasePan()
    self:_refresh("flashui")
end

function Canvas:doDrag()
    self._touch_px = self._touch_x
    self._touch_py = self._touch_y
    self._touch_x = self:tx(Device.input:getCurrentMtSlotData("x"))
    self._touch_y = self:ty(Device.input:getCurrentMtSlotData("y"))
    self._touch_px = self._touch_px or self._touch_x
    self._touch_py = self._touch_py or self._touch_y

    local tool = self.show_parent.tool

    if tool == "pencil" or tool == "eraser" then self:dragPencil()
    elseif tool == "line" then self:dragLine()
    elseif tool == "rect" then self:dragRect()
    elseif tool == "circle" then self:dragCircle()
    elseif tool == "pan" then self:dragPan()
    end

    if Device.input:getCurrentMtSlotData("id") ~= -1 then
        UIManager:scheduleIn(tool == "pan" and 0.3 or 0.1, self.drag_callback)
    else
        if tool == "line" then self:releaseLine()
        elseif tool == "rect" then self:releaseRect()
        elseif tool == "circle" then self:releaseCircle()
        elseif tool == "pan" then self:releasePan()
        end
    end
end

-- Clear the canvas + center
function Canvas:newImage()
    self._image:fill(Blitbuffer.COLOR_WHITE)
    self:center()
    self:_update()
end

-- Export canvas to PNG
function Canvas:saveImage(file)
    local bgr = Device:hasBGRFrameBuffer() and true or false
    self._image:writePNG(file, bgr)
end

-- Load canvas from image
function Canvas:loadImage(file)
    local load = RenderImage:renderImageFile(file, false, self.image_w, self.image_h)
    self._image:blitFrom(load, 0, 0)
    load:free()
    self:center()
    self:_update()
end

function Canvas:free()
    if self._image then self._image:free() end
    if self._preview then self._preview:free() end
    if self._bb then self._bb:free() end
    self._image = nil
    self._preview = nil
    self._bb = nil
end

return Canvas