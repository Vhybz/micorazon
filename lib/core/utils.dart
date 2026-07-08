enum WeightUnit { kg, lb, unit }

class WeightConverter {
  static double toKg(double lbs) => lbs * 0.453592;
  static double toLbs(double kgs) => kgs * 2.20462;
  static double toLb(double kgs) => toLbs(kgs);

  static String formatShort(double weight) {
    if (weight >= 1000) {
      return '${(weight / 1000).toStringAsFixed(1)}t';
    }
    return '${weight.toStringAsFixed(1)}kg';
  }
}

class IdGenerator {
  static String generate({String prefix = 'ID'}) {
    final now = DateTime.now();
    final dateStr = '${now.year.toString().substring(2)}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final timeStr = '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final random = (100 + (now.microsecond % 900)).toString();
    return '$prefix-$dateStr-$timeStr-$random';
  }
}
