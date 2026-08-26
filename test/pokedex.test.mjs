import test from 'node:test';
import assert from 'node:assert/strict';
import { ENTRIES, resolve, lookup, normalize, setPool, clearPool, getPool, byPokemonId } from '../src/pokedex.mjs';

test.afterEach(() => clearPool());

test('圖鑑載入完整：涵蓋全國圖鑑，每筆都有繁中名與屬性', () => {
  assert.ok(ENTRIES.length > 1000, `只載入了 ${ENTRIES.length} 筆`);
  const species = new Set(ENTRIES.map((e) => e.speciesId));
  assert.ok(species.size >= 1025, `只有 ${species.size} 個物種`);
  for (const e of ENTRIES) {
    assert.ok(e.zh, `#${e.id} ${e.slug} 缺繁中名`);
    assert.ok(e.types.length >= 1 && e.types.length <= 2, `#${e.id} 屬性數量異常`);
  }
});

test('繁中名稱精確查詢', () => {
  const cases = [
    ['皮卡丘', ['electric']],
    ['噴火龍', ['fire', 'flying']],
    ['班基拉斯', ['rock', 'dark']],
    ['沙奈朵', ['psychic', 'fairy']],
    ['暴鯉龍', ['water', 'flying']],
    ['快龍', ['dragon', 'flying']],
    ['耿鬼', ['ghost', 'poison']],
    ['超夢', ['psychic']],
    ['夢幻', ['psychic']],
    ['多龍巴魯托', ['dragon', 'ghost']],
  ];
  for (const [name, types] of cases) {
    const hit = lookup(name);
    assert.ok(hit, `查不到 ${name}`);
    assert.equal(hit.exact, true, `${name} 應該是精確命中`);
    assert.deepEqual(hit.entry.types, types, name);
  }
});

test('英文與日文名稱也查得到', () => {
  assert.equal(lookup('Charizard').entry.zh, '噴火龍');
  assert.equal(lookup('tyranitar').entry.zh, '班基拉斯');
  assert.equal(lookup('ピカチュウ').entry.zh, '皮卡丘');
});

test('同一隻的裝飾性形態會被收斂，不會洗版查詢結果', () => {
  const hits = resolve('皮卡丘', { limit: 5 });
  assert.equal(hits.length, 1, `皮卡丘回傳了 ${hits.length} 筆`);
  assert.equal(hits[0].entry.isDefault, true);
});

test('屬性不同的形態會保留，因為剋制關係真的不一樣', () => {
  const hits = resolve('噴火龍', { limit: 5 });
  const combos = hits.map((h) => h.entry.types.join('/'));
  assert.ok(combos.includes('fire/flying'), '缺少原始形態');
  assert.ok(combos.includes('fire/dragon'), '缺少 Mega X（火/龍）');
  assert.equal(hits[0].entry.isDefault, true, '預設形態應該排第一');
});

test('地區形態有獨立名稱與屬性', () => {
  const alolan = lookup('雷丘（阿羅拉的樣子）');
  assert.ok(alolan);
  assert.deepEqual(alolan.entry.types, ['electric', 'psychic']);

  const galarian = resolve('大蔥鴨', { limit: 5 }).map((h) => h.entry.types.join('/'));
  assert.ok(galarian.includes('fighting'), '缺少伽勒爾大蔥鴨（格鬥）');
});

// OCR 的輸出從來不乾淨，這幾種雜訊是實測最常見的。
test('normalize 清掉 OCR 雜訊：等級、性別符號、全形空白、標點', () => {
  assert.equal(normalize('Lv.50 耿鬼 ♂'), '耿鬼');
  assert.equal(normalize('　噴火龍　'), '噴火龍');
  assert.equal(normalize('皮卡丘!!'), '皮卡丘');
  assert.equal(normalize('ＬＶ．１００ 快龍'), '快龍');
  assert.equal(normalize(''), '');
  assert.equal(normalize(null), '');
});

test('帶雜訊的 OCR 文字仍能精確命中', () => {
  assert.equal(lookup('Lv.50 耿鬼 ♂').entry.zh, '耿鬼');
  assert.equal(lookup('　班基拉斯 ').entry.zh, '班基拉斯');
});

test('單字錯誤（簡繁混用、形近字）能靠模糊比對救回來', () => {
  const cases = [
    ['大葱鴨', '大蔥鴨'],   // 葱／蔥
    ['噴火竜', '噴火龍'],   // 竜／龍
    ['班基拉期', '班基拉斯'],
  ];
  for (const [noisy, expected] of cases) {
    const hit = lookup(noisy, { minScore: 0.5 });
    assert.ok(hit, `${noisy} 完全查不到`);
    assert.equal(hit.entry.zh, expected, `${noisy} 應對應到 ${expected}`);
    assert.equal(hit.exact, false);
    assert.ok(hit.score < 1 && hit.score >= 0.5);
  }
});

test('完全不像名字的字串不會硬湊出結果', () => {
  assert.equal(lookup('對戰準備', { minScore: 0.6 }), null);
  assert.equal(lookup('剩餘時間', { minScore: 0.6 }), null);
  assert.equal(lookup('', { minScore: 0.6 }), null);
});

test('minScore 越嚴格，越不會回傳勉強的結果', () => {
  assert.ok(lookup('班基拉期', { minScore: 0.5 }));
  assert.equal(lookup('班基拉期', { minScore: 0.95 }), null);
});

// 規劃書的風險因應：縮小比對範圍以提高準確率。
test('賽季清單把比對範圍限制在清單內', () => {
  setPool(['皮卡丘', '噴火龍', '水箭龜'], 'test-season');
  assert.equal(getPool().name, 'test-season');
  assert.ok(lookup('皮卡丘'));
  assert.equal(lookup('班基拉斯', { minScore: 0.6 }), null, '清單外的寶可夢不該被查到');
});

test('限制範圍後，錯字更容易被修正到正確的候選', () => {
  // 全圖鑑時「妙蛙草」跟「妙蛙花」互相干擾；限定清單後歧義消失。
  setPool(['妙蛙花', '皮卡丘', '超夢'], 'test-season');
  const hit = lookup('妙蛙化', { minScore: 0.5 });
  assert.equal(hit.entry.zh, '妙蛙花');
});

test('清單用圖鑑編號指定也可以', () => {
  setPool([25, 6], 'by-id');
  assert.equal(getPool().entries.length, 2);
  assert.equal(lookup('皮卡丘').entry.speciesId, 25);
});

test('清空清單後恢復查全圖鑑', () => {
  setPool(['皮卡丘'], 'tiny');
  assert.equal(lookup('班基拉斯', { minScore: 0.6 }), null);
  clearPool();
  assert.ok(lookup('班基拉斯'));
});

test('byPokemonId 直查', () => {
  assert.equal(byPokemonId(25).zh, '皮卡丘');
  assert.equal(byPokemonId(9999), null);
});
