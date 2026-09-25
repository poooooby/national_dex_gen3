-- Test stub for a companion mod that adds a held item FireRed doesn't have:
-- a Protector, the item Rhydon -> Rhyperior needs (data/species/crossgen.lua).
return function(mod)
  mod.content.items:register("PROTECTOR", {
    id = "PROTECTOR", name = "Protector", index = 400, pocket = "ITEMS", price = 0,
  })
end
