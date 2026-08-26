// 對戰分析：給定我方與對方寶可夢，產出動態島/UI 要顯示的核心資訊。

/**
 * @param {import("./typechart.js").TypeChart} chart
 * @param {Object|null} mine 我方條目（可為 null，表示只看對方弱點）
 * @param {Object} opponent 對方條目
 */
export function analyze(chart, mine, opponent) {
  // 18 種攻擊屬性打對方的乘數，由高到低（同乘數依屬性 id）
  const offense = chart.types
    .map((t) => ({
      type: t.identifier,
      type_zh: t.name_zh,
      multiplier: chart.effectiveness(t.identifier, opponent.types),
    }))
    .sort((a, b) => b.multiplier - a.multiplier);

  const result = {
    opponent: summarize(chart, opponent),
    offense,
    weaknesses: offense.filter((o) => o.multiplier > 1),
    resistances: offense.filter((o) => o.multiplier < 1 && o.multiplier > 0),
    immunities: offense.filter((o) => o.multiplier === 0),
  };

  if (mine) {
    result.mine = summarize(chart, mine);
    // 我方本屬性（STAB）打對方
    result.my_stab = mine.types.map((t) => ({
      type: t,
      type_zh: chart.zhName(t),
      multiplier: chart.effectiveness(t, opponent.types),
    }));
    // 對方本屬性（STAB）打我方 —— 威脅度
    result.threats = opponent.types.map((t) => ({
      type: t,
      type_zh: chart.zhName(t),
      multiplier: chart.effectiveness(t, mine.types),
    }));
  }
  return result;
}

function summarize(chart, entry) {
  return {
    id: entry.id,
    dex: entry.dex,
    name_zh: entry.name_zh,
    name_en: entry.name_en,
    types: entry.types,
    types_zh: entry.types.map((t) => chart.zhName(t)),
  };
}

/** 把乘數格式化成顯示字串（4× / 2× / 1× / ½× / ¼× / 0×）。 */
export function fmtMult(m) {
  if (m === 0.5) return "½×";
  if (m === 0.25) return "¼×";
  return `${m}×`;
}
