local Blitbuffer = require("ffi/blitbuffer")
local HorizontalGroup = require("ui/widget/horizontalgroup")

local SubMenu = HorizontalGroup:new{
    dark = nil,
    show_parent = nil,
}

-- Paint a single rounded corner (partly stolen from Blitbuffer paintRoundedCorner code)
function paintCorner(image, off_x, off_y, w, h, bw, r, c, i)
    if 2 * r > h or 2 * r > w or r == 0 then return end

    r = math.min(r, h, w)
    bw = math.min(bw, r)

    local x = 0
    local y = r
    local delta = 5/4 - r

    local r2 = r - bw
    local x2 = 0
    local y2 = r2
    local delta2 = 5/4 - r

    while x < y do
        x = x + 1

        if delta > 0 then
            y = y - 1
            delta = delta + 2 * x - 2 * y + 2
        else
            delta = delta + 2 * x + 1
        end

        if x2 > y2 then
            y2 = y2 + 1
            x2 = x2 + 1
        else
            x2 = x2 + 1
            if delta2 > 0 then
                y2 = y2 - 1
                delta2 = delta2 + 2 * x2 - 2 * y2 + 2
            else
                delta2 = delta2 + 2 * x2 + 1
            end
        end

        for tmp_y = y, y2 + 1, -1 do
            if i == 4 then
                image:setPixelClamped((w - r) + off_x + x - 1, (h - r) + off_y + tmp_y - 1, c)
                image:setPixelClamped((w - r) + off_x + tmp_y - 1, (h - r) + off_y + x - 1, c)
            end

            if i == 2 then
                image:setPixelClamped((w - r) + off_x + tmp_y - 1, r + off_y - x, c)
                image:setPixelClamped((w - r) + off_x + x - 1, r + off_y - tmp_y, c)
            end

            if i == 1 then
                image:setPixelClamped(r + off_x - x, r + off_y - tmp_y, c)
                image:setPixelClamped(r + off_x - tmp_y, r + off_y - x, c)
            end

            if i == 3 then
                image:setPixelClamped(r + off_x - tmp_y, (h - r) + off_y + x - 1, c)
                image:setPixelClamped(r + off_x - x, (h - r) + off_y + tmp_y - 1, c)
            end
        end
    end
end

function SubMenu:paintTo(bb, x, y)
    HorizontalGroup.paintTo(self, bb, x, y)

    if self:getSize().w ~= 0 then
        local b = self.dark and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE -- background
        local o = self.dark and Blitbuffer.Color8(0x55) or Blitbuffer.Color8(0xBB) -- outline

        bb:paintRect(x, y - 16, 4, self:getSize().h + 32, b) -- cover up sidebar outline

        bb:paintRect(x + 16, y - 4, self:getSize().w - 28, 4, o) -- top border
        bb:paintRect(x + 16, y + self:getSize().h, self:getSize().w - 28, 4, o) -- bottom border

        -- top inside corner
        paintCorner(bb, x, y - 32 + 6, 32, 32, 4, 16, b, 3)
        paintCorner(bb, x, y - 32 + 3, 32, 32, 4, 16, b, 3)
        paintCorner(bb, x, y - 32, 32, 32, 4, 16, o, 3)

        -- bottom insie corner
        paintCorner(bb, x, y + self:getSize().h - 6, 32, 32, 4, 16, b, 1)
        paintCorner(bb, x, y + self:getSize().h - 3, 32, 32, 4, 16, b, 1)
        paintCorner(bb, x, y + self:getSize().h, 32, 32, 4, 16, o, 1)

        -- right outside corners
        paintCorner(bb, x, y - 4, self:getSize().w + 4, self:getSize().h + 8, 4, 16, o, 2)
        bb:paintRect(x + self:getSize().w, y + 12, 4, self:getSize().h - 24, o)
        paintCorner(bb, x, y - 4, self:getSize().w + 4, self:getSize().h + 8, 4, 16, o, 4)
    end
end

return SubMenu