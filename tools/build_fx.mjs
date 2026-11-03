#!/usr/bin/env node
// Battle animations drawn with pixelfx (https://github.com/patch-gg/pixelfx, MIT, Copyright (c) 2026 Patch,
// Copyright (c) 2026 Hugo Duprez) for new moves whose pokeemerald-expansion script needs graphics no Gen 3 cart has.
//
// pixelfx effects are code that draws each frame. This renders the ones listed in SHEETS below in grays (each
// palette an even gray ramp), and tools/fx_atlas.py packs every frame of every sheet, trimmed to what it draws,
// into one gray + alpha atlas (assets/fx/atlas.png). A move colours its effect at draw time with one of the
// ramps (src/fx_anims.lua maps each gray onto the ramp), so one orb serves Aura Sphere, Focus Blast and Energy
// Ball. data/fx.lua holds the atlas layout, the ramps and MOVES, the battle scripts that play them (rows for
// the engine's animation player, the shape data/anims.lua has; src/fx_anims.lua plays them through its own
// visual task, "NdxFx").
//
//   node tools/build_fx.mjs              build (clones pixelfx at PIXELFX_COMMIT into tools/.cache the first time)
//   node tools/build_fx.mjs --preview    also writes a contact sheet per sheet to tools/.cache/fx_preview
//
// Needs Python with Pillow for the packing. A sheet's or ramp's name is what the scripts and src/fx_anims.lua
// know it by; renaming one means updating MOVES.

import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync, rmSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const PIXELFX_URL = "https://github.com/patch-gg/pixelfx.git";
const PIXELFX_COMMIT = "a84159688af3ca37a4be05a0d422b94451b2e24e";
const SRC = join(ROOT, "tools", ".cache", "pixelfx_src", "repo");
const PREVIEW = process.argv.includes("--preview");

// ---------- ramps (dark to bright, 8 steps): what a move's grays become. Each sheet also gets its effect's
// own palette as a ramp named after it (lower case), for a move that names none; these are for the types.

const PAL = {
  dragon: ["#0c0828", "#1c1460", "#2c2498", "#4038d0", "#6060f0", "#8c98ff", "#c4ccff", "#ffffff"],
  steel: ["#10141c", "#222a36", "#3a4656", "#566678", "#7a8a9c", "#a4b2c2", "#d4dee8", "#ffffff"],
  electric: ["#2a1a04", "#5a3a06", "#96660a", "#d0a010", "#f0d020", "#fff060", "#fffab0", "#ffffff"],
  aura: ["#04102a", "#0a2460", "#10409c", "#1c66d4", "#3c96f4", "#7cc4ff", "#c4e8ff", "#ffffff"],
  focus: ["#2a0c04", "#5c1c06", "#9a360a", "#d85a12", "#f48a24", "#ffbc4a", "#ffe49a", "#ffffff"],
  grass: ["#061a08", "#0e3a12", "#1a5e1c", "#2c8a26", "#4cb436", "#84dc54", "#c4f490", "#ffffff"],
  ghost: ["#0c0618", "#1e0e3a", "#34186a", "#52289c", "#7444c8", "#9c70e8", "#ccacff", "#ffffff"],
  dark: ["#0a0408", "#1e0a14", "#3a1224", "#5e1a34", "#8a2a4a", "#b84a6a", "#e6a0b4", "#ffffff"],
  poison: ["#12061a", "#2a0c3a", "#461462", "#66208a", "#8a34b0", "#b05cd4", "#d89cf0", "#f8e0ff"],
  pink: ["#1a0410", "#3c0a24", "#6a1240", "#a01c5c", "#d42c7c", "#f45c9c", "#ff96c0", "#ffffff"],
  wind: ["#1c2230", "#2e3648", "#465064", "#626e84", "#8692a6", "#aab4c6", "#d2dae6", "#ffffff"],
  ground: ["#120c0c", "#2b1d17", "#4a3326", "#6e4c34", "#a0602a", "#e08a2a", "#ffc860", "#fff0c0"],
};

// ---------- the sheets
// fx: the pixelfx effect; opts: its options (colours become grays); from/to: the seconds kept; speed: played
// that much faster; cut: the alpha below which a pixel is dropped, for one whose glow is a disc (ALPHA_CUT
// below); scale: drawn this much smaller (an explosion made for a 24 px hero is bigger than the battle
// screen), or bigger (pixel for pixel: a block of ice made for that hero is half a Pokemon); fps: frames a
// second kept (30, or 20 for a long loop); pin: the effect point placed on the battler ("center" of what it
// draws, "origin" = its anchor, or [x, y] from the anchor); patch: [find, replace] pairs applied to a copy of
// the effect's source (a beam's length)

const BEAM_LEN = 100;
const SHEETS = {
  BEAM: { fx: "arcane/arcane-beam", pin: [15, -24], reach: BEAM_LEN, patch: [["L = 168", `L = ${BEAM_LEN}`]] },
  BALL_SPARK: { fx: "lightning/ball-lightning", to: 1.0, pin: "center" },
  ORB: { fx: "arcane/arcane-orb", to: 1.2, pin: "center" },
  BURST: { fx: "explosions/plasma-explosion", scale: 0.5, to: 0.9, pin: "origin" },
  VOID_ORB: { fx: "shadow/void-orb", fps: 20, to: 1.6, pin: "center" },
  SHADOW_FLAMES: { fx: "shadow/shadow-flames", fps: 20, to: 1.6, pin: "center" },
  EARTH_SPIKE: { fx: "nature/earth-spike", from: 0.2, to: 2.3, speed: 1.5, pin: "origin" },
  QUAKE: { fx: "nature/quake", from: 0.1, to: 2.2, speed: 1.4, pin: "origin" },
  TORNADO: { fx: "nature/tornado", fps: 20, to: 2.0, pin: "origin" },
  LIGHTNING_STRIKE: { fx: "lightning/lightning-strike", cut: 170, fps: 20, from: 0.4, to: 2.4, speed: 1.3, pin: "origin" },
  ICICLE_FALL: { fx: "ice/icicle-fall", to: 2.0, speed: 1.3, pin: "origin" },
  ICE_LANCE: { fx: "ice/ice-lance", to: 0.8, pin: "origin" },
  ICE_SHATTER: { fx: "ice/ice-shatter", scale: 1.5, to: 1.6, speed: 1.3, pin: "origin" },
  SLASH: { fx: "melee/double-slash", pin: "center" },
  CLAW: { fx: "melee/claw-swipe", pin: "center" },
  ACID: { fx: "nature/acid-splash", to: 2.0, speed: 1.4, pin: "origin" },
  FIRE_RING: { fx: "fire/fire-ring", fps: 20, to: 2.6, speed: 1.5, pin: "origin" },
  FLAME: { fx: "fire/spirit-flame", fps: 20, to: 1.6, pin: "center" },
  CRIT_HIT: { fx: "impacts/crit-hit", pin: "center" },
};

// ---------- the battle scripts: rows for the engine's animation player
// fx(sheet, mode, dx, dy, frames, flags, ramp): src/fx_anims.lua's task, its arguments
// { "FX:" .. sheet, MODE, dx, dy, frames, FLAG bits, "FX:" .. ramp } (no ramp: the sheet's own). mode:
// "attacker" | "target" (on that battler's centre + dx, dy), "travel" (attacker to target over `frames`),
// "beam" (from the attacker, stretched to the target). frames 0 = the sheet's own length. flags: "ground" (on
// the battler's feet), "aim" (turned toward the target), "back" (behind the battlers). Numbers in the rows:
// the anims resolver passes only SE: / TAG: / FX: strings through.
const MODE = { attacker: 0, target: 1, travel: 2, beam: 3 };
const FLAG = { ground: 1, aim: 2, back: 4 };

const ATK = -64, TGT = 63;
const fx = (sheet, mode, dx = 0, dy = 0, frames = 0, flags = "", ramp = "") => {
  if (MODE[mode] === undefined) throw new Error("no mode " + mode);
  const bits = flags.split(" ").filter(Boolean).reduce((b, f) => (FLAG[f] ? b | FLAG[f] : (() => { throw new Error("no flag " + f); })()), 0);
  return { op: "createvisualtask", task: "NdxFx", priority: 2,
    args: ["FX:" + sheet, MODE[mode], dx, dy, frames, bits, ...(ramp ? ["FX:" + ramp] : [])] };
};
const se = (name, pan = TGT) => ({ op: "playsewithpan", se: name, pan });
const delay = (frames) => ({ op: "delay", frames });
const wait = () => ({ op: "waitforvisualfinish" });
const shake = (n = 6, x = 3, y = 0) => ({ op: "createvisualtask", task: "AnimTask_ShakeMon", priority: 2, args: [1, x, y, n, 1] });
const lunge = () => ({ op: "createsprite", template: "gHorizontalLungeSpriteTemplate", animBattler: "attacker", subpriority: 2, args: [4, 4] });
const END = { op: "end" };

const shot = (ramp, sound, hitSound) => [
  se(sound, ATK), fx("ORB", "attacker", 0, 0, 16, "", ramp), wait(),
  fx("ORB", "travel", 0, 0, 18, "", ramp), wait(),
  se(hitSound), fx("BURST", "target", 0, 0, 0, "", ramp), delay(4), shake(), wait(), END,
];
const MOVES = {
  DRAGON_PULSE: [se("SE_M_PSYBEAM", ATK), fx("BEAM", "beam", 0, 0, 44, "", "dragon"), delay(8), shake(8), wait(), END],
  FLASH_CANNON: [se("SE_M_HYPER_BEAM", ATK), fx("BEAM", "beam", 0, 0, 40, "", "steel"), delay(8), shake(8), wait(), END],
  CHARGE_BEAM: [se("SE_M_CHARGE", ATK), fx("BALL_SPARK", "attacker", 0, 0, 30, "", "electric"), wait(),
    se("SE_M_THUNDERBOLT", ATK), fx("BEAM", "beam", 0, 0, 36, "", "electric"), delay(8), shake(6), wait(), END],
  AURA_SPHERE: shot("aura", "SE_M_CHARGE", "SE_M_SELF_DESTRUCT"),
  FOCUS_BLAST: shot("focus", "SE_M_CHARGE", "SE_M_EXPLOSION"),
  ENERGY_BALL: shot("grass", "SE_M_SOLAR_BEAM", "SE_M_GIGA_DRAIN"),
  DARK_PULSE: [se("SE_M_NIGHTMARE", ATK), fx("VOID_ORB", "attacker", 0, 0, 24), wait(),
    fx("VOID_ORB", "travel", 0, 0, 20), wait(), se("SE_M_FAINT_ATTACK"), shake(8), delay(10), END],
  HEX: [se("SE_M_NIGHTMARE"), fx("SHADOW_FLAMES", "target", 0, 0, 48, "", "ghost"), delay(10), shake(5, 2), wait(), END],
  STONE_EDGE: [se("SE_M_ROCK_THROW"), fx("EARTH_SPIKE", "target", 0, 0, 0, "ground"), delay(14), shake(6, 0, 3), wait(), END],
  BULLDOZE: [se("SE_M_EARTHQUAKE"), fx("QUAKE", "target", 0, 0, 0, "ground", "ground"), delay(6), shake(10, 0, 3), wait(), END],
  HURRICANE: [se("SE_M_GUST"), fx("TORNADO", "target", 0, 0, 60, "ground", "wind"), delay(12), se("SE_M_GUST2"), shake(10, 2), wait(), END],
  BOLT_STRIKE: [se("SE_M_THUNDERBOLT2"), fx("LIGHTNING_STRIKE", "target", 0, 0, 0, "ground"), delay(14), shake(8), wait(), END],
  ICICLE_CRASH: [se("SE_M_ICY_WIND"), fx("ICICLE_FALL", "target", 0, 0, 0, "ground"), delay(24), se("SE_M_BLIZZARD2"), shake(6, 0, 3), wait(), END],
  ICE_SHARD: [se("SE_M_ICY_WIND", ATK), fx("ICE_LANCE", "travel", 0, 0, 12, "aim"), wait(),
    se("SE_M_BLIZZARD2"), fx("ICE_SHATTER", "target", 0, 0, 0, "ground"), shake(4), wait(), END],
  NIGHT_SLASH: [lunge(), delay(4), se("SE_M_CUT"), fx("SLASH", "target", 0, 0, 0, "", "dark"), shake(4), wait(), END],
  SHADOW_CLAW: [lunge(), delay(4), se("SE_M_SCRATCH"), fx("CLAW", "target", 0, 0, 0, "", "ghost"), shake(4), wait(), END],
  GUNK_SHOT: [se("SE_M_TOXIC"), fx("ACID", "target", 0, 0, 0, "ground", "poison"), delay(10), shake(5, 2), wait(), END],
  LAVA_PLUME: [se("SE_M_FLAMETHROWER", ATK), fx("FIRE_RING", "attacker", 0, 0, 0, "ground"), delay(16), shake(6), wait(), END],
  MYSTICAL_FIRE: [se("SE_M_SACRED_FIRE"), fx("FLAME", "target", 0, 0, 44, "", "pink"), delay(8), shake(5, 2), wait(), END],
  GIGA_IMPACT: [lunge(), delay(4), se("SE_M_MEGA_KICK2"), fx("CRIT_HIT", "target"), shake(10, 4), wait(), END],
};

// ---------- pixelfx

function ensureSource() {
  const git = (...args) => spawnSync("git", args, { cwd: SRC, encoding: "utf8" });
  if (!existsSync(join(SRC, ".git"))) {
    mkdirSync(dirname(SRC), { recursive: true });
    const r = spawnSync("git", ["clone", PIXELFX_URL, SRC], { stdio: "inherit" });
    if (r.status !== 0) throw new Error("could not clone " + PIXELFX_URL);
  }
  if (git("rev-parse", "HEAD").stdout.trim() !== PIXELFX_COMMIT) {
    if (git("cat-file", "-e", PIXELFX_COMMIT + "^{commit}").status !== 0) git("fetch", "origin", PIXELFX_COMMIT);
    const r = git("checkout", "--quiet", PIXELFX_COMMIT);
    if (r.status !== 0) throw new Error("could not check out pixelfx " + PIXELFX_COMMIT + ": " + r.stderr);
  }
}

ensureSource();
const lib = await import(pathToFileURL(join(SRC, "tools", "lib", "fxlib.mjs")).href);
const { encodePNG } = await import(pathToFileURL(join(SRC, "tools", "lib", "png.mjs")).href);

// an effect, or a patched copy of it (written next to the original so its imports resolve)
const patched = [];
async function effectFor(spec, name) {
  if (!spec.patch) return lib.loadEffect(spec.fx);
  const [cat, base] = spec.fx.split("/");
  let src = readFileSync(join(SRC, "src", "fx", cat, base + ".js"), "utf8");
  for (const [find, repl] of spec.patch) {
    if (!src.includes(find)) throw new Error(`${name}: "${find}" is not in ${spec.fx}`);
    src = src.replace(find, repl);
  }
  const id = `${cat}/_ndx_${name.toLowerCase()}`;
  const file = join(SRC, "src", "fx", id + ".js");
  writeFileSync(file, src);
  patched.push(file);
  return lib.loadEffect(id);
}

// pixels fainter than this are dropped: a soft glow over nothing reads as a dark haze on a bright battle
// background, and the carts' own art has no soft edges
const ALPHA_CUT = 72;
// and so are see-through dark ones (a gray this low): an effect's dimming of the sky around it, which the
// trimmed frame would cut into a box
const DARK_CUT = 60;

// ---------- colours

const hex = (h) => {
  h = h.replace("#", "");
  if (h.length === 3) h = h.split("").map((c) => c + c).join("");
  return [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16));
};
const toHex = (c) => "#" + c.map((v) => Math.round(v).toString(16).padStart(2, "0")).join("");
const luma = (c) => Math.round(0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]);
const isHex = (x) => typeof x === "string" && /^#[0-9a-f]{3,8}$/i.test(x);
// any ramp as 8 steps, as pixelfx's fit() does
const fit8 = (r) => Array.from({ length: 8 }, (_, i) => r[Math.round((i * (r.length - 1)) / 7)]);
// an effect's options in grays: its palette an even ramp (so a gray is a step of a move's ramp), every other
// colour its own brightness
function grayOptions(options) {
  const out = {};
  for (const [k, v] of Object.entries(options ?? {})) {
    if (k === "palette" && Array.isArray(v)) out[k] = v.map((_, i) => toHex(Array(3).fill((255 * i) / (v.length - 1))));
    else if (Array.isArray(v) && v.length && v.every(isHex)) out[k] = v.map((x) => toHex(Array(3).fill(luma(hex(x)))));
    else if (isHex(v)) out[k] = toHex(Array(3).fill(luma(hex(v))));
    else out[k] = v;
  }
  return out;
}

// ---------- render each sheet in grays, trimmed to the box all its frames draw in

const outDir = join(ROOT, "assets", "fx");
const tmpDir = join(ROOT, "tools", ".cache", "fx_frames");
mkdirSync(outDir, { recursive: true });
mkdirSync(tmpDir, { recursive: true });
const sheetsOut = {}, manifest = [], ramps = {};
for (const [k, v] of Object.entries(PAL)) ramps[k] = fit8(v);
try {
  for (const [name, spec] of Object.entries(SHEETS)) {
    const fxm = await effectFor(spec, name);
    const meta = fxm.meta, fps = spec.fps ?? 30, speed = spec.speed ?? 1;
    const opts = grayOptions({ ...meta.options, ...(spec.opts ?? {}) });
    const r = lib.renderFrames(fxm, { bg: "none", fps: fps / speed, options: opts });
    const first = Math.round((spec.from ?? 0) * fps / speed);
    const last = Math.min(r.n - 1, spec.to !== undefined ? Math.round(spec.to * fps / speed) : r.n - 1);
    const frames = r.frames.slice(first, last + 1), cut = spec.cut ?? ALPHA_CUT;
    for (const f of frames)
      for (let i = 3; i < f.clear.length; i += 4) {
        const c = f.clear;
        if (c[i] < cut || (c[i] < 255 && Math.max(c[i - 3], c[i - 2], c[i - 1]) < DARK_CUT)) c[i] = 0;
      }
    let x0 = r.w, y0 = r.h, x1 = -1, y1 = -1;
    for (const f of frames)
      for (let y = 0; y < r.h; y++)
        for (let x = 0; x < r.w; x++)
          if (f.clear[(y * r.w + x) * 4 + 3] > 0) {
            if (x < x0) x0 = x;
            if (x > x1) x1 = x;
            if (y < y0) y0 = y;
            if (y > y1) y1 = y;
          }
    if (x1 < 0) throw new Error(`${name}: draws nothing`);
    const w = x1 - x0 + 1, h = y1 - y0 + 1, n = frames.length;
    const cols = Math.min(n, Math.max(1, Math.ceil(Math.sqrt((n * h) / w)))), rows = Math.ceil(n / cols);
    const W = cols * w, H = rows * h;
    const img = new Uint8ClampedArray(W * H * 4);
    frames.forEach((f, i) => {
      const ox = (i % cols) * w, oy = Math.floor(i / cols) * h;
      for (let y = 0; y < h; y++) {
        const s = ((y + y0) * r.w + x0) * 4, d = ((oy + y) * W + ox) * 4;
        img.set(f.clear.subarray(s, s + w * 4), d);
      }
    });
    const file = join(tmpDir, name.toLowerCase() + ".png");
    writeFileSync(file, encodePNG(W, H, img));
    const k = spec.scale ?? 1, fw = Math.max(1, Math.round(w * k)), fh = Math.max(1, Math.round(h * k));
    manifest.push({ name, file, w, h, cols, n, fw, fh, cut });
    // the pin, in the (scaled) frame's pixels
    const [OX, OY] = meta.origin;
    let px, py;
    if (spec.pin === "center") [px, py] = [(x0 + x1 + 1) / 2, (y0 + y1 + 1) / 2];
    else if (Array.isArray(spec.pin)) [px, py] = [OX + spec.pin[0], OY + spec.pin[1]];
    else [px, py] = [OX, OY];
    // its own colours, for a move that names no ramp
    const own = name.toLowerCase();
    ramps[own] = fit8(spec.opts?.palette ?? meta.options.palette);
    sheetsOut[name] = {
      fx: spec.fx, frames: n, fps, loop: !!meta.loop, ramp: own,
      px: Math.round((px - x0) * k), py: Math.round((py - y0) * k),
      ...(spec.reach ? { reach: spec.reach } : {}),
    };
    if (PREVIEW) {
      const dir = join(ROOT, "tools", ".cache", "fx_preview");
      mkdirSync(dir, { recursive: true });
      writeFileSync(join(dir, own + ".png"), lib.contactSheet(fxm, { ...r, frames, n }, { max: 12, width: 1000, title: `${name}  ${fw}x${fh}  ${n}F` }));
    }
    process.stdout.write(`${name} ${fw}x${fh} ${n}f\n`);
  }
} finally {
  for (const f of patched) rmSync(f, { force: true });
}
for (const [k, v] of Object.entries(ramps)) ramps[k] = v.map((c) => toHex(hex(c)));

// ---------- one atlas (tools/fx_atlas.py)

for (const f of readdirSync(outDir)) if (f.endsWith(".png")) rmSync(join(outDir, f));
const manifestFile = join(tmpDir, "manifest.json"), layoutFile = join(tmpDir, "layout.json");
const atlasFile = join(outDir, "atlas.png");
writeFileSync(manifestFile, JSON.stringify({ sheets: manifest }));
const packed = spawnSync("python", [join(ROOT, "tools", "fx_atlas.py"), manifestFile, atlasFile, layoutFile], { encoding: "utf8" });
if (packed.status !== 0) throw new Error("tools/fx_atlas.py (Python with Pillow) failed: " + (packed.stderr || packed.error));
const layout = JSON.parse(readFileSync(layoutFile, "utf8"));
for (const [name, rects] of Object.entries(layout.sheets)) sheetsOut[name].rects = rects.flat();

// every sheet and ramp a script names must exist
for (const [move, rows] of Object.entries(MOVES))
  for (const r of rows)
    if (r.task === "NdxFx") {
      if (!sheetsOut[r.args[0].slice(3)]) throw new Error(`${move}: no sheet ${r.args[0]}`);
      if (r.args[6] && !ramps[r.args[6].slice(3)]) throw new Error(`${move}: no ramp ${r.args[6]}`);
    }

// ---------- data/fx.lua

const lua = (v) => {
  if (Array.isArray(v)) return "{ " + v.map((x) => lua(x)).join(", ") + " }";
  if (v && typeof v === "object") {
    return "{ " + Object.keys(v).map((k) => `${/^[A-Za-z_]\w*$/.test(k) ? k : `["${k}"]`} = ${lua(v[k])}`).join(", ") + " }";
  }
  if (typeof v === "string") return JSON.stringify(v);
  return String(v);
};
const label = (move) => "NdxFx_" + move;
let out = "-- Generated by tools/build_fx.mjs from pixelfx " + PIXELFX_COMMIT.slice(0, 7) + " (MIT,\n" +
  "-- https://github.com/patch-gg/pixelfx). Do not edit by hand.\n" +
  "return {\n  source = " + lua("pixelfx " + PIXELFX_COMMIT.slice(0, 7)) + ",\n" +
  "  mode = " + lua(MODE) + ",\n  flag = " + lua(FLAG) + ",\n" +
  "  atlas = " + lua({ file: "assets/fx/atlas.png", w: layout.w, h: layout.h }) + ",\n  ramps = {\n";
for (const name of Object.keys(ramps).sort()) out += `    ${name} = ${lua(ramps[name])},\n`;
out += "  },\n  -- rects: x, y, w, h (in the atlas), ox, oy (where that sits in the frame), six numbers a frame\n  sheets = {\n";
for (const name of Object.keys(sheetsOut).sort()) out += `    ${name} = ${lua(sheetsOut[name])},\n`;
out += "  },\n  moves = {\n";
for (const move of Object.keys(MOVES).sort()) out += `    ${move} = ${lua(label(move))},\n`;
out += "  },\n  labels = {\n";
for (const move of Object.keys(MOVES).sort()) {
  out += `    ["${label(move)}"] = {\n`;
  for (const r of MOVES[move]) out += `      ${lua(r)},\n`;
  out += "    },\n";
}
out += "  },\n}\n";
writeFileSync(join(ROOT, "data", "fx.lua"), out);
console.log(`${Object.keys(sheetsOut).length} sheets in a ${layout.w}x${layout.h} atlas (${(statSync(atlasFile).size / 1024).toFixed(0)} KB), ` +
  `${Object.keys(ramps).length} ramps, ${Object.keys(MOVES).length} moves -> data/fx.lua`);
