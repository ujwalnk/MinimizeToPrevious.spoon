--- === MinimizeToPrevious ===
---
--- Replaces the normal macOS minimize-button behavior.
---
--- Clicking the yellow/orange minimize button:
---   1. Finds the previous visible window.
---   2. Activates it.
---   3. Minimizes the window whose minimize button was clicked.
---
--- Normal left-clicks are passed through unchanged.

local MinimizeToPrevious = {}

MinimizeToPrevious.name = "MinimizeToPrevious"
MinimizeToPrevious.version = "1.0"
MinimizeToPrevious.author = "Ujwal N K"
MinimizeToPrevious.license = "MIT"
MinimizeToPrevious.homepage = "https://github.com/ujwalnk/MinimizeToPrevious"

----------------------------------------------------------------------
-- Configuration
----------------------------------------------------------------------

-- Set to true while debugging Accessibility hit-testing.
MinimizeToPrevious.debug = false

-- Whether to require the clicked window to be a standard window.
-- This avoids accidentally treating unusual UI elements as windows.
MinimizeToPrevious.requireStandardWindow = true

----------------------------------------------------------------------
-- Internal state
----------------------------------------------------------------------

MinimizeToPrevious._eventtap = nil
MinimizeToPrevious._swallowMouseUp = false

----------------------------------------------------------------------
-- Logging
----------------------------------------------------------------------

function MinimizeToPrevious:_log(...)
    if self.debug then
        print("[MinimizeToPrevious]", ...)
    end
end

----------------------------------------------------------------------
-- Accessibility helpers
----------------------------------------------------------------------

--- Walk up the accessibility hierarchy until an AXWindow is found.
---
--- @param element axuielement
--- @return axuielement|nil
function MinimizeToPrevious:_findWindowElement(element)
    local current = element

    -- Prevent pathological accessibility hierarchies.
    for _ = 1, 20 do
        if not current then
            return nil
        end

        local role = current:attributeValue("AXRole")

        if role == "AXWindow" then
            return current
        end

        current = current:attributeValue("AXParent")
    end

    return nil
end

--- Determine whether an accessibility element is the macOS
--- minimize button.
---
--- macOS normally exposes this as:
---
---   AXRole    = AXButton
---   AXSubrole = AXMinimizeButton
---
--- @param element axuielement
--- @return boolean
function MinimizeToPrevious:_isMinimizeButton(element)
    if not element then
        return false
    end

    local role = element:attributeValue("AXRole")
    local subrole = element:attributeValue("AXSubrole")

    self:_log(
        "Hit element:",
        "role =", role,
        "subrole =", subrole
    )

    return role == "AXButton" and subrole == "AXMinimizeButton"
end

--- Find the hs.window corresponding to an accessibility window element.
---
--- @param element axuielement
--- @return hs.window|nil
function MinimizeToPrevious:_hsWindowForAXWindow(element)
    if not element then
        return nil
    end

    return element:asHSWindow()
end

----------------------------------------------------------------------
-- Window selection
----------------------------------------------------------------------

--- Find the window immediately behind the target window in the
--- visible front-to-back window ordering.
---
--- hs.window.orderedWindows() returns visible windows from front
--- to back, so if target is at index N, the first subsequent
--- non-minimized/usable window is the previous window.
---
--- @param target hs.window
--- @return hs.window|nil
function MinimizeToPrevious:_previousWindow(target)
    local windows = hs.window.orderedWindows()
    local targetID = target:id()

    local targetIndex = nil

    for i, window in ipairs(windows) do
        if window:id() == targetID then
            targetIndex = i
            break
        end
    end

    if not targetIndex then
        self:_log("Target window was not found in ordered window list")
        return nil
    end

    -- orderedWindows() is front -> back.
    for i = targetIndex + 1, #windows do
        local candidate = windows[i]

        if candidate
            and candidate:id() ~= targetID
            and candidate:isVisible()
            and not candidate:isMinimized()
        then
            if not self.requireStandardWindow
                or candidate:isStandard()
            then
                return candidate
            end
        end
    end

    return nil
end

----------------------------------------------------------------------
-- Main action
----------------------------------------------------------------------

function MinimizeToPrevious:_handleMinimizeClick(point)
    -- Hit-test the exact point of the click.
    local element = hs.axuielement.systemElementAtPosition(point)

    if not element then
        self:_log("No accessibility element at click position")
        return false
    end

    if not self:_isMinimizeButton(element) then
        return false
    end

    self:_log("Minimize button detected")

    local axWindow = self:_findWindowElement(element)

    if not axWindow then
        self:_log("Could not find parent AXWindow")
        return false
    end

    local targetWindow = self:_hsWindowForAXWindow(axWindow)

    if not targetWindow then
        self:_log("Could not convert AXWindow to hs.window")
        return false
    end

    if self.requireStandardWindow and not targetWindow:isStandard() then
        self:_log("Target is not a standard window")
        return false
    end

    self:_log(
        "Target:",
        targetWindow:title(),
        "app:",
        targetWindow:application()
            and targetWindow:application():name()
            or "unknown"
    )

    local previousWindow = self:_previousWindow(targetWindow)

    if not previousWindow then
        self:_log("No previous window available")

        -- We deliberately do NOT consume the click here.
        -- macOS will perform its normal minimize behavior.
        return false
    end

    self:_log(
        "Previous:",
        previousWindow:title(),
        "app:",
        previousWindow:application()
            and previousWindow:application():name()
            or "unknown"
    )

    ------------------------------------------------------------------
    -- This is the important sequence:
    --
    -- 1. Activate previous window.
    -- 2. Minimize the originally clicked window.
    ------------------------------------------------------------------

    previousWindow:focus()
    targetWindow:minimize()

    return true
end

----------------------------------------------------------------------
-- Event handling
----------------------------------------------------------------------

function MinimizeToPrevious:_eventHandler(event)
    local eventType = event:getType()

    ------------------------------------------------------------------
    -- Mouse down
    ------------------------------------------------------------------

    if eventType == hs.eventtap.event.types.leftMouseDown then
        local point = event:location()

        local handled = self:_handleMinimizeClick(point)

        if handled then
            -- We consumed the mouse-down event.
            --
            -- macOS therefore won't receive the original click and
            -- won't perform its normal minimize action.
            --
            -- Also consume the corresponding mouse-up event.
            self._swallowMouseUp = true

            return true
        end

        return false
    end

    ------------------------------------------------------------------
    -- Mouse up
    ------------------------------------------------------------------

    if eventType == hs.eventtap.event.types.leftMouseUp then
        if self._swallowMouseUp then
            self._swallowMouseUp = false
            return true
        end

        return false
    end

    return false
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

--- Start intercepting minimize-button clicks.
---
--- @return MinimizeToPrevious
function MinimizeToPrevious:start()
    if self._eventtap then
        self._eventtap:stop()
    end

    self._swallowMouseUp = false

    self._eventtap = hs.eventtap.new({
        hs.eventtap.event.types.leftMouseDown,
        hs.eventtap.event.types.leftMouseUp,
    }, function(event)
        return self:_eventHandler(event)
    end)

    self._eventtap:start()

    self:_log("Started")

    return self
end

--- Stop intercepting clicks.
---
--- @return MinimizeToPrevious
function MinimizeToPrevious:stop()
    if self._eventtap then
        self._eventtap:stop()
        self._eventtap = nil
    end

    self._swallowMouseUp = false

    self:_log("Stopped")

    return self
end

--- Toggle the Spoon.
---
--- @return MinimizeToPrevious
function MinimizeToPrevious:toggle()
    if self._eventtap and self._eventtap:isEnabled() then
        return self:stop()
    else
        return self:start()
    end
end

--- Return whether the Spoon is currently running.
---
--- @return boolean
function MinimizeToPrevious:isRunning()
    return self._eventtap ~= nil
        and self._eventtap:isEnabled()
end

return MinimizeToPrevious