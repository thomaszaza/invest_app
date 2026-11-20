import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/instrument_detail_screen.dart'; // ⚠️ adapte le chemin si besoin
import '../services/price_service.dart';

/// Plage du graphique de la fiche : mémorise la dernière choisie.
/// Variable statique => repasse à 1M à chaque lancement de l'app.
class ChartRangeStore {
  static String value = '1M';
}

/// Verrou du swipe entre fiches : activé quand un doigt touche le graphique
/// (pour ne pas casser le tooltip ni la mesure à deux doigts).
class PagerLock {
  static final ValueNotifier<bool> locked = ValueNotifier<bool>(false);
}

/// Plages de performance (listes positions / watchlist)
class PerfRange {
  static const String pru = 'PRU';
  static const List<String> watchlistRanges = [
    '1D',
    '1W',
    '1M',
    '3M',
    '6M',
    'YTD',
    '1A',
  ];
  static const List<String> positionsRanges = [pru, ...watchlistRanges];

  /// Date de référence : on prend le dernier prix connu <= cette date.
  static DateTime startDate(String label) {
    final now = DateTime.now();
    switch (label) {
      case '1D':
        return now.subtract(const Duration(days: 1));
      case '1W':
        return now.subtract(const Duration(days: 7));
      case '1M':
        return DateTime(now.year, now.month - 1, now.day);
      case '3M':
        return DateTime(now.year, now.month - 3, now.day);
      case '6M':
        return DateTime(now.year, now.month - 6, now.day);
      case 'YTD':
        return DateTime(now.year - 1, 12, 31, 23, 59);
      case '1A':
        return DateTime(now.year - 1, now.month, now.day);
      default:
        return now;
    }
  }
}

class _CacheEntry {
  final DateTime at;
  final Map<String, double> data;
  _CacheEntry(this.at, this.data);
}

class HistoricalPrices {
  static final Map<String, _CacheEntry> _cache = {};

  static void clearCache() => _cache.clear();

  /// Historique journalier d'un instrument (mis en cache 15 min).
  /// Même logique de sources que la fiche : Yahoo -> manuel -> daily_prices.
  static Future<Map<String, double>> _history(
    SupabaseClient client,
    Map inst,
  ) async {
    final id = inst['id'];
    final key = id.toString();
    final cached = _cache[key];
    if (cached != null && DateTime.now().difference(cached.at).inMinutes < 15) {
      return cached.data;
    }

    final String name = (inst['name'] ?? '').toString();
    final String isin = (inst['ticker_isin'] ?? inst['isin'] ?? '').toString();

    Map<String, double> h = {};
    try {
      final y = await PriceService.fetchYahooHistory(
        name,
        isin: isin,
        range: '2y',
      );
      h = Map<String, double>.from(y);
    } catch (_) {}

    try {
      final manual = await PriceService.fetchManualHistory(id);
      if (manual.isNotEmpty) h = Map<String, double>.from(manual);
    } catch (_) {}

    if (h.isEmpty) {
      try {
        final rows = await client
            .from('daily_prices')
            .select('date, price')
            .eq('instrument_id', id)
            .order('date');
        for (final row in rows) {
          h[row['date'].toString()] = (row['price'] as num).toDouble();
        }
      } catch (_) {}
    }

    _cache[key] = _CacheEntry(DateTime.now(), h);
    return h;
  }

  static double? _pick(Map<String, double> h, DateTime target) {
    if (h.isEmpty) return null;
    final keys = h.keys.toList()..sort();
    String? best;
    for (final k in keys) {
      final d = DateTime.tryParse(k);
      if (d == null) continue;
      if (d.isAfter(target)) break;
      best = k;
    }
    return best == null ? null : h[best];
  }

  /// Retourne {id.toString(): prix de référence} pour la plage [label].
  static Future<Map<String, double>> fetch(
    SupabaseClient client,
    List instruments,
    String label,
  ) async {
    final target = PerfRange.startDate(label);
    final Map<String, double> out = {};
    await Future.wait(
      instruments.map((inst) async {
        try {
          final h = await _history(client, inst as Map);
          final p = _pick(h, target);
          if (p != null) out[inst['id'].toString()] = p;
        } catch (_) {}
      }),
    );
    return out;
  }
}

/// Barre de sélection de plage (chips horizontales)
class PerfRangeBar extends StatelessWidget {
  final List<String> ranges;
  final String selected;
  final ValueChanged<String> onSelected;

  const PerfRangeBar({
    super.key,
    required this.ranges,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: ranges.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final r = ranges[i];
          final isSel = r == selected;
          return GestureDetector(
            onTap: () => onSelected(r),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSel ? Colors.white : const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Text(
                r,
                style: TextStyle(
                  color: isSel ? Colors.black : Colors.white54,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Badge de performance.
/// filled = true  -> performance sur une plage de temps (fond teinté)
/// filled = false -> performance par rapport au PRU (contour seul)
class PerfBadge extends StatelessWidget {
  final String label;
  final double? pct;
  final bool filled;

  const PerfBadge({
    super.key,
    required this.label,
    required this.pct,
    required this.filled,
  });

  @override
  Widget build(BuildContext context) {
    if (pct == null) {
      return const Text(
        '--',
        style: TextStyle(color: Colors.white38, fontSize: 13),
      );
    }
    final color = pct! >= 0 ? Colors.greenAccent : Colors.redAccent;
    final sign = pct! >= 0 ? '+' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? color.withOpacity(0.18) : Colors.transparent,
        border: filled ? null : Border.all(color: color.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color.withOpacity(0.75),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$sign${pct!.toStringAsFixed(2)}%',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Swipe gauche/droite pour passer à l'action suivante/précédente de la liste.
class InstrumentPager extends StatefulWidget {
  final List instruments;
  final int initialIndex;

  const InstrumentPager({
    super.key,
    required this.instruments,
    required this.initialIndex,
  });

  @override
  State<InstrumentPager> createState() => _InstrumentPagerState();
}

class _InstrumentPagerState extends State<InstrumentPager> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PagerLock.locked,
      builder: (context, locked, _) => PageView.builder(
        controller: _controller,
        physics: locked
            ? const NeverScrollableScrollPhysics()
            : const PageScrollPhysics(),
        itemCount: widget.instruments.length,
        itemBuilder: (context, i) => InstrumentDetailScreen(
          key: ValueKey(widget.instruments[i]['id']),
          instrument: widget.instruments[i],
        ),
      ),
    );
  }
}
