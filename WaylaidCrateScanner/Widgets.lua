local _, ns = ...

-- Small UI building blocks shared by the scanner window (UI.lua) and the Buy window (BuyUI.lua).

ns.COLOR = {
  CRATE = "|cffffd100",
  GREY = "|cff808080",
  DIM = "|cffa0a0a0",
  RED = "|cffff4040",
  ORANGE = "|cffff9933",
  GREEN = "|cff40ff40",
  CRAFT = "|cff66ccff",
  FAVOR = "|cffe6cc80",
}

function ns.MakeButton(parent, text, width, height)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, height or 22)
  b:SetText(text)
  return b
end

--- Static hover tooltip. body may be a string, nil, or a function returning the text.
function ns.SimpleTooltip(frame, title, body)
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(title)
    local text = type(body) == "function" and body() or body
    if text then
      GameTooltip:AddLine(text, 1, 1, 1, true)
    end
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", GameTooltip_Hide)
end

--- A movable portrait window that closes with Escape and is dragged by its title bar.
--- onMoved (optional) runs after the player drags it.
function ns.CreatePanelWindow(name, title, onMoved)
  local f = CreateFrame("Frame", name, UIParent, "PortraitFrameTemplate")
  f:SetToplevel(true)
  f:SetFrameStrata("HIGH")
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  if f.SetTitle then
    f:SetTitle(title)
  end
  if f.SetPortraitToAsset then
    f:SetPortraitToAsset(ns.ICON)
  end
  if not f.Bg then
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetPoint("TOPLEFT", 2, -2)
    bg:SetPoint("BOTTOMRIGHT", -2, 2)
    bg:SetColorTexture(0.06, 0.06, 0.06, 0.95)
  end
  f:Hide()
  table.insert(UISpecialFrames, name) -- close with Escape

  local drag = CreateFrame("Frame", nil, f)
  drag:SetPoint("TOPLEFT", f, "TOPLEFT", 60, 0)
  drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, 0)
  drag:SetHeight(22)
  drag:EnableMouse(true)
  drag:RegisterForDrag("LeftButton")
  drag:SetScript("OnDragStart", function()
    f:StartMoving()
  end)
  drag:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    if onMoved then
      onMoved()
    end
  end)
  return f
end
