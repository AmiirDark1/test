const express = require('express');
const path = require('path');
const { Rcon } = require('rcon-client');
const fs = require('fs');
const os = require('os');

const app = express();
const PORT = process.env.SERVER_PORT || 3000;
const RCON_HOST = process.env.RCON_HOST || 'minecraft';
const RCON_PORT = parseInt(process.env.RCON_PORT || '25575');
const RCON_PASSWORD = process.env.RCON_PASSWORD || 'minecraft';
const DATA_PATH = process.env.DATA_PATH || path.join(__dirname, '..', 'data');
const SERVER_DATA_PATH = process.env.DATA_PATH || path.join(__dirname, '..', 'data');
const SERVER_CONFIG_PATH = process.env.SERVER_CONFIG_PATH || path.join(__dirname, 'server-config.json');

app.use(express.json({ limit: '1mb' }));
app.use(express.static(path.join(__dirname, 'public')));

// --- RCON Helper ---
async function withRcon(fn) {
  const rcon = new Rcon({
    host: RCON_HOST,
    port: RCON_PORT,
    password: RCON_PASSWORD,
    timeout: 5000,
  });
  try {
    await rcon.connect();
    return await fn(rcon);
  } finally {
    try { await rcon.end(); } catch (e) { /* ignore */ }
  }
}

// Helper to parse player list from /list
function parsePlayerList(raw) {
  const result = { online: 0, max: 0, players: [] };
  if (!raw) return result;
  const match = raw.match(/There are (\d+) of a max of (\d+) players online:\s*(.*)/i);
  if (match) {
    result.online = parseInt(match[1]) || 0;
    result.max = parseInt(match[2]) || 0;
    const playersStr = match[3].trim();
    if (playersStr && playersStr !== '') {
      result.players = playersStr.split(',').map(p => p.trim()).filter(p => p);
    }
  }
  return result;
}

// Parse NBT data for Inventory
function parseInventory(raw) {
  if (!raw) return { items: [], error: 'No data' };
  const dataMatch = raw.match(/has the following entity data:\s*(.+)/);
  if (!dataMatch) return { items: [], error: 'Could not parse' };
  let nbtStr = dataMatch[1].trim();
  
  try {
    nbtStr = nbtStr.replace(/(\d+)b/g, '$1');
    nbtStr = nbtStr.replace(/([\d.]+)f/g, '$1');
    nbtStr = nbtStr.replace(/([\d.]+)d/g, '$1');
    nbtStr = nbtStr.replace(/\[I;([^\]]+)\]/g, '[$1]');
    nbtStr = nbtStr.replace(/\[L;([^\]]+)\]/g, '[$1]');
    
    const items = JSON.parse(nbtStr);
    if (!Array.isArray(items)) return { items: [], error: 'Not an array' };
    
    const mapped = items.map((item, idx) => ({
      slot: item.Slot !== undefined ? item.Slot : idx,
      id: item.id || item.Id || 'unknown',
      count: item.Count || item.count || 1,
      damage: item.Damage || 0,
    }));
    
    mapped.sort((a, b) => a.slot - b.slot);
    
    return { items: mapped, total: mapped.length };
  } catch (e) {
    return parseInventoryManual(nbtStr);
  }
}

function parseInventoryManual(nbtStr) {
  try {
    const items = [];
    const itemRegex = /\{(.*?)\}/g;
    let match;
    while ((match = itemRegex.exec(nbtStr)) !== null) {
      const itemStr = match[1];
      const idMatch = itemStr.match(/id:"([^"]+)"/);
      const countMatch = itemStr.match(/Count:(\d+)/);
      const slotMatch = itemStr.match(/Slot:(\d+)/);
      if (idMatch) {
        items.push({
          slot: slotMatch ? parseInt(slotMatch[1]) : items.length,
          id: idMatch[1],
          count: countMatch ? parseInt(countMatch[1]) : 1,
        });
      }
    }
    items.sort((a, b) => a.slot - b.slot);
    return { items, total: items.length };
  } catch (e) {
    return { items: [], error: e.message };
  }
}

// Parse position data
function parsePosition(raw) {
  if (!raw) return null;
  const dataMatch = raw.match(/has the following entity data:\s*(.+)/);
  if (!dataMatch) return null;
  let posStr = dataMatch[1].trim();
  try {
    posStr = posStr.replace(/([\d.]+)d/g, '$1');
    posStr = posStr.replace(/([\d.]+)f/g, '$1');
    const pos = JSON.parse(posStr);
    if (Array.isArray(pos) && pos.length >= 3) {
      return { x: Math.round(pos[0] * 10) / 10, y: Math.round(pos[1] * 10) / 10, z: Math.round(pos[2] * 10) / 10 };
    }
    return null;
  } catch (e) {
    return null;
  }
}

// Parse health data
function parseHealth(raw) {
  if (!raw) return null;
  const dataMatch = raw.match(/has the following entity data:\s*(.+)/);
  if (!dataMatch) return null;
  let val = dataMatch[1].trim();
  val = val.replace(/[fd]/g, '');
  const num = parseFloat(val);
  return isNaN(num) ? null : Math.round(num * 10) / 10;
}

// ======================= SYSTEM RESOURCES =======================
function getSystemResources() {
  const resources = {
    memory: { usage: 0, limit: 0, percent: 0 },
    cpu: { cores: 0, usage: 0, percent: 0 },
    node: { memory: 0, uptime: 0 },
    container: { memory: 0, limit: 0 },
    hostname: os.hostname(),
    platform: os.platform(),
    arch: os.arch(),
  };

  // Node process memory
  const memUsage = process.memoryUsage();
  resources.node.memory = Math.round(memUsage.rss / 1024 / 1024 * 100) / 100;
  resources.node.uptime = Math.floor(process.uptime());

  // Read container cgroup memory (cgroup v2)
  try {
    const cgroupMem = fs.readFileSync('/sys/fs/cgroup/memory.current', 'utf8').trim();
    resources.container.memory = Math.round(parseInt(cgroupMem) / 1024 / 1024 * 100) / 100;
  } catch (e) {
    // try cgroup v1
    try {
      const cgroupMem = fs.readFileSync('/sys/fs/cgroup/memory/memory.usage_in_bytes', 'utf8').trim();
      resources.container.memory = Math.round(parseInt(cgroupMem) / 1024 / 1024 * 100) / 100;
    } catch (e2) { /* ignore */ }
  }

  try {
    const memLimit = fs.readFileSync('/sys/fs/cgroup/memory.max', 'utf8').trim();
    if (memLimit !== 'max') {
      resources.container.limit = Math.round(parseInt(memLimit) / 1024 / 1024 * 100) / 100;
    }
  } catch (e) {
    try {
      const memLimit = fs.readFileSync('/sys/fs/cgroup/memory/memory.limit_in_bytes', 'utf8').trim();
      resources.container.limit = Math.round(parseInt(memLimit) / 1024 / 1024 * 100) / 100;
    } catch (e2) { /* ignore */ }
  }

  if (resources.container.limit > 0 && resources.container.memory > 0) {
    resources.memory.usage = resources.container.memory;
    resources.memory.limit = resources.container.limit;
    resources.memory.percent = Math.round(resources.container.memory / resources.container.limit * 10000) / 100;
  } else if (resources.container.memory > 0) {
    resources.memory.usage = resources.container.memory;
    resources.memory.limit = resources.container.limit;
  }

  // CPU info - read /proc/stat
  try {
    const cpuStat = fs.readFileSync('/proc/stat', 'utf8');
    const lines = cpuStat.split('\n');
    const cpuLine = lines.find(l => l.startsWith('cpu '));
    if (cpuLine) {
      const parts = cpuLine.trim().split(/\s+/).slice(1).map(Number);
      const total = parts.reduce((a, b) => a + b, 0);
      const idle = parts[3] || 0;
      resources.cpu.usage = total - idle;
      resources.cpu.total = total;
    }
    resources.cpu.cores = os.cpus().length;
    // Calculate percentage based on delta (will be calculated on client or use as snapshot)
    resources.cpu.percent = Math.round((1 - (idle || 0) / (total || 1)) * 10000) / 100;
  } catch (e) { /* ignore */ }

  return resources;
}

// Read banned-players.json for ban details
function readBanDetails() {
  try {
    // Try multiple possible paths
    const paths = [
      path.join(DATA_PATH, 'banned-players.json'),
      path.join(DATA_PATH, 'banned-players.json'),
      path.join(__dirname, '..', 'data', 'banned-players.json'),
      '/data/banned-players.json',
    ];
    
    for (const p of paths) {
      try {
        if (fs.existsSync(p)) {
          const content = fs.readFileSync(p, 'utf8');
          const data = JSON.parse(content);
          if (Array.isArray(data)) {
            return {
              total: data.length,
              bans: data.map(b => ({
                name: b.name || b.username || 'Unknown',
                reason: b.reason || b.cause || 'No reason',
                created: b.created || b.ban_start || null,
                source: b.source || b.operator || 'Unknown',
                expires: b.expires || null,
              })).sort((a, b) => {
                // Sort by most recent first
                if (a.created && b.created) return new Date(b.created) - new Date(a.created);
                return 0;
              })
            };
          }
          return { total: 0, bans: [], note: 'Unexpected format' };
        }
      } catch (e) { /* try next path */ }
    }
    return { total: 0, bans: [], note: 'File not found in any path' };
  } catch (e) {
    return { total: 0, bans: [], error: e.message };
  }
}

// ======================= ITEMS DATABASE =======================
const ITEMS_DATABASE = {
  "building": {
    name: "🧱 مصالح ساختمانی",
    icon: "🧱",
    items: [
      { id: "minecraft:stone", name: "Stone" },
      { id: "minecraft:granite", name: "Granite" },
      { id: "minecraft:diorite", name: "Diorite" },
      { id: "minecraft:andesite", name: "Andesite" },
      { id: "minecraft:dirt", name: "Dirt" },
      { id: "minecraft:grass_block", name: "Grass Block" },
      { id: "minecraft:cobblestone", name: "Cobblestone" },
      { id: "minecraft:oak_planks", name: "Oak Planks" },
      { id: "minecraft:spruce_planks", name: "Spruce Planks" },
      { id: "minecraft:birch_planks", name: "Birch Planks" },
      { id: "minecraft:jungle_planks", name: "Jungle Planks" },
      { id: "minecraft:acacia_planks", name: "Acacia Planks" },
      { id: "minecraft:dark_oak_planks", name: "Dark Oak Planks" },
      { id: "minecraft:mangrove_planks", name: "Mangrove Planks" },
      { id: "minecraft:cherry_planks", name: "Cherry Planks" },
      { id: "minecraft:bamboo_planks", name: "Bamboo Planks" },
      { id: "minecraft:oak_log", name: "Oak Log" },
      { id: "minecraft:spruce_log", name: "Spruce Log" },
      { id: "minecraft:birch_log", name: "Birch Log" },
      { id: "minecraft:jungle_log", name: "Jungle Log" },
      { id: "minecraft:acacia_log", name: "Acacia Log" },
      { id: "minecraft:dark_oak_log", name: "Dark Oak Log" },
      { id: "minecraft:mangrove_log", name: "Mangrove Log" },
      { id: "minecraft:cherry_log", name: "Cherry Log" },
      { id: "minecraft:bamboo_block", name: "Bamboo Block" },
      { id: "minecraft:stripped_oak_log", name: "Stripped Oak Log" },
      { id: "minecraft:stripped_spruce_log", name: "Stripped Spruce Log" },
      { id: "minecraft:stripped_birch_log", name: "Stripped Birch Log" },
      { id: "minecraft:stripped_jungle_log", name: "Stripped Jungle Log" },
      { id: "minecraft:stripped_acacia_log", name: "Stripped Acacia Log" },
      { id: "minecraft:stripped_dark_oak_log", name: "Stripped Dark Oak Log" },
      { id: "minecraft:stripped_mangrove_log", name: "Stripped Mangrove Log" },
      { id: "minecraft:stripped_cherry_log", name: "Stripped Cherry Log" },
      { id: "minecraft:oak_wood", name: "Oak Wood" },
      { id: "minecraft:spruce_wood", name: "Spruce Wood" },
      { id: "minecraft:birch_wood", name: "Birch Wood" },
      { id: "minecraft:jungle_wood", name: "Jungle Wood" },
      { id: "minecraft:acacia_wood", name: "Acacia Wood" },
      { id: "minecraft:dark_oak_wood", name: "Dark Oak Wood" },
      { id: "minecraft:mangrove_wood", name: "Mangrove Wood" },
      { id: "minecraft:cherry_wood", name: "Cherry Wood" },
      { id: "minecraft:glass", name: "Glass" },
      { id: "minecraft:sandstone", name: "Sandstone" },
      { id: "minecraft:bricks", name: "Bricks" },
      { id: "minecraft:stone_bricks", name: "Stone Bricks" },
      { id: "minecraft:mossy_stone_bricks", name: "Mossy Stone Bricks" },
      { id: "minecraft:deepslate", name: "Deepslate" },
      { id: "minecraft:cobbled_deepslate", name: "Cobbled Deepslate" },
      { id: "minecraft:polished_deepslate", name: "Polished Deepslate" },
      { id: "minecraft:deepslate_bricks", name: "Deepslate Bricks" },
      { id: "minecraft:deepslate_tiles", name: "Deepslate Tiles" },
      { id: "minecraft:tuff", name: "Tuff" },
      { id: "minecraft:calcite", name: "Calcite" },
      { id: "minecraft:white_wool", name: "White Wool" },
      { id: "minecraft:terracotta", name: "Terracotta" },
      { id: "minecraft:white_concrete", name: "White Concrete" },
      { id: "minecraft:white_glass", name: "White Glass" },
      { id: "minecraft:prismarine", name: "Prismarine" },
      { id: "minecraft:obsidian", name: "Obsidian" },
      { id: "minecraft:crying_obsidian", name: "Crying Obsidian" },
      { id: "minecraft:netherrack", name: "Netherrack" },
      { id: "minecraft:nether_bricks", name: "Nether Bricks" },
      { id: "minecraft:blackstone", name: "Blackstone" },
      { id: "minecraft:polished_blackstone", name: "Polished Blackstone" },
      { id: "minecraft:end_stone", name: "End Stone" },
      { id: "minecraft:purpur_block", name: "Purpur Block" },
      { id: "minecraft:smooth_stone", name: "Smooth Stone" },
      { id: "minecraft:sponge", name: "Sponge" },
      { id: "minecraft:mud", name: "Mud" },
      { id: "minecraft:mud_bricks", name: "Mud Bricks" },
      { id: "minecraft:packed_mud", name: "Packed Mud" },
    ]
  },
  "decoration": {
    name: "🎨 تزئینی",
    icon: "🎨",
    items: [
      { id: "minecraft:oak_stairs", name: "Oak Stairs" },
      { id: "minecraft:spruce_stairs", name: "Spruce Stairs" },
      { id: "minecraft:birch_stairs", name: "Birch Stairs" },
      { id: "minecraft:jungle_stairs", name: "Jungle Stairs" },
      { id: "minecraft:acacia_stairs", name: "Acacia Stairs" },
      { id: "minecraft:dark_oak_stairs", name: "Dark Oak Stairs" },
      { id: "minecraft:mangrove_stairs", name: "Mangrove Stairs" },
      { id: "minecraft:cherry_stairs", name: "Cherry Stairs" },
      { id: "minecraft:bamboo_stairs", name: "Bamboo Stairs" },
      { id: "minecraft:cobblestone_stairs", name: "Cobblestone Stairs" },
      { id: "minecraft:stone_brick_stairs", name: "Stone Brick Stairs" },
      { id: "minecraft:oak_slab", name: "Oak Slab" },
      { id: "minecraft:spruce_slab", name: "Spruce Slab" },
      { id: "minecraft:birch_slab", name: "Birch Slab" },
      { id: "minecraft:jungle_slab", name: "Jungle Slab" },
      { id: "minecraft:acacia_slab", name: "Acacia Slab" },
      { id: "minecraft:dark_oak_slab", name: "Dark Oak Slab" },
      { id: "minecraft:mangrove_slab", name: "Mangrove Slab" },
      { id: "minecraft:cherry_slab", name: "Cherry Slab" },
      { id: "minecraft:bamboo_slab", name: "Bamboo Slab" },
      { id: "minecraft:stone_slab", name: "Stone Slab" },
      { id: "minecraft:cobblestone_slab", name: "Cobblestone Slab" },
      { id: "minecraft:stone_brick_slab", name: "Stone Brick Slab" },
      { id: "minecraft:oak_fence", name: "Oak Fence" },
      { id: "minecraft:spruce_fence", name: "Spruce Fence" },
      { id: "minecraft:birch_fence", name: "Birch Fence" },
      { id: "minecraft:jungle_fence", name: "Jungle Fence" },
      { id: "minecraft:acacia_fence", name: "Acacia Fence" },
      { id: "minecraft:dark_oak_fence", name: "Dark Oak Fence" },
      { id: "minecraft:mangrove_fence", name: "Mangrove Fence" },
      { id: "minecraft:cherry_fence", name: "Cherry Fence" },
      { id: "minecraft:bamboo_fence", name: "Bamboo Fence" },
      { id: "minecraft:oak_fence_gate", name: "Oak Fence Gate" },
      { id: "minecraft:spruce_fence_gate", name: "Spruce Fence Gate" },
      { id: "minecraft:birch_fence_gate", name: "Birch Fence Gate" },
      { id: "minecraft:jungle_fence_gate", name: "Jungle Fence Gate" },
      { id: "minecraft:acacia_fence_gate", name: "Acacia Fence Gate" },
      { id: "minecraft:dark_oak_fence_gate", name: "Dark Oak Fence Gate" },
      { id: "minecraft:mangrove_fence_gate", name: "Mangrove Fence Gate" },
      { id: "minecraft:cherry_fence_gate", name: "Cherry Fence Gate" },
      { id: "minecraft:bamboo_fence_gate", name: "Bamboo Fence Gate" },
      { id: "minecraft:oak_door", name: "Oak Door" },
      { id: "minecraft:spruce_door", name: "Spruce Door" },
      { id: "minecraft:birch_door", name: "Birch Door" },
      { id: "minecraft:jungle_door", name: "Jungle Door" },
      { id: "minecraft:acacia_door", name: "Acacia Door" },
      { id: "minecraft:dark_oak_door", name: "Dark Oak Door" },
      { id: "minecraft:mangrove_door", name: "Mangrove Door" },
      { id: "minecraft:cherry_door", name: "Cherry Door" },
      { id: "minecraft:bamboo_door", name: "Bamboo Door" },
      { id: "minecraft:iron_door", name: "Iron Door" },
      { id: "minecraft:oak_trapdoor", name: "Oak Trapdoor" },
      { id: "minecraft:spruce_trapdoor", name: "Spruce Trapdoor" },
      { id: "minecraft:birch_trapdoor", name: "Birch Trapdoor" },
      { id: "minecraft:jungle_trapdoor", name: "Jungle Trapdoor" },
      { id: "minecraft:acacia_trapdoor", name: "Acacia Trapdoor" },
      { id: "minecraft:dark_oak_trapdoor", name: "Dark Oak Trapdoor" },
      { id: "minecraft:mangrove_trapdoor", name: "Mangrove Trapdoor" },
      { id: "minecraft:cherry_trapdoor", name: "Cherry Trapdoor" },
      { id: "minecraft:bamboo_trapdoor", name: "Bamboo Trapdoor" },
      { id: "minecraft:iron_trapdoor", name: "Iron Trapdoor" },
      { id: "minecraft:painting", name: "Painting" },
      { id: "minecraft:item_frame", name: "Item Frame" },
      { id: "minecraft:flower_pot", name: "Flower Pot" },
      { id: "minecraft:torch", name: "Torch" },
      { id: "minecraft:lantern", name: "Lantern" },
      { id: "minecraft:soul_lantern", name: "Soul Lantern" },
      { id: "minecraft:sea_lantern", name: "Sea Lantern" },
      { id: "minecraft:ladder", name: "Ladder" },
      { id: "minecraft:vines", name: "Vines" },
      { id: "minecraft:bookshelf", name: "Bookshelf" },
      { id: "minecraft:chest", name: "Chest" },
      { id: "minecraft:ender_chest", name: "Ender Chest" },
      { id: "minecraft:bed", name: "Bed" },
      { id: "minecraft:crafting_table", name: "Crafting Table" },
      { id: "minecraft:enchanting_table", name: "Enchanting Table" },
      { id: "minecraft:anvil", name: "Anvil" },
      { id: "minecraft:grindstone", name: "Grindstone" },
      { id: "minecraft:loom", name: "Loom" },
      { id: "minecraft:stonecutter", name: "Stonecutter" },
      { id: "minecraft:cartography_table", name: "Cartography Table" },
      { id: "minecraft:fletching_table", name: "Fletching Table" },
      { id: "minecraft:smithing_table", name: "Smithing Table" },
      { id: "minecraft:blast_furnace", name: "Blast Furnace" },
      { id: "minecraft:smoker", name: "Smoker" },
      { id: "minecraft:bell", name: "Bell" },
      { id: "minecraft:campfire", name: "Campfire" },
      { id: "minecraft:soul_campfire", name: "Soul Campfire" },
      { id: "minecraft:candle", name: "Candle" },
      { id: "minecraft:lectern", name: "Lectern" },
      { id: "minecraft:composter", name: "Composter" },
      { id: "minecraft:barrel", name: "Barrel" },
    ]
  },
  "redstone": {
    name: "🔴 ردستون",
    icon: "🔴",
    items: [
      { id: "minecraft:redstone", name: "Redstone" },
      { id: "minecraft:redstone_block", name: "Redstone Block" },
      { id: "minecraft:redstone_torch", name: "Redstone Torch" },
      { id: "minecraft:repeater", name: "Repeater" },
      { id: "minecraft:comparator", name: "Comparator" },
      { id: "minecraft:observer", name: "Observer" },
      { id: "minecraft:piston", name: "Piston" },
      { id: "minecraft:sticky_piston", name: "Sticky Piston" },
      { id: "minecraft:slime_block", name: "Slime Block" },
      { id: "minecraft:honey_block", name: "Honey Block" },
      { id: "minecraft:lever", name: "Lever" },
      { id: "minecraft:stone_button", name: "Stone Button" },
      { id: "minecraft:oak_button", name: "Oak Button" },
      { id: "minecraft:spruce_button", name: "Spruce Button" },
      { id: "minecraft:birch_button", name: "Birch Button" },
      { id: "minecraft:jungle_button", name: "Jungle Button" },
      { id: "minecraft:acacia_button", name: "Acacia Button" },
      { id: "minecraft:dark_oak_button", name: "Dark Oak Button" },
      { id: "minecraft:mangrove_button", name: "Mangrove Button" },
      { id: "minecraft:cherry_button", name: "Cherry Button" },
      { id: "minecraft:bamboo_button", name: "Bamboo Button" },
      { id: "minecraft:stone_pressure_plate", name: "Stone Pressure Plate" },
      { id: "minecraft:oak_pressure_plate", name: "Oak Pressure Plate" },
      { id: "minecraft:spruce_pressure_plate", name: "Spruce Pressure Plate" },
      { id: "minecraft:birch_pressure_plate", name: "Birch Pressure Plate" },
      { id: "minecraft:jungle_pressure_plate", name: "Jungle Pressure Plate" },
      { id: "minecraft:acacia_pressure_plate", name: "Acacia Pressure Plate" },
      { id: "minecraft:dark_oak_pressure_plate", name: "Dark Oak Pressure Plate" },
      { id: "minecraft:mangrove_pressure_plate", name: "Mangrove Pressure Plate" },
      { id: "minecraft:cherry_pressure_plate", name: "Cherry Pressure Plate" },
      { id: "minecraft:bamboo_pressure_plate", name: "Bamboo Pressure Plate" },
      { id: "minecraft:light_weighted_pressure_plate", name: "Light Weighted Pressure Plate" },
      { id: "minecraft:heavy_weighted_pressure_plate", name: "Heavy Weighted Pressure Plate" },
      { id: "minecraft:tripwire_hook", name: "Tripwire Hook" },
      { id: "minecraft:dispenser", name: "Dispenser" },
      { id: "minecraft:dropper", name: "Dropper" },
      { id: "minecraft:hopper", name: "Hopper" },
      { id: "minecraft:target", name: "Target Block" },
      { id: "minecraft:daylight_detector", name: "Daylight Detector" },
      { id: "minecraft:note_block", name: "Note Block" },
      { id: "minecraft:jukebox", name: "Jukebox" },
      { id: "minecraft:sculk_sensor", name: "Sculk Sensor" },
      { id: "minecraft:calibrated_sculk_sensor", name: "Calibrated Sculk Sensor" },
      { id: "minecraft:sculk_shrieker", name: "Sculk Shrieker" },
      { id: "minecraft:trapped_chest", name: "Trapped Chest" },
      { id: "minecraft:rail", name: "Rail" },
      { id: "minecraft:powered_rail", name: "Powered Rail" },
      { id: "minecraft:detector_rail", name: "Detector Rail" },
      { id: "minecraft:activator_rail", name: "Activator Rail" },
      { id: "minecraft:minecart", name: "Minecart" },
      { id: "minecraft:chest_minecart", name: "Chest Minecart" },
      { id: "minecraft:tnt_minecart", name: "TNT Minecart" },
      { id: "minecraft:hopper_minecart", name: "Hopper Minecart" },
    ]
  },
  "tools": {
    name: "🛠️ ابزارها",
    icon: "🛠️",
    items: [
      { id: "minecraft:wooden_axe", name: "Wooden Axe" },
      { id: "minecraft:stone_axe", name: "Stone Axe" },
      { id: "minecraft:iron_axe", name: "Iron Axe" },
      { id: "minecraft:golden_axe", name: "Golden Axe" },
      { id: "minecraft:diamond_axe", name: "Diamond Axe" },
      { id: "minecraft:netherite_axe", name: "Netherite Axe" },
      { id: "minecraft:wooden_pickaxe", name: "Wooden Pickaxe" },
      { id: "minecraft:stone_pickaxe", name: "Stone Pickaxe" },
      { id: "minecraft:iron_pickaxe", name: "Iron Pickaxe" },
      { id: "minecraft:golden_pickaxe", name: "Golden Pickaxe" },
      { id: "minecraft:diamond_pickaxe", name: "Diamond Pickaxe" },
      { id: "minecraft:netherite_pickaxe", name: "Netherite Pickaxe" },
      { id: "minecraft:wooden_shovel", name: "Wooden Shovel" },
      { id: "minecraft:stone_shovel", name: "Stone Shovel" },
      { id: "minecraft:iron_shovel", name: "Iron Shovel" },
      { id: "minecraft:golden_shovel", name: "Golden Shovel" },
      { id: "minecraft:diamond_shovel", name: "Diamond Shovel" },
      { id: "minecraft:netherite_shovel", name: "Netherite Shovel" },
      { id: "minecraft:wooden_hoe", name: "Wooden Hoe" },
      { id: "minecraft:stone_hoe", name: "Stone Hoe" },
      { id: "minecraft:iron_hoe", name: "Iron Hoe" },
      { id: "minecraft:golden_hoe", name: "Golden Hoe" },
      { id: "minecraft:diamond_hoe", name: "Diamond Hoe" },
      { id: "minecraft:netherite_hoe", name: "Netherite Hoe" },
      { id: "minecraft:fishing_rod", name: "Fishing Rod" },
      { id: "minecraft:shears", name: "Shears" },
      { id: "minecraft:flint_and_steel", name: "Flint and Steel" },
      { id: "minecraft:compass", name: "Compass" },
      { id: "minecraft:recovery_compass", name: "Recovery Compass" },
      { id: "minecraft:clock", name: "Clock" },
      { id: "minecraft:spyglass", name: "Spyglass" },
      { id: "minecraft:brush", name: "Brush" },
      { id: "minecraft:lead", name: "Lead" },
      { id: "minecraft:name_tag", name: "Name Tag" },
      { id: "minecraft:bucket", name: "Bucket" },
      { id: "minecraft:water_bucket", name: "Water Bucket" },
      { id: "minecraft:lava_bucket", name: "Lava Bucket" },
      { id: "minecraft:milk_bucket", name: "Milk Bucket" },
      { id: "minecraft:powder_snow_bucket", name: "Powder Snow Bucket" },
      { id: "minecraft:bone_meal", name: "Bone Meal" },
      { id: "minecraft:shears", name: "Shears" },
    ]
  },
  "combat": {
    name: "⚔️ جنگی",
    icon: "⚔️",
    items: [
      { id: "minecraft:wooden_sword", name: "Wooden Sword" },
      { id: "minecraft:stone_sword", name: "Stone Sword" },
      { id: "minecraft:iron_sword", name: "Iron Sword" },
      { id: "minecraft:golden_sword", name: "Golden Sword" },
      { id: "minecraft:diamond_sword", name: "Diamond Sword" },
      { id: "minecraft:netherite_sword", name: "Netherite Sword" },
      { id: "minecraft:bow", name: "Bow" },
      { id: "minecraft:crossbow", name: "Crossbow" },
      { id: "minecraft:arrow", name: "Arrow" },
      { id: "minecraft:spectral_arrow", name: "Spectral Arrow" },
      { id: "minecraft:trident", name: "Trident" },
      { id: "minecraft:shield", name: "Shield" },
      { id: "minecraft:leather_helmet", name: "Leather Helmet" },
      { id: "minecraft:leather_chestplate", name: "Leather Chestplate" },
      { id: "minecraft:leather_leggings", name: "Leather Leggings" },
      { id: "minecraft:leather_boots", name: "Leather Boots" },
      { id: "minecraft:chainmail_helmet", name: "Chainmail Helmet" },
      { id: "minecraft:chainmail_chestplate", name: "Chainmail Chestplate" },
      { id: "minecraft:chainmail_leggings", name: "Chainmail Leggings" },
      { id: "minecraft:chainmail_boots", name: "Chainmail Boots" },
      { id: "minecraft:iron_helmet", name: "Iron Helmet" },
      { id: "minecraft:iron_chestplate", name: "Iron Chestplate" },
      { id: "minecraft:iron_leggings", name: "Iron Leggings" },
      { id: "minecraft:iron_boots", name: "Iron Boots" },
      { id: "minecraft:diamond_helmet", name: "Diamond Helmet" },
      { id: "minecraft:diamond_chestplate", name: "Diamond Chestplate" },
      { id: "minecraft:diamond_leggings", name: "Diamond Leggings" },
      { id: "minecraft:diamond_boots", name: "Diamond Boots" },
      { id: "minecraft:netherite_helmet", name: "Netherite Helmet" },
      { id: "minecraft:netherite_chestplate", name: "Netherite Chestplate" },
      { id: "minecraft:netherite_leggings", name: "Netherite Leggings" },
      { id: "minecraft:netherite_boots", name: "Netherite Boots" },
      { id: "minecraft:turtle_helmet", name: "Turtle Helmet" },
      { id: "minecraft:elytra", name: "Elytra" },
      { id: "minecraft:totem_of_undying", name: "Totem of Undying" },
      { id: "minecraft:end_crystal", name: "End Crystal" },
      { id: "minecraft:wind_charge", name: "Wind Charge" },
      { id: "minecraft:mace", name: "Mace" },
    ]
  },
  "food": {
    name: "🍔 غذا",
    icon: "🍔",
    items: [
      { id: "minecraft:apple", name: "Apple" },
      { id: "minecraft:golden_apple", name: "Golden Apple" },
      { id: "minecraft:enchanted_golden_apple", name: "Enchanted Golden Apple" },
      { id: "minecraft:bread", name: "Bread" },
      { id: "minecraft:porkchop", name: "Raw Porkchop" },
      { id: "minecraft:cooked_porkchop", name: "Cooked Porkchop" },
      { id: "minecraft:beef", name: "Raw Beef" },
      { id: "minecraft:cooked_beef", name: "Steak" },
      { id: "minecraft:chicken", name: "Raw Chicken" },
      { id: "minecraft:cooked_chicken", name: "Cooked Chicken" },
      { id: "minecraft:cod", name: "Raw Cod" },
      { id: "minecraft:cooked_cod", name: "Cooked Cod" },
      { id: "minecraft:salmon", name: "Raw Salmon" },
      { id: "minecraft:cooked_salmon", name: "Cooked Salmon" },
      { id: "minecraft:tropical_fish", name: "Tropical Fish" },
      { id: "minecraft:potato", name: "Potato" },
      { id: "minecraft:baked_potato", name: "Baked Potato" },
      { id: "minecraft:carrot", name: "Carrot" },
      { id: "minecraft:golden_carrot", name: "Golden Carrot" },
      { id: "minecraft:pumpkin_pie", name: "Pumpkin Pie" },
      { id: "minecraft:cake", name: "Cake" },
      { id: "minecraft:cookie", name: "Cookie" },
      { id: "minecraft:melon_slice", name: "Melon Slice" },
      { id: "minecraft:sweet_berries", name: "Sweet Berries" },
      { id: "minecraft:glow_berries", name: "Glow Berries" },
      { id: "minecraft:mushroom_stew", name: "Mushroom Stew" },
      { id: "minecraft:beetroot", name: "Beetroot" },
      { id: "minecraft:beetroot_soup", name: "Beetroot Soup" },
      { id: "minecraft:rabbit_stew", name: "Rabbit Stew" },
      { id: "minecraft:suspicious_stew", name: "Suspicious Stew" },
      { id: "minecraft:honey_bottle", name: "Honey Bottle" },
      { id: "minecraft:chorus_fruit", name: "Chorus Fruit" },
      { id: "minecraft:dried_kelp", name: "Dried Kelp" },
      { id: "minecraft:rotten_flesh", name: "Rotten Flesh" },
      { id: "minecraft:spider_eye", name: "Spider Eye" },
      { id: "minecraft:poisonous_potato", name: "Poisonous Potato" },
    ]
  },
  "materials": {
    name: "💎 مواد اولیه",
    icon: "💎",
    items: [
      { id: "minecraft:coal", name: "Coal" },
      { id: "minecraft:charcoal", name: "Charcoal" },
      { id: "minecraft:iron_ingot", name: "Iron Ingot" },
      { id: "minecraft:gold_ingot", name: "Gold Ingot" },
      { id: "minecraft:copper_ingot", name: "Copper Ingot" },
      { id: "minecraft:diamond", name: "Diamond" },
      { id: "minecraft:emerald", name: "Emerald" },
      { id: "minecraft:netherite_scrap", name: "Netherite Scrap" },
      { id: "minecraft:netherite_ingot", name: "Netherite Ingot" },
      { id: "minecraft:lapis_lazuli", name: "Lapis Lazuli" },
      { id: "minecraft:redstone", name: "Redstone" },
      { id: "minecraft:amethyst_shard", name: "Amethyst Shard" },
      { id: "minecraft:quartz", name: "Nether Quartz" },
      { id: "minecraft:iron_nugget", name: "Iron Nugget" },
      { id: "minecraft:gold_nugget", name: "Gold Nugget" },
      { id: "minecraft:stick", name: "Stick" },
      { id: "minecraft:string", name: "String" },
      { id: "minecraft:feather", name: "Feather" },
      { id: "minecraft:leather", name: "Leather" },
      { id: "minecraft:rabbit_hide", name: "Rabbit Hide" },
      { id: "minecraft:wool", name: "Wool" },
      { id: "minecraft:paper", name: "Paper" },
      { id: "minecraft:book", name: "Book" },
      { id: "minecraft:slime_ball", name: "Slimeball" },
      { id: "minecraft:clay_ball", name: "Clay Ball" },
      { id: "minecraft:brick", name: "Brick" },
      { id: "minecraft:flint", name: "Flint" },
      { id: "minecraft:gunpowder", name: "Gunpowder" },
      { id: "minecraft:blaze_rod", name: "Blaze Rod" },
      { id: "minecraft:blaze_powder", name: "Blaze Powder" },
      { id: "minecraft:ghast_tear", name: "Ghast Tear" },
      { id: "minecraft:ender_pearl", name: "Ender Pearl" },
      { id: "minecraft:ender_eye", name: "Ender Eye" },
      { id: "minecraft:experience_bottle", name: "Bottle o' Enchanting" },
      { id: "minecraft:shulker_shell", name: "Shulker Shell" },
      { id: "minecraft:nautilus_shell", name: "Nautilus Shell" },
      { id: "minecraft:heart_of_the_sea", name: "Heart of the Sea" },
      { id: "minecraft:echo_shard", name: "Echo Shard" },
      { id: "minecraft:disc_fragment_5", name: "Disc Fragment (5)" },
      { id: "minecraft:honeycomb", name: "Honeycomb" },
      { id: "minecraft:copper_ingot", name: "Copper Ingot" },
    ]
  },
  "brewing": {
    name: "🧪 معجون‌سازی",
    icon: "🧪",
    items: [
      { id: "minecraft:glass_bottle", name: "Glass Bottle" },
      { id: "minecraft:brewing_stand", name: "Brewing Stand" },
      { id: "minecraft:cauldron", name: "Cauldron" },
      { id: "minecraft:nether_wart", name: "Nether Wart" },
      { id: "minecraft:glowstone_dust", name: "Glowstone Dust" },
      { id: "minecraft:redstone", name: "Redstone (extended)" },
      { id: "minecraft:fermented_spider_eye", name: "Fermented Spider Eye" },
      { id: "minecraft:gunpowder", name: "Gunpowder (splash)" },
      { id: "minecraft:dragon_breath", name: "Dragon's Breath" },
      { id: "minecraft:sugar", name: "Sugar" },
      { id: "minecraft:rabbit_foot", name: "Rabbit's Foot" },
      { id: "minecraft:blaze_powder", name: "Blaze Powder" },
      { id: "minecraft:magma_cream", name: "Magma Cream" },
      { id: "minecraft:glistering_melon_slice", name: "Glistering Melon Slice" },
      { id: "minecraft:golden_carrot", name: "Golden Carrot" },
      { id: "minecraft:pufferfish", name: "Pufferfish" },
      { id: "minecraft:turtle_helmet", name: "Turtle Shell" },
      { id: "minecraft:phantom_membrane", name: "Phantom Membrane" },
    ]
  },
  "nature": {
    name: "🌿 طبیعت",
    icon: "🌿",
    items: [
      { id: "minecraft:oak_sapling", name: "Oak Sapling" },
      { id: "minecraft:spruce_sapling", name: "Spruce Sapling" },
      { id: "minecraft:birch_sapling", name: "Birch Sapling" },
      { id: "minecraft:jungle_sapling", name: "Jungle Sapling" },
      { id: "minecraft:acacia_sapling", name: "Acacia Sapling" },
      { id: "minecraft:dark_oak_sapling", name: "Dark Oak Sapling" },
      { id: "minecraft:mangrove_propagule", name: "Mangrove Propagule" },
      { id: "minecraft:cherry_sapling", name: "Cherry Sapling" },
      { id: "minecraft:wheat_seeds", name: "Wheat Seeds" },
      { id: "minecraft:wheat", name: "Wheat" },
      { id: "minecraft:sugar_cane", name: "Sugar Cane" },
      { id: "minecraft:bamboo", name: "Bamboo" },
      { id: "minecraft:cactus", name: "Cactus" },
      { id: "minecraft:kelp", name: "Kelp" },
      { id: "minecraft:sea_pickle", name: "Sea Pickle" },
      { id: "minecraft:lily_pad", name: "Lily Pad" },
      { id: "minecraft:vine", name: "Vines" },
      { id: "minecraft:weeping_vines", name: "Weeping Vines" },
      { id: "minecraft:twisting_vines", name: "Twisting Vines" },
      { id: "minecraft:cocoa_beans", name: "Cocoa Beans" },
      { id: "minecraft:egg", name: "Egg" },
      { id: "minecraft:bone", name: "Bone" },
      { id: "minecraft:ink_sac", name: "Ink Sac" },
      { id: "minecraft:glow_ink_sac", name: "Glow Ink Sac" },
      { id: "minecraft:feather", name: "Feather" },
      { id: "minecraft:leather", name: "Leather" },
      { id: "minecraft:rabbit_foot", name: "Rabbit Foot" },
      { id: "minecraft:scute", name: "Scute" },
      { id: "minecraft:armadillo_scute", name: "Armadillo Scute" },
      { id: "minecraft:bone_meal", name: "Bone Meal" },
      { id: "minecraft:allium", name: "Allium" },
      { id: "minecraft:azure_bluet", name: "Azure Bluet" },
      { id: "minecraft:blue_orchid", name: "Blue Orchid" },
      { id: "minecraft:cornflower", name: "Cornflower" },
      { id: "minecraft:dandelion", name: "Dandelion" },
      { id: "minecraft:lilac", name: "Lilac" },
      { id: "minecraft:lily_of_the_valley", name: "Lily of the Valley" },
      { id: "minecraft:orange_tulip", name: "Orange Tulip" },
      { id: "minecraft:oxeye_daisy", name: "Oxeye Daisy" },
      { id: "minecraft:peony", name: "Peony" },
      { id: "minecraft:pink_tulip", name: "Pink Tulip" },
      { id: "minecraft:poppy", name: "Poppy" },
      { id: "minecraft:red_tulip", name: "Red Tulip" },
      { id: "minecraft:rose_bush", name: "Rose Bush" },
      { id: "minecraft:sunflower", name: "Sunflower" },
      { id: "minecraft:white_tulip", name: "White Tulip" },
      { id: "minecraft:wither_rose", name: "Wither Rose" },
      { id: "minecraft:torchflower", name: "Torchflower" },
      { id: "minecraft:pitcher_plant", name: "Pitcher Plant" },
      { id: "minecraft:spore_blossom", name: "Spore Blossom" },
    ]
  },
  "ores": {
    name: "⛏️ سنگ معدن",
    icon: "⛏️",
    items: [
      { id: "minecraft:coal_ore", name: "Coal Ore" },
      { id: "minecraft:deepslate_coal_ore", name: "Deepslate Coal Ore" },
      { id: "minecraft:iron_ore", name: "Iron Ore" },
      { id: "minecraft:deepslate_iron_ore", name: "Deepslate Iron Ore" },
      { id: "minecraft:copper_ore", name: "Copper Ore" },
      { id: "minecraft:deepslate_copper_ore", name: "Deepslate Copper Ore" },
      { id: "minecraft:gold_ore", name: "Gold Ore" },
      { id: "minecraft:deepslate_gold_ore", name: "Deepslate Gold Ore" },
      { id: "minecraft:redstone_ore", name: "Redstone Ore" },
      { id: "minecraft:deepslate_redstone_ore", name: "Deepslate Redstone Ore" },
      { id: "minecraft:lapis_ore", name: "Lapis Lazuli Ore" },
      { id: "minecraft:deepslate_lapis_ore", name: "Deepslate Lapis Ore" },
      { id: "minecraft:diamond_ore", name: "Diamond Ore" },
      { id: "minecraft:deepslate_diamond_ore", name: "Deepslate Diamond Ore" },
      { id: "minecraft:emerald_ore", name: "Emerald Ore" },
      { id: "minecraft:deepslate_emerald_ore", name: "Deepslate Emerald Ore" },
      { id: "minecraft:nether_gold_ore", name: "Nether Gold Ore" },
      { id: "minecraft:nether_quartz_ore", name: "Nether Quartz Ore" },
      { id: "minecraft:ancient_debris", name: "Ancient Debris" },
      { id: "minecraft:raw_iron", name: "Raw Iron" },
      { id: "minecraft:raw_gold", name: "Raw Gold" },
      { id: "minecraft:raw_copper", name: "Raw Copper" },
      { id: "minecraft:raw_iron_block", name: "Block of Raw Iron" },
      { id: "minecraft:raw_gold_block", name: "Block of Raw Gold" },
      { id: "minecraft:raw_copper_block", name: "Block of Raw Copper" },
      { id: "minecraft:coal_block", name: "Block of Coal" },
      { id: "minecraft:iron_block", name: "Block of Iron" },
      { id: "minecraft:gold_block", name: "Block of Gold" },
      { id: "minecraft:diamond_block", name: "Block of Diamond" },
      { id: "minecraft:emerald_block", name: "Block of Emerald" },
      { id: "minecraft:netherite_block", name: "Block of Netherite" },
      { id: "minecraft:lapis_block", name: "Block of Lapis" },
      { id: "minecraft:copper_block", name: "Block of Copper" },
      { id: "minecraft:waxed_copper_block", name: "Waxed Copper Block" },
    ]
  },
  "misc": {
    name: "🔮 متفرقه",
    icon: "🔮",
    items: [
      { id: "minecraft:tnt", name: "TNT" },
      { id: "minecraft:firework_rocket", name: "Firework Rocket" },
      { id: "minecraft:firework_star", name: "Firework Star" },
      { id: "minecraft:fire_charge", name: "Fire Charge" },
      { id: "minecraft:ender_pearl", name: "Ender Pearl" },
      { id: "minecraft:ender_eye", name: "Ender Eye" },
      { id: "minecraft:empty_map", name: "Empty Map" },
      { id: "minecraft:filled_map", name: "Filled Map" },
      { id: "minecraft:explorer_map", name: "Explorer Map" },
      { id: "minecraft:goat_horn", name: "Goat Horn" },
      { id: "minecraft:music_disc_13", name: "Music Disc (13)" },
      { id: "minecraft:music_disc_cat", name: "Music Disc (Cat)" },
      { id: "minecraft:music_disc_blocks", name: "Music Disc (Blocks)" },
      { id: "minecraft:music_disc_chirp", name: "Music Disc (Chirp)" },
      { id: "minecraft:music_disc_far", name: "Music Disc (Far)" },
      { id: "minecraft:music_disc_mall", name: "Music Disc (Mall)" },
      { id: "minecraft:music_disc_mellohi", name: "Music Disc (Mellohi)" },
      { id: "minecraft:music_disc_stal", name: "Music Disc (Stal)" },
      { id: "minecraft:music_disc_strad", name: "Music Disc (Strad)" },
      { id: "minecraft:music_disc_ward", name: "Music Disc (Ward)" },
      { id: "minecraft:music_disc_11", name: "Music Disc (11)" },
      { id: "minecraft:music_disc_wait", name: "Music Disc (Wait)" },
      { id: "minecraft:music_disc_otherside", name: "Music Disc (Otherside)" },
      { id: "minecraft:music_disc_5", name: "Music Disc (5)" },
      { id: "minecraft:music_disc_relic", name: "Music Disc (Relic)" },
      { id: "minecraft:music_disc_creator", name: "Music Disc (Creator)" },
      { id: "minecraft:saddle", name: "Saddle" },
      { id: "minecraft:carrot_on_a_stick", name: "Carrot on a Stick" },
      { id: "minecraft:warped_fungus_on_a_stick", name: "Warped Fungus on a Stick" },
      { id: "minecraft:armor_stand", name: "Armor Stand" },
      { id: "minecraft:ominous_bottle", name: "Ominous Bottle" },
      { id: "minecraft:trial_key", name: "Trial Key" },
      { id: "minecraft:ominous_trial_key", name: "Ominous Trial Key" },
      { id: "minecraft:heavy_core", name: "Heavy Core" },
    ]
  },
  "potions": {
    name: "🧪 معجون‌ها",
    icon: "🧪",
    items: [
      { id: "minecraft:potion", name: "Potion (base)" },
      { id: "minecraft:splash_potion", name: "Splash Potion" },
      { id: "minecraft:lingering_potion", name: "Lingering Potion" },
      { id: "minecraft:potion{Potion:\"minecraft:healing\"}", name: "Potion of Healing" },
      { id: "minecraft:potion{Potion:\"minecraft:regeneration\"}", name: "Potion of Regeneration" },
      { id: "minecraft:potion{Potion:\"minecraft:strength\"}", name: "Potion of Strength" },
      { id: "minecraft:potion{Potion:\"minecraft:swiftness\"}", name: "Potion of Swiftness" },
      { id: "minecraft:potion{Potion:\"minecraft:fire_resistance\"}", name: "Potion of Fire Resistance" },
      { id: "minecraft:potion{Potion:\"minecraft:water_breathing\"}", name: "Potion of Water Breathing" },
      { id: "minecraft:potion{Potion:\"minecraft:night_vision\"}", name: "Potion of Night Vision" },
      { id: "minecraft:potion{Potion:\"minecraft:invisibility\"}", name: "Potion of Invisibility" },
      { id: "minecraft:potion{Potion:\"minecraft:poison\"}", name: "Potion of Poison" },
      { id: "minecraft:potion{Potion:\"minecraft:weakness\"}", name: "Potion of Weakness" },
      { id: "minecraft:potion{Potion:\"minecraft:slowness\"}", name: "Potion of Slowness" },
      { id: "minecraft:potion{Potion:\"minecraft:leaping\"}", name: "Potion of Leaping" },
      { id: "minecraft:potion{Potion:\"minecraft:turtle_master\"}", name: "Potion of Turtle Master" },
      { id: "minecraft:potion{Potion:\"minecraft:slow_falling\"}", name: "Potion of Slow Falling" },
    ]
  },
  "enchanted_books": {
    name: "📚 کتاب‌های افسون",
    icon: "📚",
    items: [
      { id: "minecraft:enchanted_book{StoredEnchantments:[{id:\"minecraft:sharpness\",lvl:5}]}", name: "Sharpness V" },
      { id: "minecraft:enchanted_book{StoredEnchantments:[{id:\"minecraft:protection\",lvl:4}]}", name: "Protection IV" },
      { id: "minecraft:enchanted_book{StoredEnchantments:[{id:\"minecraft:fortune\",lvl:3}]}", name: "Fortune III" },
      { id: "minecraft:enchanted_book{StoredEnchantments:[{id:\"minecraft:efficiency\",lvl:5}]}", name: "Efficiency V" },
      { id: "minecraft:enchanted_book{StoredEnchantments:[{id:\"minecraft:unbreaking\",lvl:3}]}", name: "Unbreaking III" },
      { id: "minecraft:enchanted_book{StoredEnchantments:[{id:\"minecraft:mending\",lvl:1}]}", name: "Mending" },
      { id: "minecraft:enchanted_book{StoredEnchantments:[{id:\"minecraft:power\",lvl:5}]}", name: "Power V" },
      { id: "minecraft:enchanted_book{StoredEnchantments:[{id:\"minecraft:looting\",lvl:3}]}", name: "Looting III" },
      { id: "minecraft:enchanted_book{StoredEnchantments:[{id:\"minecraft:silk_touch\",lvl:1}]}", name: "Silk Touch" },
      { id: "minecraft:enchanted_book{StoredEnchantments:[{id:\"minecraft:fire_aspect\",lvl:2}]}", name: "Fire Aspect II" },
      { id: "minecraft:enchanted_book{StoredEnchantments:[{id:\"minecraft:depth_strider\",lvl:3}]}", name: "Depth Strider III" },
      { id: "minecraft:enchanted_book{StoredEnchantments:[{id:\"minecraft:feather_falling\",lvl:4}]}", name: "Feather Falling IV" },
    ]
  }
};

// ======================= API ROUTES =======================

// --- Get items database ---
app.get('/api/items', (req, res) => {
  res.json({ success: true, categories: Object.keys(ITEMS_DATABASE), items: ITEMS_DATABASE });
});

// --- Get item icon helper ---
app.get('/api/items/search', (req, res) => {
  const { q } = req.query;
  if (!q || q.length < 2) return res.json({ success: false, error: 'Search query too short' });
  const query = q.toLowerCase();
  const results = [];
  for (const [catKey, category] of Object.entries(ITEMS_DATABASE)) {
    for (const item of category.items) {
      if (item.name.toLowerCase().includes(query) || item.id.toLowerCase().includes(query)) {
        results.push({ ...item, category: catKey, categoryName: category.name });
      }
    }
  }
  res.json({ success: true, results: results.slice(0, 50) });
});

// --- Server Status ---
app.get('/api/status', async (req, res) => {
  try {
    const data = await withRcon(async (rcon) => {
      const listRaw = await rcon.send('list');
      const tpsRaw = await rcon.send('tps');
      const memoryRaw = await rcon.send('memory');
      const uptimeRaw = await rcon.send('uptime');

      const parsed = parsePlayerList(listRaw);
      return {
        playersOnline: parsed.online,
        maxPlayers: parsed.max,
        players: parsed.players,
        listRaw,
        tpsRaw,
        memoryRaw,
        uptimeRaw
      };
    });
    res.json({ success: true, ...data });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- System Resources (CPU/RAM from container) ---
app.get('/api/system', (req, res) => {
  try {
    const resources = getSystemResources();
    res.json({ success: true, ...resources });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Ban details from banned-players.json ---
app.get('/api/banlist/details', (req, res) => {
  try {
    const details = readBanDetails();
    res.json({ success: true, ...details });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- All Players (online list) ---
app.get('/api/players', async (req, res) => {
  try {
    const data = await withRcon(async (rcon) => {
      const raw = await rcon.send('list');
      return parsePlayerList(raw);
    });
    res.json({ success: true, ...data });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Detailed player info with inventory, position, health ---
app.get('/api/players/detailed', async (req, res) => {
  try {
    const data = await withRcon(async (rcon) => {
      const listRaw = await rcon.send('list');
      const parsed = parsePlayerList(listRaw);
      
      // Get details for each online player
      const playerDetails = [];
      for (const player of parsed.players) {
        try {
          const [posRaw, healthRaw, foodRaw, gmRaw] = await Promise.all([
            rcon.send(`data get entity ${player} Pos`).catch(() => null),
            rcon.send(`data get entity ${player} Health`).catch(() => null),
            rcon.send(`data get entity ${player} foodLevel`).catch(() => null),
            rcon.send(`data get entity ${player} playerGameType`).catch(() => null),
          ]);
          
          const pos = parsePosition(posRaw);
          const health = parseHealth(healthRaw);
          const food = parseHealth(foodRaw);
          const gamemode = gmRaw ? (gmRaw.includes('creative') ? 'creative' : 
                                    gmRaw.includes('adventure') ? 'adventure' : 
                                    gmRaw.includes('spectator') ? 'spectator' : 'survival') : 'unknown';
          
          playerDetails.push({
            name: player,
            position: pos,
            health: health,
            food: food,
            gamemode: gamemode,
          });
        } catch (e) {
          playerDetails.push({ name: player, error: e.message });
        }
      }
      
      return {
        online: parsed.online,
        max: parsed.max,
        players: playerDetails,
      };
    });
    res.json({ success: true, ...data });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Get full player info ---
app.get('/api/player/:name', async (req, res) => {
  const { name } = req.params;
  try {
    const data = await withRcon(async (rcon) => {
      const seed = await rcon.send(`seed`);
      const listRaw = await rcon.send('list');
      const allPlayers = parsePlayerList(listRaw);
      const isOnline = allPlayers.players.includes(name);
      
      let position = null, health = null, food = null, gamemode = null;
      if (isOnline) {
        const [posRaw, healthRaw, foodRaw, gmRaw] = await Promise.all([
          rcon.send(`data get entity ${name} Pos`).catch(() => null),
          rcon.send(`data get entity ${name} Health`).catch(() => null),
          rcon.send(`data get entity ${name} foodLevel`).catch(() => null),
          rcon.send(`data get entity ${name} playerGameType`).catch(() => null),
        ]);
        position = parsePosition(posRaw);
        health = parseHealth(healthRaw);
        food = parseHealth(foodRaw);
        gamemode = gmRaw ? (gmRaw.includes('creative') ? 'creative' : 
                            gmRaw.includes('adventure') ? 'adventure' : 
                            gmRaw.includes('spectator') ? 'spectator' : 'survival') : 'unknown';
      }
      
      return { name, isOnline, totalOnline: allPlayers.online, seed, position, health, food, gamemode };
    });
    res.json({ success: true, ...data });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Player Inventory ---
app.get('/api/player/:name/inventory', async (req, res) => {
  const { name } = req.params;
  try {
    const raw = await withRcon(async (rcon) => {
      const rawData = await rcon.send(`data get entity ${name} Inventory`);
      return rawData;
    });
    const parsed = parseInventory(raw);
    res.json({ success: true, player: name, ...parsed, raw });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Player Position ---
app.get('/api/player/:name/position', async (req, res) => {
  const { name } = req.params;
  try {
    const raw = await withRcon(async (rcon) => {
      return await rcon.send(`data get entity ${name} Pos`);
    });
    const position = parsePosition(raw);
    res.json({ success: true, player: name, position, raw });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Player Health ---
app.get('/api/player/:name/health', async (req, res) => {
  const { name } = req.params;
  try {
    const raw = await withRcon(async (rcon) => {
      return await rcon.send(`data get entity ${name} Health`);
    });
    const health = parseHealth(raw);
    res.json({ success: true, player: name, health, raw });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Player XP ---
app.get('/api/player/:name/xp', async (req, res) => {
  const { name } = req.params;
  try {
    const raw = await withRcon(async (rcon) => {
      const xpRaw = await rcon.send(`data get entity ${name} XpLevel`);
      const xpTotal = await rcon.send(`data get entity ${name} XpTotal`);
      return { xpLevel: xpRaw, xpTotal: xpTotal };
    });
    const level = parseHealth(raw.xpLevel);
    const total = parseHealth(raw.xpTotal);
    res.json({ success: true, player: name, level, total, raw });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// ===== EXISTING ROUTES (unchanged functionality) =====

// --- Whitelist ---
app.get('/api/whitelist', async (req, res) => {
  try {
    const raw = await withRcon((rcon) => rcon.send('whitelist list'));
    res.json({ success: true, ...parseWhitelist(raw), raw });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

function parseWhitelist(raw) {
  const result = { total: 0, players: [] };
  if (!raw) return result;
  const match = raw.match(/There are (\d+) whitelisted players:\s*(.*)/i);
  if (match) {
    result.total = parseInt(match[1]) || 0;
    const playersStr = match[2].trim();
    if (playersStr && playersStr !== '') {
      result.players = playersStr.split(',').map(p => p.trim()).filter(p => p);
    }
  }
  return result;
}

// Whitelist on/off
app.post('/api/whitelist/toggle', async (req, res) => {
  const { enable } = req.body;
  const cmd = enable ? 'whitelist on' : 'whitelist off';
  try {
    const result = await withRcon((rcon) => rcon.send(cmd));
    res.json({ success: true, message: result, enabled: !!enable });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// Add to whitelist
app.post('/api/whitelist/add', async (req, res) => {
  const { player } = req.body;
  if (!player) return res.json({ success: false, error: 'Player name is required' });
  try {
    const result = await withRcon((rcon) => rcon.send(`whitelist add ${player}`));
    res.json({ success: true, message: result });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// Remove from whitelist
app.post('/api/whitelist/remove', async (req, res) => {
  const { player } = req.body;
  if (!player) return res.json({ success: false, error: 'Player name is required' });
  try {
    const result = await withRcon((rcon) => rcon.send(`whitelist remove ${player}`));
    res.json({ success: true, message: result });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Banlist ---
app.get('/api/banlist', async (req, res) => {
  try {
    const raw = await withRcon((rcon) => rcon.send('banlist'));
    res.json({ success: true, ...parseBanlist(raw), raw });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

function parseBanlist(raw) {
  const result = { total: 0, players: [] };
  if (!raw) return result;
  
  // Try to extract total from "There are X banned players:"
  const totalMatch = raw.match(/There are (\d+) banned players/i);
  if (totalMatch) {
    result.total = parseInt(totalMatch[1]) || 0;
  }
  
  // Handle modern Paper format with "- " prefix on each line:
  // There are 1 banned players:
  // - PlayerName
  const dashLines = raw.match(/^-\s+(.+)$/gm);
  if (dashLines && dashLines.length > 0) {
    result.players = dashLines.map(line => line.replace(/^-\s+/, '').trim()).filter(p => p);
    if (result.total === 0) result.total = result.players.length;
    return result;
  }
  
  // Handle old comma-separated format:
  // There are 2 banned players: player1, player2
  const match = raw.match(/There are (\d+) banned players:\s*(.*)/i);
  if (match) {
    result.total = parseInt(match[1]) || 0;
    const playersStr = match[2].trim();
    if (playersStr && playersStr !== '') {
      result.players = playersStr.split(',').map(p => p.trim()).filter(p => p);
    }
  }
  return result;
}

// Ban player
app.post('/api/ban', async (req, res) => {
  const { player, reason } = req.body;
  if (!player) return res.json({ success: false, error: 'Player name is required' });
  const cmd = reason ? `ban ${player} ${reason}` : `ban ${player}`;
  try {
    const result = await withRcon((rcon) => rcon.send(cmd));
    res.json({ success: true, message: result });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// Ban IP
app.post('/api/ban-ip', async (req, res) => {
  const { ip, reason } = req.body;
  if (!ip) return res.json({ success: false, error: 'IP is required' });
  const cmd = reason ? `ban-ip ${ip} ${reason}` : `ban-ip ${ip}`;
  try {
    const result = await withRcon((rcon) => rcon.send(cmd));
    res.json({ success: true, message: result });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// IP Banlist
app.get('/api/banlist-ips', async (req, res) => {
  try {
    const raw = await withRcon((rcon) => rcon.send('banlist ips'));
    const match = raw.match(/There are (\d+) banned IP addresses:\s*(.*)/i);
    const total = match ? parseInt(match[1]) || 0 : 0;
    const ips = match && match[2] ? match[2].split(',').map(i => i.trim()).filter(i => i) : [];
    res.json({ success: true, total, ips, raw });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// Pardon (unban)
app.post('/api/pardon', async (req, res) => {
  const { player } = req.body;
  if (!player) return res.json({ success: false, error: 'Player name is required' });
  try {
    const result = await withRcon((rcon) => rcon.send(`pardon ${player}`));
    res.json({ success: true, message: result });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// Pardon IP
app.post('/api/pardon-ip', async (req, res) => {
  const { ip } = req.body;
  if (!ip) return res.json({ success: false, error: 'IP is required' });
  try {
    const result = await withRcon((rcon) => rcon.send(`pardon-ip ${ip}`));
    res.json({ success: true, message: result });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- OPs ---
app.get('/api/oplist', async (req, res) => {
  try {
    const raw = await withRcon((rcon) => rcon.send('op list'));
    const match = raw.match(/Operators \((\d+)\):\s*(.*)/i);
    const total = match ? parseInt(match[1]) || 0 : 0;
    const operators = match && match[2] ? match[2].split(',').map(o => {
      const parts = o.trim().split(/\s+/);
      return parts[0];
    }).filter(o => o) : [];
    res.json({ success: true, total, operators, raw });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// Op player
app.post('/api/op', async (req, res) => {
  const { player } = req.body;
  if (!player) return res.json({ success: false, error: 'Player name is required' });
  try {
    const result = await withRcon((rcon) => rcon.send(`op ${player}`));
    res.json({ success: true, message: result });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// Deop player
app.post('/api/deop', async (req, res) => {
  const { player } = req.body;
  if (!player) return res.json({ success: false, error: 'Player name is required' });
  try {
    const result = await withRcon((rcon) => rcon.send(`deop ${player}`));
    res.json({ success: true, message: result });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Kick ---
app.post('/api/kick', async (req, res) => {
  const { player, reason } = req.body;
  if (!player) return res.json({ success: false, error: 'Player name is required' });
  const cmd = reason ? `kick ${player} ${reason}` : `kick ${player}`;
  try {
    const result = await withRcon((rcon) => rcon.send(cmd));
    res.json({ success: true, message: result });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Send command ---
app.post('/api/command', async (req, res) => {
  const { command } = req.body;
  if (!command) return res.json({ success: false, error: 'Command is required' });
  try {
    const result = await withRcon((rcon) => rcon.send(command));
    res.json({ success: true, message: result });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Server Settings ---
app.get('/api/settings', async (req, res) => {
  try {
    const data = await withRcon(async (rcon) => {
      const [difficulty, gameMode] = await Promise.all([
        rcon.send('difficulty'),
        rcon.send('defaultgamemode'),
      ]);
      return { difficulty, gameMode };
    });
    res.json({ success: true, ...data });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// Change difficulty
app.post('/api/difficulty', async (req, res) => {
  const { difficulty } = req.body;
  const valid = ['peaceful', 'easy', 'normal', 'hard'];
  if (!valid.includes(difficulty)) return res.json({ success: false, error: 'Invalid difficulty. Use: peaceful, easy, normal, hard' });
  try {
    const result = await withRcon((rcon) => rcon.send(`difficulty ${difficulty}`));
    res.json({ success: true, message: result });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// Change gamemode
app.post('/api/gamemode', async (req, res) => {
  const { player, gamemode } = req.body;
  if (!player || !gamemode) return res.json({ success: false, error: 'Player and gamemode are required' });
  const valid = ['survival', 'creative', 'adventure', 'spectator'];
  if (!valid.includes(gamemode)) return res.json({ success: false, error: 'Invalid gamemode' });
  try {
    const result = await withRcon((rcon) => rcon.send(`gamemode ${gamemode} ${player}`));
    res.json({ success: true, message: result });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// Set world spawn
app.post('/api/setworldspawn', async (req, res) => {
  try {
    const result = await withRcon((rcon) => rcon.send('setworldspawn'));
    res.json({ success: true, message: result });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// Time commands
app.post('/api/time', async (req, res) => {
  const { time } = req.body;
  if (!time) return res.json({ success: false, error: 'Time is required (day, night, noon, midnight, or number)' });
  const valid = ['day', 'night', 'noon', 'midnight'];
  const cmd = valid.includes(time) ? `time set ${time}` : `time set ${parseInt(time)}`;
  try {
    const result = await withRcon((rcon) => rcon.send(cmd));
    res.json({ success: true, message: result });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// Weather commands
app.post('/api/weather', async (req, res) => {
  const { weather } = req.body;
  if (!['clear', 'rain', 'thunder'].includes(weather)) return res.json({ success: false, error: 'Use: clear, rain, thunder' });
  try {
    const result = await withRcon((rcon) => rcon.send(`weather ${weather}`));
    res.json({ success: true, message: result });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// Save-all
app.post('/api/save-all', async (req, res) => {
  try {
    const result = await withRcon((rcon) => rcon.send('save-all'));
    res.json({ success: true, message: result });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// Restart the server (soft)
app.post('/api/restart', async (req, res) => {
  try {
    await withRcon((rcon) => rcon.send('say §c§lServer is restarting in 5 seconds...'));
    setTimeout(async () => {
      try {
        await withRcon((rcon) => rcon.send('stop'));
      } catch (e) { /* ignore */ }
    }, 5000);
    res.json({ success: true, message: 'Server is restarting...' });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Server TPS & Performance ---
app.get('/api/tps', async (req, res) => {
  try {
    const raw = await withRcon((rcon) => rcon.send('tps'));
    const lines = raw.split('\n').filter(l => l.trim());
    const tpsData = lines.map(line => {
      const match = line.match(/§\w\w+.*?§\w([\d.]+|\d+)\/.*?§\w([\d.]+|\d+)/);
      if (match) return { world: 'overworld', tps: parseFloat(match[1]), mspt: parseFloat(match[2]) };
      const simpleMatch = line.match(/(\w+)\s*#\s*(\d+)\s*§\w+([\d.]+)\s*\/\s*§\w+([\d.]+)/);
      if (simpleMatch) return { world: simpleMatch[1], tps: parseFloat(simpleMatch[3]), mspt: parseFloat(simpleMatch[4]) };
      const basicMatch = line.match(/([\d.]+)\/([\d.]+)/);
      if (basicMatch) return { world: 'overworld', tps: parseFloat(basicMatch[1]), mspt: parseFloat(basicMatch[2]) };
      return null;
    }).filter(Boolean);
    res.json({ success: true, tps: tpsData, raw });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Server Info ---
app.get('/api/version', async (req, res) => {
  try {
    const raw = await withRcon((rcon) => rcon.send('version'));
    res.json({ success: true, version: raw });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Seed ---
app.get('/api/seed', async (req, res) => {
  try {
    const raw = await withRcon((rcon) => rcon.send('seed'));
    res.json({ success: true, seed: raw });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Say / Broadcast ---
app.post('/api/say', async (req, res) => {
  const { message } = req.body;
  if (!message) return res.json({ success: false, error: 'Message is required' });
  try {
    const result = await withRcon((rcon) => rcon.send(`say ${message}`));
    res.json({ success: true, message: result });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Title ---
app.post('/api/title', async (req, res) => {
  const { title, subtitle = '' } = req.body;
  if (!title) return res.json({ success: false, error: 'Title is required' });
  try {
    await withRcon(async (rcon) => {
      await rcon.send(`title @a title {"text":"${title}","bold":true,"color":"gold"}`);
      if (subtitle) await rcon.send(`title @a subtitle {"text":"${subtitle}","color":"gray"}`);
    });
    res.json({ success: true, message: 'Title sent to all players' });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Give item to player ---
app.post('/api/give', async (req, res) => {
  const { player, item, amount = 1 } = req.body;
  if (!player || !item) return res.json({ success: false, error: 'Player and item are required' });
  try {
    const result = await withRcon((rcon) => rcon.send(`give ${player} ${item} ${amount}`));
    res.json({ success: true, message: result });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Teleport ---
app.post('/api/tp', async (req, res) => {
  const { target, x, y, z } = req.body;
  if (!target) return res.json({ success: false, error: 'Target is required' });
  let cmd;
  if (x !== undefined && y !== undefined && z !== undefined) {
    cmd = `tp ${target} ${x} ${y} ${z}`;
  } else {
    return res.json({ success: false, error: 'Coordinates (x, y, z) are required' });
  }
  try {
    const result = await withRcon((rcon) => rcon.send(cmd));
    res.json({ success: true, message: result });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Clear inventory ---
app.post('/api/clear', async (req, res) => {
  const { player } = req.body;
  if (!player) return res.json({ success: false, error: 'Player is required' });
  try {
    const result = await withRcon((rcon) => rcon.send(`clear ${player}`));
    res.json({ success: true, message: result });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Kill entity ---
app.post('/api/kill', async (req, res) => {
  const { target } = req.body;
  if (!target) return res.json({ success: false, error: 'Target is required' });
  try {
    const result = await withRcon((rcon) => rcon.send(`kill ${target}`));
    res.json({ success: true, message: result });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Effect give/remove ---
app.post('/api/effect', async (req, res) => {
  const { player, effect, duration = 30, amplifier = 1 } = req.body;
  if (!player || !effect) return res.json({ success: false, error: 'Player and effect are required' });
  try {
    const result = await withRcon((rcon) => rcon.send(`effect give ${player} ${effect} ${duration} ${amplifier}`));
    res.json({ success: true, message: result });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Enchant ---
app.post('/api/enchant', async (req, res) => {
  const { player, enchantment, level = 1 } = req.body;
  if (!player || !enchantment) return res.json({ success: false, error: 'Player and enchantment are required' });
  try {
    const result = await withRcon((rcon) => rcon.send(`enchant ${player} ${enchantment} ${level}`));
    res.json({ success: true, message: result });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Experience give ---
app.post('/api/xp', async (req, res) => {
  const { player, amount = 1 } = req.body;
  if (!player) return res.json({ success: false, error: 'Player is required' });
  try {
    const result = await withRcon((rcon) => rcon.send(`xp add ${player} ${amount}`));
    res.json({ success: true, message: result });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Gamerule management ---
app.post('/api/gamerule', async (req, res) => {
  const { rule, value } = req.body;
  if (!rule || value === undefined) return res.json({ success: false, error: 'Rule and value are required' });
  try {
    const result = await withRcon((rcon) => rcon.send(`gamerule ${rule} ${value}`));
    res.json({ success: true, message: result });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// Get specific gamerule
app.get('/api/gamerule/:rule', async (req, res) => {
  const { rule } = req.params;
  try {
    const result = await withRcon((rcon) => rcon.send(`gamerule ${rule}`));
    res.json({ success: true, rule, value: result });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// Get all gamerules
app.get('/api/gamerules', async (req, res) => {
  try {
    const raw = await withRcon((rcon) => rcon.send('gamerule'));
    const lines = raw.split('\n').filter(l => l.trim());
    const rules = {};
    lines.forEach(line => {
      const match = line.match(/(\w+)\s*=\s*(.+)/);
      if (match) rules[match[1]] = match[2].trim();
    });
    res.json({ success: true, rules, raw });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Server Config (name, discord, description, icon) ---
app.get('/api/server-config', (req, res) => {
  try {
    const defaultConfig = {
      name: '🎮 Minecraft Server',
      description: 'خوش آمدید به سرور ماینکرفت ما!',
      discord: '',
      icon: '',
      motd: 'A Minecraft Server',
    };
    let config = { ...defaultConfig };
    if (fs.existsSync(SERVER_CONFIG_PATH)) {
      const saved = JSON.parse(fs.readFileSync(SERVER_CONFIG_PATH, 'utf8'));
      config = { ...defaultConfig, ...saved };
    }
    res.json({ success: true, config });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// Save server config
app.post('/api/server-config', async (req, res) => {
  try {
    const { name, description, discord, motd } = req.body;
    const config = {
      name: name || '🎮 Minecraft Server',
      description: description || '',
      discord: discord || '',
      motd: motd || 'A Minecraft Server',
      icon: '', // icon handled separately
    };
    // Preserve existing icon
    if (fs.existsSync(SERVER_CONFIG_PATH)) {
      const old = JSON.parse(fs.readFileSync(SERVER_CONFIG_PATH, 'utf8'));
      config.icon = old.icon || '';
    }
    fs.writeFileSync(SERVER_CONFIG_PATH, JSON.stringify(config, null, 2), 'utf8');
    res.json({ success: true, message: 'تنظیمات ذخیره شد', config });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// Upload server icon (base64)
app.post('/api/server-icon', async (req, res) => {
  try {
    const { icon } = req.body;
    if (!icon) return res.json({ success: false, error: 'No icon data' });
    
    let config = { icon: '' };
    if (fs.existsSync(SERVER_CONFIG_PATH)) {
      config = JSON.parse(fs.readFileSync(SERVER_CONFIG_PATH, 'utf8'));
    }
    config.icon = icon;
    fs.writeFileSync(SERVER_CONFIG_PATH, JSON.stringify(config, null, 2), 'utf8');
    res.json({ success: true, message: 'آیکون ذخیره شد' });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Scoreboard ---
app.get('/api/scoreboard', async (req, res) => {
  try {
    const raw = await withRcon((rcon) => rcon.send('scoreboard objectives list'));
    res.json({ success: true, scoreboard: raw });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Dashboard ---
app.get('/api/dashboard', async (req, res) => {
  try {
    const data = await withRcon(async (rcon) => {
      const [listRaw, tpsRaw, versionRaw, difficultyRaw, banlistRaw, oplistRaw] = await Promise.all([
        rcon.send('list'),
        rcon.send('tps'),
        rcon.send('version'),
        rcon.send('difficulty'),
        rcon.send('banlist'),
        rcon.send('op list'),
      ]);

      const players = parsePlayerList(listRaw);
      const bans = parseBanlist(banlistRaw);

      const opMatch = oplistRaw.match(/Operators \((\d+)\)/i);
      const opCount = opMatch ? parseInt(opMatch[1]) || 0 : 0;

      return {
        playersOnline: players.online,
        maxPlayers: players.max,
        players: players.players,
        tps: tpsRaw,
        version: versionRaw,
        difficulty: difficultyRaw,
        bans: bans.total,
        ops: opCount,
      };
    });
    res.json({ success: true, ...data });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- Console log stream endpoint ---
app.get('/api/console', async (req, res) => {
  try {
    const raw = await withRcon((rcon) => rcon.send('list'));
    res.json({ success: true, log: `[${new Date().toISOString()}] Server status: ${raw}` });
  } catch (err) {
    res.json({ success: false, error: err.message });
  }
});

// --- RCON Connection Test ---
app.get('/api/test', async (req, res) => {
  try {
    const result = await withRcon(async (rcon) => {
      const ping = await rcon.send('list');
      return { connected: true, ping: ping.substring(0, 100) };
    });
    res.json({ success: true, ...result });
  } catch (err) {
    res.json({ success: false, connected: false, error: err.message });
  }
});

// --- Serve frontend ---
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// --- Start Server ---
app.listen(PORT, '0.0.0.0', () => {
  console.log(`✅ Minecraft Admin Panel running on http://0.0.0.0:${PORT}`);
  console.log(`   RCON: ${RCON_HOST}:${RCON_PORT}`);
  console.log(`   Data path: ${DATA_PATH}`);
});