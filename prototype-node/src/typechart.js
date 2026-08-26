// 18×18 屬性剋制引擎。乘數只會是 0 / 0.25 / 0.5 / 1 / 2 / 4（2 的冪次，浮點相等安全）。

export class TypeChart {
  /** @param {{types: Array, chart: Object}} json data/type_chart.json 的內容 */
  constructor(json) {
    this.types = json.types; // [{id, identifier, name_en, name_zh}]
    this.chart = json.chart; // chart[attack][defense] = 0|0.5|1|2
    this.byIdentifier = new Map(json.types.map((t) => [t.identifier, t]));
    this.byZh = new Map(json.types.map((t) => [t.name_zh, t]));
  }

  /** 單一攻擊屬性對（可能雙屬性的）防禦方的總乘數。 */
  effectiveness(attack, defenseTypes) {
    const row = this.chart[attack];
    if (!row) throw new Error(`未知攻擊屬性: ${attack}`);
    let mult = 1;
    for (const d of defenseTypes) {
      const v = row[d];
      if (v === undefined) throw new Error(`未知防禦屬性: ${d}`);
      mult *= v;
    }
    return mult;
  }

  /** 全部 18 種攻擊屬性對此防禦組合的乘數表。 */
  defensiveProfile(defenseTypes) {
    const profile = {};
    for (const t of this.types)
      profile[t.identifier] = this.effectiveness(t.identifier, defenseTypes);
    return profile;
  }

  /** 繁中屬性名（identifier → 例如 "fire" → "火"）。 */
  zhName(identifier) {
    return this.byIdentifier.get(identifier)?.name_zh ?? identifier;
  }
}
