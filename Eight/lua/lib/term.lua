local screen = require("screen");
local font = require("fonts.tewi")
local event = require("event")
local timer = require("timer")
local expect = require("expect") 

local grid = {}
local term = {}

local fontWidth = font._width or 0
local fontHeight = font._height or 0
local width, height, scale = 0, 0, 1

local fgColor = { 0xff, 0xff, 0xff }
local bgColor = { 0, 0, 0 }

local posX = 0
local posY = 0

local blinkDelay = 500
local isBlinking = false
local timerBlinkId

local spaceCode = string.byte(" ")

local initiated = false

if not utf8.sub then
    function utf8.sub(s, i, j)
        return string.sub(s, utf8.offset(s, i), j and (utf8.offset(s, j + 1) - 1) or #s)
    end
end

local function isValidUtf8(str)
  local i, len = 1, #str
  while i <= len do
    if     i == string.find(str, "[%z\1-\127]", i) then i = i + 1
    elseif i == string.find(str, "[\194-\223][\128-\191]", i) then i = i + 2
    elseif i == string.find(str,        "\224[\160-\191][\128-\191]", i)
        or i == string.find(str, "[\225-\236][\128-\191][\128-\191]", i)
        or i == string.find(str,        "\237[\128-\159][\128-\191]", i)
        or i == string.find(str, "[\238-\239][\128-\191][\128-\191]", i) then i = i + 3
    elseif i == string.find(str,        "\240[\144-\191][\128-\191][\128-\191]", i)
        or i == string.find(str, "[\241-\243][\128-\191][\128-\191][\128-\191]", i)
        or i == string.find(str,        "\244[\128-\143][\128-\191][\128-\191]", i) then i = i + 4
    else
      return false, i
    end
  end

  return true
end

local function setChar(x, y, char, fg, bg)
    if x >= 0 and y >= 0 and x < width and y < height then
        grid[posY] = grid[posY] or {}
        grid[posY][posX] = {
            char, fg, bg
        }
    end
end

local function getChar(x, y)
    grid[posY] = grid[posY] or {}
    return grid[posY][posX]
end

local function drawChar(c, fg, bg, noset)
    local char = font[c] or font[string.byte("?")] or { {} }
    fg = fg or fgColor
    bg = bg or bgColor
    underline = underline or false

    local deltaX, deltaY = posX * fontWidth, posY * fontHeight

    local charWidth = #char[1]
    deltaX = deltaX + math.ceil((fontWidth / 2) - (charWidth / 2))

    screen.drawRectangle(
            posX * fontWidth,
            posY * fontHeight,
            fontWidth,
            fontHeight,
            table.unpack(bg)
    )

    for y = 1, #char do
        for x = 1, #char[y] do
            if char[y][x] == 1 then
                screen.setPixel(deltaX + x, deltaY + y - 1, table.unpack(fg))
            end
        end
    end

    if not noset then
        setChar(posX, posY, c, fg, bg)
    end
    posX = posX + 1

end

local function redraw()
    local cx, cy = term.getPos()
    for y, row in pairs(grid) do
        for x, char in pairs(row) do
            term.setPos(x, y)
            if char[1] then
                drawChar(char[1], char[2] or fgColor, char[3] or bgColor, true)
            end
        end
    end

    term.setPos(cx, cy)
end

local function redrawChar(x, y)
    local cx, cy = term.getPos()
    
    local row = grid[y]
    if row then
        local char = row[x]
        if char then
            posX, posY = x, y
            drawChar(char[1] or spaceCode, char[2] or fgColor, char[3] or bgColor, true)
        end
    end
    
    posX, posY = cx, cy
end

local function clear(resetGrid)
    screen.clear()
    local w, h = screen.getSize()
    screen.drawRectangle(0, 0, w, h, table.unpack(bgColor))
    if resetGrid then
        grid = {}
        for y = 1, h do
            grid[y] = {}
            for x = 1, w do
                grid[y][x] = {}
            end
        end
    end
end

function term.setSize(w, h, s)
    expect(1, w, "number")
    expect(2, h, "number")
    expect(1, s, "number", "nil")

    local ow, oh, os = screen.getSize()

    w = math.floor(w)
    h = math.floor(h)

    screen.setSize(w * fontWidth, h * fontHeight, s or os)

    width = w
    height = h
    scale = s or os

    clear(true)
end

function term.getSize()
    return width, height, scale
end

function term.setPos(x, y)
    expect(1, x, "number")
    expect(2, y, "number")
    
    local oldX, oldY = posX, posY
    posX = x
    posY = y
    
    redrawChar(oldX, oldY)
end

function term.getPos()
    return posX, posY
end

function term.setForeground(r, g, b)
    expect(1, r, "number", "table")
    expect(1, g, "number", "nil")
    expect(1, b, "number", "nil")
    
    if type(r) == "table" then
        for i = 1, 3 do
            if type(r[i]) ~= "number" then
                error(("bad argument #1[%d] (expected %s, got %s)"):format(i, "number", type(r[i])), 3)
            end
        end
        fgColor = {
             r[1], r[2], r[3]
        }
        return    
    end
    fgColor = { r, g, b }
end

function term.setBackground(r, g, b)
    expect(1, r, "number", "table")
    expect(1, g, "number", "nil")
    expect(1, b, "number", "nil")
    
    if type(r) == "table" then
        for i = 1, 3 do
            if type(r[i]) ~= "number" then
                error(("bad argument #1[%d] (expected %s, got %s)"):format(i, "number", type(r[i])), 3)
            end
        end
        bgColor = {
            r[1], r[2], r[3]
        }
        return    
    end
    bgColor = { r, g, b }
end

function term.getForeground()
    return table.unpack(fgColor)
end

function term.getBackground()
    return table.unpack(bgColor)
end

function term.write(...)
    local chunks = {}
    for k, v in ipairs({...}) do
        chunks[#chunks + 1] = tostring(v)
    end

    local text = table.concat(chunks, " ")

    local function iterate(char)
        if char == 10 then
            posY = posY + 1
            if posY >= height then
                term.scroll(-1)
                posY = height - 1
            end
            posX = 0
        elseif char == 9 then
            posX = posX + 2
        elseif char ~= 13 then
            drawChar(char)
        end

        if posX >= width then
            posX = 0
            posY = posY + 1
        end
    end

    if isValidUtf8(text) then
        for _, char in utf8.codes(text) do
            iterate(char)
        end
    else
        for char in string.gmatch(text, "(.)") do
            iterate(char)
        end
    end
end


function term.clear()
    clear(true)
end

function term.clearLine()
    local w, h = screen.getSize()
    screen.drawRectangle(0, posY * fontHeight, w, fontWidth, table.unpack(bgColor))
end

function term.scroll(n)
    expect(1, n, "number")
    local copy = {}
    for k, v in pairs(grid) do
        copy[k + 1] = v
    end

    if n < 0 then
        for i = 1, math.abs(n) do
            table.remove(copy, 1)
            table.insert(copy, #copy, {})
        end
    end

    if n > 0 then
        for i = 1, math.abs(n) do
            table.insert(copy, 1, {})
            table.remove(copy, #copy)
        end
    end

    grid = {}
    for k, v in pairs(copy) do
        grid[k - 1] = v
    end

    clear(false)
    redraw()
end

function term.setBlinking(blink)
    expect(1, blink, "boolean")
    isBlinking = blink
end

function term.getBlinking()
    return isBlinking
end

function term.read(_sReplaceChar, _tHistory, _fnComplete, _sDefault)
    expect(1, _sReplaceChar, "string", "nil")
    expect(2, _tHistory, "table", "nil")
    expect(3, _fnComplete, "function", "nil")
    expect(4, _sDefault, "string", "nil")

    term.setBlinking(true)

    local sLine
    if type(_sDefault) == "string" then
        sLine = _sDefault
    else
        sLine = ""
    end
    local nHistoryPos
    local nPos, nScroll = utf8.len(sLine), 0
    if _sReplaceChar then
        _sReplaceChar = string.sub(_sReplaceChar, 1, 1)
    end

    local tCompletions
    local nCompletion
    local function recomplete()
        if _fnComplete and nPos == utf8.len(sLine) then
            tCompletions = _fnComplete(sLine)
            if tCompletions and #tCompletions > 0 then
                nCompletion = 1
            else
                nCompletion = nil
            end
        else
            tCompletions = nil
            nCompletion = nil
        end
    end

    local function uncomplete()
        tCompletions = nil
        nCompletion = nil
    end

    local w = term.getSize()
    local sx = term.getPos()

    local function redraw(_bClear)
        local cursor_pos = nPos - nScroll
        if sx + cursor_pos > w then
            -- We've moved beyond the RHS, ensure we're on the edge.
            nScroll = sx + nPos - w
        elseif cursor_pos < 0 then
            -- We've moved beyond the LHS, ensure we're on the edge.
            nScroll = nPos
        end

        local _, cy = term.getPos()
        term.setPos(sx, cy)
        local sReplace = _bClear and " " or _sReplaceChar
        if sReplace then
            term.write(string.rep(utf8.sub(sReplace, 1, 1), math.max(utf8.len(sLine) - nScroll, 0)))
        else
            term.write(utf8.sub(sLine, nScroll + 1))
        end

        if nCompletion then
            local sCompletion = tCompletions[nCompletion]
            local oldText, oldBg
            if not _bClear then
                oldText = term.getForeground()
                oldBg = term.getBackground()
                term.setForeground(colors.white)
                term.setBackground(colors.gray)
            end
            if sReplace then
                term.write(string.rep(sReplace, #sCompletion))
            else
                term.write(sCompletion)
            end
            if not _bClear then
                term.setForeground(oldText)
                term.getBackground(oldBg)
            end
        end

        term.setPos(sx + nPos - nScroll, cy)
    end

    local function clear()
        redraw(true)
    end

    recomplete()
    redraw()

    local function acceptCompletion()
        if nCompletion then
            -- Clear
            clear()

            -- Find the common prefix of all the other suggestions which start with the same letter as the current one
            local sCompletion = tCompletions[nCompletion]
            sLine = sLine .. sCompletion
            nPos = utf8.len(sLine)

            -- Redraw
            recomplete()
            redraw()
        end
    end
    while true do
        local sEvent, param, param1, param2 = event.pull()
        if sEvent == "char" then
            -- Typed key
            clear()
            sLine = utf8.sub(sLine, 1, nPos) .. param .. utf8.sub(sLine, nPos + 1)
            nPos = nPos + 1
            recomplete()
            redraw()

        elseif sEvent == "paste" then
            -- Pasted text
            clear()
            sLine = string.sub(sLine, 1, nPos) .. param .. string.sub(sLine, nPos + 1)
            nPos = nPos + #param
            recomplete()
            redraw()

        elseif sEvent == "key_down" then
            if param == "return" then
                -- Enter
                if nCompletion then
                    clear()
                    uncomplete()
                    redraw()
                end
                break

            elseif param == "left" then
                -- Left
                if nPos > 0 then
                    clear()
                    nPos = nPos - 1
                    recomplete()
                    redraw()
                end

            elseif param == "right" then
                -- Right
                if nPos < utf8.len(sLine) then
                    -- Move right
                    clear()
                    nPos = nPos + 1
                    recomplete()
                    redraw()
                else
                    -- Accept autocomplete
                    acceptCompletion()
                end

            elseif param == "up" or param == "down" then
                -- Up or down
                if nCompletion then
                    -- Cycle completions
                    clear()
                    if param == "up" then
                        nCompletion = nCompletion - 1
                        if nCompletion < 1 then
                            nCompletion = #tCompletions
                        end
                    elseif param == "down" then
                        nCompletion = nCompletion + 1
                        if nCompletion > #tCompletions then
                            nCompletion = 1
                        end
                    end
                    redraw()

                elseif _tHistory then
                    -- Cycle history
                    clear()
                    if param == "up" then
                        -- Up
                        if nHistoryPos == nil then
                            if #_tHistory > 0 then
                                nHistoryPos = #_tHistory
                            end
                        elseif nHistoryPos > 1 then
                            nHistoryPos = nHistoryPos - 1
                        end
                    else
                        -- Down
                        if nHistoryPos == #_tHistory then
                            nHistoryPos = nil
                        elseif nHistoryPos ~= nil then
                            nHistoryPos = nHistoryPos + 1
                        end
                    end
                    if nHistoryPos then
                        sLine = _tHistory[nHistoryPos]
                        nPos, nScroll = utf8.len(sLine), 0
                    else
                        sLine = ""
                        nPos, nScroll = 0, 0
                    end
                    uncomplete()
                    redraw()

                end

            elseif param == "backspace" then
                -- Backspace
                if nPos > 0 then
                    clear()
                    sLine = utf8.sub(sLine, 1, nPos - 1) .. utf8.sub(sLine, nPos + 1)
                    nPos = nPos - 1
                    if nScroll > 0 then nScroll = nScroll - 1 end
                    recomplete()
                    redraw()
                end

            elseif param == "home" then
                -- Home
                if nPos > 0 then
                    clear()
                    nPos = 0
                    recomplete()
                    redraw()
                end

            elseif param == "delete" then
                -- Delete
                if nPos < utf8.len(sLine) then
                    clear()
                    sLine = utf8.sub(sLine, 1, nPos) .. utf8.sub(sLine, nPos + 2)
                    recomplete()
                    redraw()
                end

            elseif param == "end" then
                -- End
                if nPos < utf8.len(sLine) then
                    clear()
                    nPos = utf8.len(sLine)
                    recomplete()
                    redraw()
                end

            elseif param == "tab" then
                -- Tab (accept autocomplete)
                acceptCompletion()

            end

        elseif sEvent == "mouse_click" or sEvent == "mouse_drag" and param == 1 then
            local _, cy = term.getPos()
            if param1 >= sx and param1 <= w and param2 == cy then
                -- Ensure we don't scroll beyond the current line
                nPos = math.min(math.max(nScroll + param1 - sx, 0), utf8.len(sLine))
                redraw()
            end

        elseif sEvent == "term_resize" then
            -- Terminal resized
            w = term.getSize()
            redraw()

        end
    end

    local _, cy = term.getPos()
    term.setBlinking(false)
    term.setPos(w + 1, cy)
    print()

    return sLine
end

function term.init()
    if initiated then
        return
    end
    initiated = true

    local w, h, s = screen.getSize()

    term.setSize(
            math.floor(w / fontWidth),
            math.floor(h / fontHeight),
            s
    )
    
    timerBlinkId = timer.start(blinkDelay)
    local blink = false
    event.on("timer", function(timerId)
        if timerId == timerBlinkId then
            if isBlinking then
                redrawChar(posX, posY)
                blink = not blink
                if blink then
                    screen.drawRectangle(posX * fontWidth + 1 , posY * fontHeight + 1, 1, fontHeight - 2, table.unpack(fgColor))
                end
            end
            timerBlinkId = timer.start(blinkDelay)
        end
    end)
    
end

return term
