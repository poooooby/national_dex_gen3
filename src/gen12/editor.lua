-- The save editor on a Red to Crystal save (tools/save-editor in the engine). It loads mods over
-- its Data and lists data.pokemon as it is, so a form showed its base's name and its own dex number
-- (20000 and up, src/gen12/project.lua): Alolan Vulpix read "VULPIX #20091" under "VULPIX #037".
-- In the editor only, each form is relabelled the way the Gen 3 editor shows it (src/editor.lua):
-- "VULPIX (ALOLAN)", with its base's number, so the picker, search and the box sort put it beside
-- its base.
--
-- Only while the editor is loading mods: no game runs there, and Gold rewrites a mon's copied
-- name from the species on every save load (Mon.syncSaveIdentity), so nothing here reaches a game.
-- A game started after the editor closes builds its species records afresh.
local E = {}

-- true while the editor's App.load is loading mods: its session exists and has no loader or
-- catalog yet. After the editor closes App.unload drops the session, so a game started later in
-- the same run (the editor's require path stays set) answers false.
function E.loading(require)
  local okG, Gen = pcall(require, "Gen")
  if not (okG and type(Gen) == "table" and type(Gen.bindGoldData) == "function") then return false end
  local okA, App = pcall(require, "App")
  if not (okA and type(App) == "table" and type(App.getState) == "function") then return false end
  local okS, S = pcall(App.getState)
  return okS and type(S) == "table" and S.mods == nil and S.cat == nil
end

-- forms: src/gen12/species.lua state.forms ({ id, data = the data/gen12/forms.lua row });
-- label: src/dex_forms.lua DexForms.label (form row -> "ALOLAN"). Returns how many were relabelled.
function E.labelForms(data, forms, label)
  local pokemon = type(data) == "table" and data.pokemon
  if type(pokemon) ~= "table" then return 0 end
  local n = 0
  for _, f in ipairs(forms or {}) do
    local def, row = pokemon[f.id], f.data
    if type(def) == "table" and type(row) == "table" and row.name then
      local ok, words = pcall(label, row)
      if ok and type(words) == "string" and words ~= "" then
        def.name = tostring(row.name) .. " (" .. words .. ")"
      end
      if tonumber(row.dex) then def.dex = tonumber(row.dex) end
      n = n + 1
    end
  end
  return n
end

-- mod, require, forms, label, log. On mods.loaded, after every other mod's listener.
function E.install(opts)
  opts.mod.events:on("mods.loaded", function(ev)
    if not E.loading(opts.require) then return end
    local n = E.labelForms(ev and ev.data, opts.forms, opts.label)
    if opts.log and n > 0 then opts.log:info("save editor: %d forms labelled", n) end
  end, -1000)
end

return E
