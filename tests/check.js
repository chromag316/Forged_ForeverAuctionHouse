// Static check of the addon: every file in the .toc must parse as Lua 5.1
// (XML files must be well-formed), and every global a Lua file uses must be
// on the list below: a Lua built-in or a known WoW client API / Blizzard
// global. An unknown global is usually a typo or a missing `local`.
//
// Usage: node check.js   (exit code 1 on any problem)

const fs = require('fs');
const path = require('path');
const luaparse = require('luaparse');

const ROOT = path.resolve(__dirname, '..');

const LUA = `
  assert error getmetatable ipairs math next pairs pcall print rawget rawset
  select setmetatable string table tonumber tostring type unpack xpcall
  date time wipe _G
`;

// WoW client and Blizzard UI globals the addon uses. Add to this list when
// the addon starts using a new one.
const WOW = `
  AUCTION_HOUSE_REFRESH_BUTTON_TOOLTIP AuctionHouseFrame AuctionHouseFrameDisplayMode
  AuctionHouseTableCellBuyoutMixin AuctionHouseTableCellCommoditiesQuantityMixin
  AuctionHouseTableCellMinPriceMixin AuctionHouseTableCellMixin
  AuctionHouseTableCellUnitPriceMixin AuctionHouseUtil BreakUpLargeNumbers
  C_AddOns C_AuctionHouse C_Container C_Item C_MerchantFrame C_Timer
  CreateDataProvider CreateFrame CreateScrollBoxListLinearView Enum
  ForgedForeverAHPercentCellMixin ForgedForeverAuctionHouseDB
  GameTooltip GameTooltipMoneyFormat GameTooltipText GameTooltip_Hide
  GetMerchantItemInfo GetMerchantItemLink GetMerchantNumItems GetMoneyString
  GetNormalizedRealmName GetRealmName GetTime ITEM_QUALITY_COLORS ItemLocation
  LibStub MoneyFormatterUtil NUM_BAG_SLOTS NUM_TOTAL_EQUIPPED_BAG_SLOTS NineSliceUtil
  PanelTemplates_DeselectTab PanelTemplates_SelectTab PanelTemplates_SetNumTabs
  PanelTemplates_SetTab PanelTemplates_TabResize PlaySound REFRESH SELL_PRICE
  SLASH_FORGEDFOREVERAH1 SOUNDKIT ScrollBoxConstants ScrollBoxListMixin ScrollUtil
  SlashCmdList TooltipDataProcessor UnitFactionGroup geterrorhandler hooksecurefunc
  issecretvalue
`;

const known = new Set((LUA + WOW).split(/\s+/).filter(Boolean));

const toc = path.join(ROOT, 'Forged_ForeverAuctionHouse.toc');
const files = fs.readFileSync(toc, 'utf8').split(/\r?\n/)
  .map(l => l.trim()).filter(l => l && !l.startsWith('#'));

let problems = 0;
function problem(msg) { problems++; console.log('  ' + msg); }

for (const f of files) {
  const file = path.join(ROOT, f);
  if (!fs.existsSync(file)) { problem(`${f}: listed in the .toc but missing`); continue; }
  const src = fs.readFileSync(file, 'utf8');
  if (f.endsWith('.xml')) {
    // Well-formedness only: balanced tags, quoted attributes.
    const stack = [];
    const tag = /<(\/?)([A-Za-z_][\w:.-]*)((?:\s+[\w:.-]+\s*=\s*("[^"]*"|'[^']*'))*)\s*(\/?)>|<!--[\s\S]*?-->|<\?[\s\S]*?\?>/g;
    let m, ok = true;
    for (const stripped of [src.replace(tag, '')]) {
      if (/<|>/.test(stripped)) { problem(`${f}: malformed tag`); ok = false; }
    }
    tag.lastIndex = 0;
    while (ok && (m = tag.exec(src))) {
      if (!m[2]) continue; // comment / declaration
      if (m[1]) {
        if (stack.pop() !== m[2]) { problem(`${f}: mismatched </${m[2]}>`); ok = false; }
      } else if (!m[5]) stack.push(m[2]);
    }
    if (ok && stack.length) problem(`${f}: unclosed <${stack[stack.length - 1]}>`);
    continue;
  }
  let ast;
  try {
    ast = luaparse.parse(src, { luaVersion: '5.1', scope: true, locations: true });
  } catch (e) {
    problem(`${f}: syntax error: ${e.message}`);
    continue;
  }
  const walk = (n) => {
    if (!n || typeof n !== 'object') return;
    if (Array.isArray(n)) { n.forEach(walk); return; }
    if (n.type === 'Identifier' && n.isLocal === false && !known.has(n.name)) {
      problem(`${f}:${n.loc.start.line}: unknown global "${n.name}"`);
    }
    for (const k in n) if (k !== 'loc') walk(n[k]);
  };
  walk(ast.body);
}

console.log(problems === 0
  ? `check: ${files.length} files OK`
  : `check: ${problems} problem(s)`);
process.exitCode = problems === 0 ? 0 : 1;
