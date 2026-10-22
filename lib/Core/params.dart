class Params {
  final Map<String, double> m;
  Params([Map<String, double>? o]) : m = {...defaults, ...?o};

  static const Map<String, double> defaults = {
    // regime / signal
    'adxMin': 22, 'volSpike': 2.2, 'htf': 1, 'minBody': 0.3, 'pbMinAtr': 0.5,
    'pbMaxFrac': 0.62, 'slBuf': 0.3, 'minSlAtr': 1.0, 'maxSlAtr': 3.5, 'minScore': 45,
    // exits
    'tp1R': 1.0, 'tp1Pct': 0.3, 'tp2R': 2.0, 'tp2Pct': 0.3, 'trailAtr': 1.8,
    'give': 0.10, 'giveMinR': 1.5, 'flip': 1,
    // pyramid
    'pyrOn': 1, 'maxSteps': 3, 'pyrStepR': 0.8, 'pyrMult': 1.3,
    // recovery
    'recOn': 1, 'recTrigR': 0.5, 'recBars': 8, 'recMult': 1.5, 'recTrailAtr': 1.0, 'maxRec': 2,
    // risk
    'riskPct': 1.0, 'basketCap': 4.0, 'leverage': 10, 'maxOpen': 3,
    // costs / misc
    'fee': 0.0004, 'slip': 0.0003, 'coolBars': 4,
  };

  double operator [](String k) => m[k] ?? defaults[k]!;
  Params copyWith(Map<String, double> o) => Params({...m, ...o});
  Map<String, dynamic> toJson() => m;
  factory Params.fromJson(Map j) => Params({
        for (final e in j.entries)
          if (e.value is num) e.key as String: (e.value as num).toDouble()
      });

  static Map<String, double> riskPreset(String level) {
    switch (level) {
      case 'low':
        return {'riskPct': 0.5, 'basketCap': 2.0, 'leverage': 5, 'maxOpen': 2, 'maxSteps': 2, 'maxRec': 1, 'minScore': 55};
      case 'high':
        return {'riskPct': 2.0, 'basketCap': 8.0, 'leverage': 20, 'maxOpen': 5, 'maxSteps': 3, 'maxRec': 2, 'minScore': 38};
      default:
        return {'riskPct': 1.0, 'basketCap': 4.0, 'leverage': 10, 'maxOpen': 3, 'maxSteps': 3, 'maxRec': 2, 'minScore': 45};
    }
  }
}
