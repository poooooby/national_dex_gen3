-- The engine's Gen 3 registry write (src/mods/Schemas.lua, from the API 3 update), adjusted for
-- this mod's alternate forms -- and, on an engine from before the cap fix, its slot ceiling.
--
-- 1. Forms. The write records each species' DISPLAY name in the live P._byName (last one wins)
--    and maps its National number back to its slot (toSpecies[dex] = slot). A form carries its
--    base's name and number (MEOWTH_GALAR shows "MEOWTH", dex 52), so it took over the base:
--    MEOWTH resolved to the Galarian form, and Modern Moves' rows for #211 landed on Hisuian
--    Qwilfish. Here a form keeps only its own id key and never claims the base's number (the
--    rule this mod's fixups have always followed); other display names are first-wins.
-- 2. The cap. The first API 3 build capped every native slot at 1..1023 in a local function,
--    below our saved slots (species to 1217, TM items to 1213). bryanthaboi's fix (79ea62f4)
--    raised it to 65535; on an older build the two literals are raised to 2047 here.
--
-- A mod cannot wrap a local, but it can do what src/dex_patch.lua does to the Pokedex: read the
-- engine source, replace exact text, run the copy, and take just what it needs from it -- the
-- three Gen 3 write closures, `REGISTRIES[name].gen3Write` for pokemon, moves and items, plus
-- the Gen 3 view (`Schemas.gen3View`) they share caches with. Installed where the engine reads them:
--   * `Schemas.REGISTRIES[name].gen3Write`: the base spec, for any registry derived later;
--   * each live registry's `spec.write`: `Schemas.shapeFor` copied gen3Write into the derived
--     spec when the loader built the registries, BEFORE this mod's entry ran -- and both call
--     sites (Loader's merge, Gen3Compat's reload) look it up on `registry.spec` at call time.
-- Any failure (source unreadable, text not the expected one, compile error) logs once and leaves
-- the stock write. On the fixed engine that only loses the form rules (forms would shadow their
-- base's name and number, as described above); on an older build the species fail to register.
--
-- The engine-side change that would retire this file: skip the display-name and toSpecies
-- writes for records with a `baseSpecies` in `updateNativeNames` / `writeMon`.
local SchemaPatch = {}

local PATH = "src/mods/Schemas.lua"
local CAP = 2047                     -- the outer gate only; gen3Fields still caps each registry
local REGISTRIES = { "pokemon", "moves", "items" }

-- the engine source, in the game/editor (CacheBlob reads through love) or headless (the test
-- harness's io-backed fs, repo-relative like love.filesystem)
local function readSource(require)
  local okB, Blob = pcall(require, "src.import.CacheBlob")
  if okB and type(Blob) == "table" and type(Blob.readFs) == "function" then
    local ok, src = pcall(Blob.readFs, PATH)
    if ok and type(src) == "string" and #src > 0 then return src end
  end
  local okF, FsIo = pcall(require, "tests.fs_io")
  if okF and type(FsIo) == "table" and type(FsIo.new) == "function" then
    local ok, src = pcall(function() return FsIo.new(".").read(PATH) end)
    if ok and type(src) == "string" and #src > 0 then return src end
  end
  return nil
end

-- opts: { require, log, registry = fn(name) -> the live registry (mod.content[name]) or nil }
function SchemaPatch.install(opts)
  local require, log = opts.require, opts.log
  local function fail(why)
    if log then log:warn("the engine's species write is left as it is (%s)", tostring(why)) end
    return false
  end
  local okS, Schemas = pcall(require, "src.mods.Schemas")
  if not (okS and type(Schemas) == "table" and type(Schemas.REGISTRIES) == "table") then
    return fail("the schema module was not found")
  end
  if Schemas.__nationalDexIndexCap then return true end

  local src = readSource(require)
  if not src then return fail("engine source not readable") end
  -- an engine from before the native write path has no 1023 gate: nothing to patch
  if not src:find("prepareNativeWrite", 1, true) then return true end
  local n1, n2, n3
  src, n1 = src:gsub("num >= 1 and num <= 1023", "num >= 1 and num <= " .. CAP)
  src, n2 = src:gsub("for num = 1, 1023 do", "for num = 1, " .. CAP .. " do")
  -- the copy starts with an empty `bound` map (Schemas.bindGen3 ran on the live module before
  -- this mod loaded), so its sibling() lookups must reach the live engine modules; `package` is
  -- not in a mod's sandbox, so its one package.loaded read goes through require instead
  src, n3 = src:gsub('return package%.loaded%[path or ""%]',
    'return __nationalDexPkgLoaded(path)')
  -- the cap: an engine from before the fix (bryanthaboi 79ea62f4, cap 65535) has the two 1023
  -- literals; a fixed engine has neither and needs no change
  local capped = n1 == 1 and n2 == 1
  if not ((capped or (n1 == 0 and n2 == 0)) and n3 == 1) then
    return fail("engine source is not the expected one")
  end
  -- the write also puts each species record's DISPLAY name into the live P._byName, last
  -- registration wins: an alternate form named like its base (MEOWTH_GALAR shows "MEOWTH",
  -- MR_MIME_GALAR shows "MR. MIME") would then answer for the base species everywhere a name is
  -- resolved. A form (a record with baseSpecies) keeps only its own id key, the rule the
  -- fixups' name keys follow; everything else is first-wins, so the cart's names survive.
  local FIND = 'if normalized then byName[normalized:gsub("[^%w]", "")] = num end'
  local REPL = 'if normalized and value.baseSpecies == nil then'
    .. ' local key = normalized:gsub("[^%w]", "")'
    .. ' if byName[key] == nil then byName[key] = num end end'
  local s2, e2 = src:find(FIND, 1, true)
  if not s2 then return fail("engine source is not the expected one (names)") end
  src = src:sub(1, s2 - 1) .. REPL .. src:sub(e2 + 1)
  if src:find(FIND, 1, true) then return fail("engine source is not the expected one (names twice)") end
  -- same rule for the National number map: the write sets toSpecies[dex] = slot for every
  -- record, so a form (dex = its base's) would claim its base's National number -- Modern
  -- Moves would then land on the form and the Pokedex would open the form for the base.
  -- toNational[slot] stays; the reverse entry is for base species only.
  local FIND2 = 'if toSpecies then toSpecies[national] = num end'
  local REPL2 = 'if toSpecies and value.baseSpecies == nil then toSpecies[national] = num end'
  local s3, e3 = src:find(FIND2, 1, true)
  if not s3 then return fail("engine source is not the expected one (national)") end
  src = src:sub(1, s3 - 1) .. REPL2 .. src:sub(e3 + 1)
  if src:find(FIND2, 1, true) then return fail("engine source is not the expected one (national twice)") end
  __nationalDexPkgLoaded = function(path)
    if type(path) ~= "string" or path == "" then return nil end
    local okM, m = pcall(require, path)
    if okM then return m end
    return nil
  end

  local chunk, err = load(src, "@" .. PATH)
  if not chunk then return fail("compile: " .. tostring(err)) end
  local okC, copy = pcall(chunk)
  if not (okC and type(copy) == "table" and type(copy.REGISTRIES) == "table") then
    return fail("run: " .. tostring(copy))
  end
  local patched = {}
  for _, name in ipairs(REGISTRIES) do
    local fresh = copy.REGISTRIES[name]
    local write = type(fresh) == "table" and fresh.gen3Write
    if type(write) ~= "function" then return fail(name .. ": the patched write was not built") end
    patched[name] = write
  end
  -- preindex (the loader's early slot allocation) and the rest of the Gen 3 view run through
  -- `Schemas.gen3View.<fn>`, looked up at call time; the fresh view's functions share one
  -- name-index cache with the fresh writes, so allocations made by one are seen by the other
  if not (type(copy.gen3View) == "table" and type(copy.gen3View.preindex) == "function"
      and type(Schemas.gen3View) == "table") then
    return fail("the patched Gen 3 view was not built")
  end

  for _, name in ipairs(REGISTRIES) do
    local spec = Schemas.REGISTRIES[name]
    if type(spec) ~= "table" or type(spec.gen3Write) ~= "function" then
      return fail(name .. ": the engine spec has no gen3 write")
    end
    spec.gen3Write = patched[name]
    -- the loader's registries hold the DERIVED spec (gen3Write copied into `write` before this
    -- mod's entry ran); shapeFor is cached, so it answers that same table
    if type(Schemas.shapeFor) == "function" then
      local okD, derived = pcall(Schemas.shapeFor, name, spec, opts.generation or 3)
      if okD and type(derived) == "table" and derived ~= spec
          and type(derived.write) == "function" then
        derived.write = patched[name]
      end
    end
  end
  for key, value in pairs(copy.gen3View) do Schemas.gen3View[key] = value end
  Schemas.__nationalDexIndexCap = CAP
  if log then
    if capped then log:info("native index cap raised to %d (species, moves, items)", CAP)
    else log:info("forms kept out of their base's name and National number") end
  end
  return true
end

return SchemaPatch
