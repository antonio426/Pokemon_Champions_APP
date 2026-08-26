import { TYPES, effectiveness, offenseProfile, defenseProfile, zhName, toType } from './typechart.mjs';
import { lookup } from './pokedex.mjs';

/**
 * 把使用者輸入（名稱字串／圖鑑條目／屬性陣列）統一成
 * { label, types } 的作戰單位。
 */
export function asCombatant(input) {
  if (input && Array.isArray(input.types)) {
    return { label: input.zh ?? input.label ?? input.en ?? '?', types: input.types, entry: input.id ? input : null };
  }
  if (Array.isArray(input)) {
    const types = input.map(toType).filter(Boolean);
    return { label: types.map(zhName).join('/'), types, entry: null };
  }
  const hit = lookup(input);
  if (!hit) return null;
  return { label: hit.entry.zh, types: hit.entry.types, entry: hit.entry, score: hit.score };
}

/** 這隻的本系招式打向對手時，最好的那一發是幾倍、用哪個屬性。 */
export function bestSTAB(attacker, defender) {
  let best = -1;
  let via = null;
  for (const atk of attacker.types) {
    const m = effectiveness(atk, defender.types);
    if (m > best) { best = m; via = atk; }
  }
  return { multiplier: best, via };
}

/**
 * 把倍率翻成一句人話。動態島空間極小，這是要直接顯示的文案。
 */
export function verdictOf(multiplier) {
  if (multiplier === 0) return '無效';
  if (multiplier >= 4) return '致命';
  if (multiplier >= 2) return '克制';
  if (multiplier > 1) return '有利';
  if (multiplier === 1) return '普通';
  if (multiplier >= 0.5) return '不利';
  return '幾乎無效';
}

/**
 * 單挑分析：我打牠幾倍、牠打我幾倍，以及誰佔上風。
 */
export function pairMatchup(mine, theirs) {
  const a = asCombatant(mine);
  const b = asCombatant(theirs);
  if (!a || !b) throw new Error(`無法解析對戰雙方：${!a ? mine : theirs}`);

  const outgoing = bestSTAB(a, b);
  const incoming = bestSTAB(b, a);
  let edge = 'even';
  if (outgoing.multiplier > incoming.multiplier) edge = 'favorable';
  else if (outgoing.multiplier < incoming.multiplier) edge = 'unfavorable';

  return {
    mine: a,
    theirs: b,
    outgoing: { ...outgoing, verdict: verdictOf(outgoing.multiplier), viaZh: outgoing.via && zhName(outgoing.via) },
    incoming: { ...incoming, verdict: verdictOf(incoming.multiplier), viaZh: incoming.via && zhName(incoming.via) },
    edge,
  };
}

/**
 * 我方單一寶可夢的完整弱點表，附上「對手隊上誰能打中這個弱點」。
 */
export function weaknessReport(mine, oppTeam = []) {
  const a = asCombatant(mine);
  if (!a) throw new Error(`無法解析：${mine}`);
  const def = defenseProfile(a.types);
  const opps = oppTeam.map(asCombatant).filter(Boolean);

  const threatenedBy = {};
  for (const type of TYPES) {
    if (def.multipliers[type] <= 1) continue;
    const who = opps.filter((o) => o.types.includes(type)).map((o) => o.label);
    if (who.length > 0) threatenedBy[type] = who;
  }
  return { combatant: a, defense: def, threatenedBy };
}

/**
 * 隊伍對隊伍：產出完整矩陣，並挑出最該注意的幾件事。
 * 這是主 App 畫面要顯示的「誰怕誰」總表來源。
 */
export function teamMatchup(myTeam, oppTeam) {
  const mine = myTeam.map(asCombatant).filter(Boolean);
  const theirs = oppTeam.map(asCombatant).filter(Boolean);

  const matrix = mine.map((a) =>
    theirs.map((b) => {
      const out = bestSTAB(a, b);
      const inc = bestSTAB(b, a);
      return { outgoing: out.multiplier, outgoingVia: out.via, incoming: inc.multiplier, incomingVia: inc.via };
    })
  );

  /** 對手中對我方威脅最大的：以「能打出超效的我方隻數 × 最高倍率」排序。 */
  const threats = theirs.map((b, j) => {
    const hits = mine
      .map((a, i) => ({ target: a.label, multiplier: matrix[i][j].incoming, via: matrix[i][j].incomingVia }))
      .filter((h) => h.multiplier > 1)
      .sort((x, y) => y.multiplier - x.multiplier);
    const peak = hits[0]?.multiplier ?? 0;
    return { combatant: b, hits, peak, count: hits.length };
  }).sort((x, y) => y.count - x.count || y.peak - x.peak);

  /** 我方誰是解答：能超效打到最多對手、且不被對方超效反打。 */
  const answers = mine.map((a, i) => {
    const hits = theirs
      .map((b, j) => ({ target: b.label, multiplier: matrix[i][j].outgoing, via: matrix[i][j].outgoingVia }))
      .filter((h) => h.multiplier > 1)
      .sort((x, y) => y.multiplier - x.multiplier);
    const worstIncoming = Math.max(0, ...theirs.map((_, j) => matrix[i][j].incoming));
    return { combatant: a, hits, count: hits.length, worstIncoming, safe: worstIncoming <= 1 };
  }).sort((x, y) => y.count - x.count || x.worstIncoming - y.worstIncoming);

  return { mine, theirs, matrix, threats, answers };
}

/**
 * 動態島用的極簡摘要：一行威脅、一行解答。
 * Live Activity 的顯示空間只夠放這兩件事。
 */
export function liveSummary(myTeam, oppTeam) {
  const { threats, answers } = teamMatchup(myTeam, oppTeam);
  const topThreat = threats.find((t) => t.count > 0);
  const topAnswer = answers.find((a) => a.count > 0);
  return {
    threat: topThreat
      ? `${topThreat.combatant.label} → ${topThreat.hits[0].target} ${topThreat.hits[0].multiplier}×`
      : '目前無明顯剋制',
    answer: topAnswer
      ? `${topAnswer.combatant.label} → ${topAnswer.hits[0].target} ${topAnswer.hits[0].multiplier}×`
      : '本系無超效打點',
    threatCount: topThreat?.count ?? 0,
    answerCount: topAnswer?.count ?? 0,
  };
}
