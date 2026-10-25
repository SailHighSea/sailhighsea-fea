import '../../core/db/app_database.dart';

/// Words that point to a kind of spending. The kind is matched against the household's own
/// category names (a category called "Groceries" matches the Food kind), so renamed or extra
/// categories still work. Order matters: the first kind with a hit wins.
const _kinds = <String, ({List<String> keywords, List<String> categoryNames})>{
  'food': (
    keywords: [
      'supermarket',
      'fairprice',
      'ntuc',
      'cold storage',
      'giant',
      'sheng siong',
      'tesco',
      'walmart',
      'aldi',
      'lidl',
      'carrefour',
      'grocer',
      'market',
      'bakery',
      'cafe',
      'coffee',
      'starbucks',
      'restaurant',
      'kitchen',
      'bistro',
      'pizza',
      'burger',
      'mcdonald',
      'kfc',
      'subway',
      'sushi',
      'noodle',
      'hawker',
      'food',
      'dining',
      'grabfood',
      'foodpanda',
      'deliveroo',
      'ubereats',
      'bar ',
      'pub ',
      'tea',
      'bubble',
    ],
    categoryNames: ['food', 'grocer', 'dining', 'eating', 'meals'],
  ),
  'transport': (
    keywords: [
      'petrol',
      'fuel',
      'shell',
      'esso',
      'caltex',
      'spc',
      'taxi',
      'grab',
      'gojek',
      'uber',
      'lyft',
      'comfortdelgro',
      'parking',
      'erp',
      'mrt',
      'bus',
      'transit',
      'ez-link',
      'ezlink',
      'simplygo',
      'railway',
      'train',
      'airline',
      'flight',
      'scoot',
      'airasia',
      'toll',
    ],
    categoryNames: ['transport', 'travel', 'commute', 'car', 'vehicle'],
  ),
  'health': (
    keywords: [
      'pharmacy',
      'chemist',
      'guardian',
      'watsons',
      'clinic',
      'hospital',
      'dental',
      'dentist',
      'doctor',
      'medical',
      'health',
      'optical',
      'physio',
    ],
    categoryNames: ['health', 'medical', 'pharmacy'],
  ),
  'bills': (
    keywords: [
      'electric',
      'utilities',
      'sp services',
      'sp group',
      'water',
      'gas bill',
      'internet',
      'broadband',
      'singtel',
      'starhub',
      'm1 ',
      'telco',
      'mobile',
      'phone bill',
      'insurance',
      'rent',
      'mortgage',
      'condo',
      'maintenance fee',
      'town council',
      'tax',
      'iras',
      'loan',
    ],
    categoryNames: ['bill', 'utilit', 'rent', 'insurance', 'home', 'housing'],
  ),
  'fun': (
    keywords: [
      'netflix',
      'spotify',
      'disney',
      'youtube',
      'cinema',
      'movie',
      'golden village',
      'shaw',
      'concert',
      'ticket',
      'game',
      'steam',
      'playstation',
      'nintendo',
      'theatre',
      'museum',
      'toys',
      'bookstore',
      'kinokuniya',
      'hobby',
      'gym',
      'fitness',
    ],
    categoryNames: ['fun', 'entertain', 'leisure', 'hobby', 'subscription'],
  ),
};

/// Lower case, no digits or punctuation, single spaces: "NTUC FAIRPRICE #123 SG" and "ntuc
/// fairprice 456" become the same key.
String descriptionKey(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// What a description looks like, with how it was decided.
class CategoryGuess {
  const CategoryGuess(this.categoryId, this.reason);
  final String? categoryId;

  /// `remembered`, `history` (you categorised the same shop before), `keyword`, or `none`.
  final String reason;
}

/// Decides a category for each description: first what the household did with the same
/// description before, then keywords. `null` means "ask".
class CategoryGuesser {
  CategoryGuesser({
    required this.categories,
    required this.history,
    this.rules = const {},
  });

  final List<CategoryRow> categories;
  final Map<String, String> history;

  /// Decisions that were remembered on purpose (confirmed in an import or chosen in a form).
  final Map<String, String> rules;

  /// From existing expenses: the most used category per description.
  static Map<String, String> historyFrom(List<ExpenseRow> expenses) {
    final counts = <String, Map<String, int>>{};
    for (final e in expenses) {
      if (e.deletedAt != null || e.note.trim().isEmpty) continue;
      final k = descriptionKey(e.note);
      if (k.isEmpty) continue;
      final m = counts.putIfAbsent(k, () => {});
      m[e.categoryId] = (m[e.categoryId] ?? 0) + 1;
    }
    return {
      for (final e in counts.entries)
        e.key:
            (e.value.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
                .first
                .key,
    };
  }

  /// The remembered category for this shop: the same description, or one that starts with the
  /// other ("azzco hypermarket" and "azzco hypermarket doha"), the longest match first.
  String? _rule(String key) {
    String? best;
    var bestLength = 0;
    for (final e in rules.entries) {
      final r = e.key;
      final exact = r == key;
      final prefix =
          (key.startsWith('$r ') || r.startsWith('$key ')) &&
          (r.length < key.length ? r : key).contains(' ');
      if ((exact || prefix) &&
          r.length > bestLength &&
          categories.any((c) => c.id == e.value)) {
        best = e.value;
        bestLength = r.length;
      }
    }
    return best;
  }

  CategoryGuess guess(String description) {
    final key = descriptionKey(description);
    if (key.isEmpty) return const CategoryGuess(null, 'none');
    final remembered = _rule(key);
    if (remembered != null) return CategoryGuess(remembered, 'remembered');
    final known = history[key];
    if (known != null && categories.any((c) => c.id == known)) {
      return CategoryGuess(known, 'history');
    }
    for (final kind in _kinds.values) {
      if (kind.keywords.any((w) => _hit(key, w.trim()))) {
        for (final c in categories) {
          final name = c.name.toLowerCase();
          if (kind.categoryNames.any(name.contains)) {
            return CategoryGuess(c.id, 'keyword');
          }
        }
      }
    }
    return const CategoryGuess(null, 'none');
  }
}

/// Short words (mrt, bus, spc) must be whole words; longer ones may sit inside a word.
bool _hit(String key, String word) => word.length <= 4
    ? RegExp('\\b${RegExp.escape(word)}\\b').hasMatch(key)
    : key.contains(word);
