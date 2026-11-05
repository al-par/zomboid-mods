local function swapSaltLicks(tbl, seen)
    if seen[tbl] then return end
    seen[tbl] = true
    for k, v in pairs(tbl) do
        if v == "Mov_SaltLick" or v == "Base.Mov_SaltLick" then
            tbl[k] = "Base.SLS_SaltLick"
        elseif type(v) == "table" then
            swapSaltLicks(v, seen)
        end
    end
end

Events.OnPreDistributionMerge.Add(function()
    local seen = {}
    if ProceduralDistributions then swapSaltLicks(ProceduralDistributions.list, seen) end
    if VehicleDistributions then swapSaltLicks(VehicleDistributions, seen) end
end)
