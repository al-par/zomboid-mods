require "BuildingObjects/ISBuildUtil"

-- Built entities with isPole = true (the Wooden Pole) must be corners, or they block an edge like a fence.
if buildUtil and buildUtil.setInfo and not buildUtil.WalkThroughPoles_Hooked then
    buildUtil.WalkThroughPoles_Hooked = true
    local originalSetInfo = buildUtil.setInfo
    buildUtil.setInfo = function(javaObject, ISItem)
        originalSetInfo(javaObject, ISItem)
        if ISItem and ISItem.isPole and javaObject and javaObject.setCorner then
            javaObject:setCorner(true)
        end
    end
end
