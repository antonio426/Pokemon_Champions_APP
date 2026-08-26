import test from 'node:test';
import assert from 'node:assert/strict';
import { asCombatant, bestSTAB, pairMatchup, teamMatchup, liveSummary, verdictOf, weaknessReport } from '../src/matchup.mjs';

test('asCombatant 接受名稱、屬性陣列與圖鑑條目', () => {
  assert.deepEqual(asCombatant('噴火龍').types, ['fire', 'flying']);
  assert.deepEqual(asCombatant(['water', 'flying']).types, ['water', 'flying']);
  assert.deepEqual(asCombatant(['水', '飛行']).types, ['water', 'flying']);
  assert.deepEqual(asCombatant({ label: '自訂', types: ['ghost'] }).types, ['ghost']);
  assert.equal(asCombatant('這不是寶可夢的名字'), null);
});

test('bestSTAB 挑出最好的本系打點', () => {
  const charizard = asCombatant('噴火龍');
  const venusaur = asCombatant('妙蛙花');
  const hit = bestSTAB(charizard, venusaur);
  assert.equal(hit.multiplier, 2);
  assert.equal(hit.via, 'fire'); // 火打草 2×，飛行打草也 2×，取先命中的最大值
});

test('pairMatchup 雙向倍率與勝負判定', () => {
  const m = pairMatchup('噴火龍', '水箭龜');
  assert.equal(m.outgoing.multiplier, 1);
  assert.equal(m.incoming.multiplier, 2);
  assert.equal(m.incoming.via, 'water');
  assert.equal(m.edge, 'unfavorable');
});

test('pairMatchup 反過來就該反過來', () => {
  const m = pairMatchup('水箭龜', '噴火龍');
  assert.equal(m.outgoing.multiplier, 2);
  assert.equal(m.incoming.multiplier, 1);
  assert.equal(m.edge, 'favorable');
});

test('pairMatchup：本系互相無效時判為勢均力敵', () => {
  const m = pairMatchup('耿鬼', '沙奈朵');
  assert.equal(m.edge, 'even');
  assert.equal(m.outgoing.multiplier, m.incoming.multiplier);
});

test('無法解析的一方會明確報錯', () => {
  assert.throws(() => pairMatchup('噴火龍', '不存在'), /無法解析對戰雙方/);
});

test('verdictOf 把倍率翻成動態島要顯示的短語', () => {
  assert.equal(verdictOf(4), '致命');
  assert.equal(verdictOf(2), '克制');
  assert.equal(verdictOf(1), '普通');
  assert.equal(verdictOf(0.5), '不利');
  assert.equal(verdictOf(0.25), '幾乎無效');
  assert.equal(verdictOf(0), '無效');
});

test('teamMatchup 產出完整矩陣，維度與輸入相符', () => {
  const mine = ['噴火龍', '沙奈朵', '耿鬼'];
  const theirs = ['水箭龜', '班基拉斯'];
  const r = teamMatchup(mine, theirs);
  assert.equal(r.matrix.length, 3);
  for (const row of r.matrix) assert.equal(row.length, 2);
  assert.equal(r.matrix[0][1].incoming, 4); // 班基拉斯的岩石 4× 打噴火龍
  assert.equal(r.matrix[0][1].incomingVia, 'rock');
});

test('teamMatchup 的威脅排序：先看能打中幾隻，再看最重的一擊', () => {
  const r = teamMatchup(['噴火龍', '暴鯉龍', '快龍'], ['皮卡丘', '妙蛙花', '班基拉斯']);
  assert.equal(r.threats[0].combatant.label, '班基拉斯');
  assert.equal(r.threats[0].count, 3); // 岩石超效打中全部三隻飛行系
  assert.equal(r.threats[0].peak, 4);
});

test('teamMatchup 的解答會標出誰不會被超效反打', () => {
  const r = teamMatchup(['沙奈朵', '噴火龍'], ['班基拉斯']);
  const gardevoir = r.answers.find((a) => a.combatant.label === '沙奈朵');
  const charizard = r.answers.find((a) => a.combatant.label === '噴火龍');
  assert.equal(gardevoir.safe, true);          // 超能力被惡免疫、惡打超能力 2×… 需實際檢查
  assert.equal(charizard.safe, false);
  assert.equal(charizard.worstIncoming, 4);
});

test('liveSummary 給出動態島要顯示的兩行字', () => {
  // 三隻飛行系對上班基拉斯，牠的岩石打點涵蓋全隊，威脅度不會跟皮卡丘打平。
  const s = liveSummary(['噴火龍', '暴鯉龍', '快龍'], ['皮卡丘', '班基拉斯']);
  assert.match(s.threat, /班基拉斯.*4×/);
  assert.equal(s.threatCount, 3);
  assert.equal(typeof s.answer, 'string');
});

test('liveSummary 在沒有超效關係時給可讀的預設字串，而不是空白', () => {
  const s = liveSummary(['伊布'], ['百變怪']);
  assert.equal(s.threat, '目前無明顯剋制');
  assert.equal(s.answer, '本系無超效打點');
  assert.equal(s.threatCount, 0);
});

test('隊伍其中一邊是空的時候不會炸掉', () => {
  const r = teamMatchup(['噴火龍'], []);
  assert.equal(r.matrix[0].length, 0);
  assert.deepEqual(r.threats, []);
  assert.equal(r.answers[0].count, 0);
});

test('weaknessReport 指出對手隊上誰打得到這個弱點', () => {
  const r = weaknessReport('噴火龍', ['班基拉斯', '水箭龜', '妙蛙花']);
  assert.equal(r.defense.multipliers.rock, 4);
  assert.deepEqual(r.threatenedBy.rock, ['班基拉斯']);
  assert.deepEqual(r.threatenedBy.water, ['水箭龜']);
  assert.ok(!r.threatenedBy.grass, '草不是噴火龍的弱點，不該出現');
});
