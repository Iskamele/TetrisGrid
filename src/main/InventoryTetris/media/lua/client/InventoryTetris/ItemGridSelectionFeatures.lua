require "ISUI/ISButton"
require "InventoryTetris/ItemGrid/UI/Grid/ItemGridUI"
require "InventoryTetris/ItemGrid/UI/Container/ItemGridContainerUI"

-- Selection manager to handle rectangle selection
SelectionManager = {}

function SelectionManager:new()
    local o = {}
    setmetatable(o, self)
    self.__index = self

    o.selectionStart = nil
    o.selectedItems = {}
    o.isSelecting = false
    return o
end

function SelectionManager:startSelection(x, y)
    self.selectionStart = {x = x, y = y}
    self.isSelecting = true
    self.selectedItems = {}
end

function SelectionManager:updateSelection(gridUi, currentX, currentY)
    if not self.isSelecting then return end

    -- Calculate selection rectangle
    local x1 = math.min(self.selectionStart.x, currentX)
    local y1 = math.min(self.selectionStart.y, currentY)
    local x2 = math.max(self.selectionStart.x, currentX)
    local y2 = math.max(self.selectionStart.y, currentY)

    -- Clear previous selection
    self.selectedItems = {}

    -- Find all items within selection rectangle
    for y = y1, y2 do
        for x = x1, x2 do
            local stack = gridUi.grid:getStack(x, y)
            if stack then
                local item = ItemStack.getFrontItem(stack, gridUi.grid.inventory)
                if item then
                    self.selectedItems[item:getID()] = {
                        item = item,
                        stack = stack
                    }
                end
            end
        end
    end
end

function SelectionManager:endSelection()
    self.isSelecting = false
    self.selectionStart = nil
    return self.selectedItems
end

function SelectionManager:renderSelectionBox(gridUi)
    if not self.isSelecting then return end

    local x1 = math.min(self.selectionStart.x, gridUi:getMouseX())
    local y1 = math.min(self.selectionStart.y, gridUi:getMouseY())
    local x2 = math.max(self.selectionStart.x, gridUi:getMouseX())
    local y2 = math.max(self.selectionStart.y, gridUi:getMouseY())

    -- Draw selection rectangle
    gridUi:drawRect(x1, y1, x2 - x1, y2 - y1, 0.3, 0.2, 0.5, 0.8)
    gridUi:drawRectBorder(x1, y1, x2 - x1, y2 - y1, 0.7, 0.2, 0.5, 0.8)
end

-- Category sorting functionality
CategorySorter = {}

function CategorySorter:new(grid)
    local o = {}
    setmetatable(o, self)
    self.__index = self

    o.grid = grid
    return o
end

function CategorySorter:sortByCategory()
    local categorizedItems = {}

    -- First, group all items by category
    for _, stack in ipairs(self.grid:getStacks()) do
        local item = ItemStack.getFrontItem(stack, self.grid.inventory)
        if item then
            local category = TetrisItemCategory.getCategory(item)
            if not categorizedItems[category] then
                categorizedItems[category] = {}
            end
            table.insert(categorizedItems[category], {
                item = item,
                stack = stack
            })
        end
    end

    -- Clear all stacks from grid
    for _, stack in ipairs(self.grid:getStacks()) do
        self.grid:_removeStack(stack)
    end

    -- Place items back in grid by category
    local currentX = 0
    local currentY = 0
    local maxHeightInRow = 0

    for _, category in ipairs(TetrisItemCategory.list) do
        local items = categorizedItems[category]
        if items then
            for _, itemData in ipairs(items) do
                local item = itemData.item
                local w, h = TetrisItemData.getItemSize(item, false)

                -- Check if we need to start a new row
                if currentX + w > self.grid.width then
                    currentX = 0
                    currentY = currentY + maxHeightInRow
                    maxHeightInRow = 0
                end

                -- Place item
                if self.grid:insertItem(item, currentX, currentY, false) then
                    maxHeightInRow = math.max(maxHeightInRow, h)
                    currentX = currentX + w
                end
            end

            -- Add spacing between categories
            currentX = 0
            currentY = currentY + maxHeightInRow + 1
            maxHeightInRow = 0
        end
    end
end

-- Integration with existing UI
local og_onMouseDown = ItemGridUI.onMouseDown
function ItemGridUI:onMouseDown(x, y, gridStack)
    if not self.selectionManager then
        self.selectionManager = SelectionManager:new()
    end

    if isShiftButtonDown() then
        self.selectionManager:startSelection(x, y)
        return true
    end

    return og_onMouseDown(self, x, y, gridStack)
end

local og_onMouseMove = ItemGridUI.onMouseMove
function ItemGridUI:onMouseMove(dx, dy)
    if self.selectionManager and self.selectionManager.isSelecting then
        self.selectionManager:updateSelection(self, self:getMouseX(), self:getMouseY())
        return true
    end

    return og_onMouseMove(self, dx, dy)
end

local og_onMouseUp = ItemGridUI.onMouseUp
function ItemGridUI:onMouseUp(x, y, gridStack)
    if self.selectionManager and self.selectionManager.isSelecting then
        local selectedItems = self.selectionManager:endSelection()
        -- Handle selected items (e.g., for dragging)
        if next(selectedItems) then
            local items = {}
            for _, data in pairs(selectedItems) do
                table.insert(items, data.item)
            end

            local vanillaStacks = ItemStack.createVanillaStacksFromItems(items, self.inventoryPane)
            DragAndDrop.prepareDrag(self, vanillaStacks, x, y)
        end
        return true
    end

    return og_onMouseUp(self, x, y, gridStack)
end

local og_render = ItemGridUI.render
function ItemGridUI:render()
    og_render(self)

    if self.selectionManager then
        self.selectionManager:renderSelectionBox(self)
    end
end

-- Add sort button to container UI
local og_createChildren = ItemGridContainerUI.createChildren
function ItemGridContainerUI:createChildren()
    og_createChildren(self)

    local sortButton = ISButton:new(self:getWidth() - 25, 0, 20, 20, "S", self, function(target)
        local sorter = CategorySorter:new(target.containerGrid)
        sorter:sortByCategory()
    end)
    sortButton:initialise()
    sortButton:instantiate()
    self:addChild(sortButton)
end