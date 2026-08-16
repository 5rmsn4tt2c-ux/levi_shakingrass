local cloneref = cloneref or function(ref: any)
    return ref
end

-- Clear all cached game/gui files so fresh fixed versions are downloaded on next execute
-- (profiles and settings are kept intact)
if isfolder('levi_shakingrass/games') then
    delfolder('levi_shakingrass/games')
end
if isfolder('levi_shakingrass/guis') then
    delfolder('levi_shakingrass/guis')
end
if isfile('levi_shakingrass/games/universal.lua') then
    delfile('levi_shakingrass/games/universal.lua')
end

-- Legacy cleanup
if isfolder('catrewrite') then
    delfolder('catrewrite')
end

cloneref(game:GetService('StarterGui')):SetCore('SendNotification', {
    Title = 'Milyonpuffnoodles',
    Text = 'Cache cleared! Rejoin the game and execute the script to get fresh files.',
    Duration = 20
})
