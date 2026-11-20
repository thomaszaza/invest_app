import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../utils/range_utils.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  List _watchlist = [];

  String _perfRange = '1D'; // plage de performance par défaut
  Map<String, double> _refPrices = {};

  @override
  void initState() {
    super.initState();
    _loadWatchlist();
  }

  Future<void> _loadReferences() async {
    if (_watchlist.isEmpty) return;
    final requested = _perfRange;
    final refs = await HistoricalPrices.fetch(supabase, _watchlist, requested);
    // ignore le résultat si la plage a changé entre-temps
    if (mounted && requested == _perfRange) {
      setState(() => _refPrices = refs);
    }
  }

  Future<void> _loadWatchlist() async {
    setState(() => _isLoading = true);

    try {
      final data = await supabase
          .from('instruments')
          .select('*')
          .eq('is_watchlist', true)
          .order('watchlist_position', ascending: true, nullsFirst: false);

      final List list = List.from(data);

      if (mounted) {
        setState(() {
          _watchlist = list;
          _isLoading = false;
        });
      }

      _loadReferences();

      final List<Future<void>> futures = list.map((inst) async {
        final String isin = inst['ticker_isin'] ?? '';
        inst['isin'] = isin;

        try {
          final double? price = await PriceService.fetchLivePrice(
            inst['name'],
            isin,
            inst['id'],
          );

          if (mounted) {
            setState(() {
              inst['currentPrice'] = price;
            });
          }
        } catch (e) {}
      }).toList();

      await Future.wait(futures);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    setState(() {
      final item = _watchlist.removeAt(oldIndex);
      _watchlist.insert(newIndex, item);
    });
    try {
      await Future.wait([
        for (int i = 0; i < _watchlist.length; i++)
          supabase
              .from('instruments')
              .update({'watchlist_position': i}).eq('id', _watchlist[i]['id']),
      ]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur de sauvegarde de l'ordre : $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Retire de la watchlist (l'instrument reste en base : il peut être en portefeuille)
  Future<void> _removeFromWatchlist(Map inst) async {
    try {
      await supabase
          .from('instruments')
          .update({'is_watchlist': false, 'watchlist_position': null}).eq(
              'id', inst['id']);
      if (mounted) {
        setState(() => _watchlist.removeWhere((i) => i['id'] == inst['id']));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur de suppression : $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showManualPriceDialog(Map<String, dynamic> inst) async {
    final TextEditingController priceController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: Text(
          "Prix manuel : ${inst['name']}",
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: priceController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Entrez le prix unitaire",
            hintStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: Colors.blueAccent),
            child: const Text("Annuler"),
          ),
          TextButton(
            onPressed: () async {
              final double? newPrice = double.tryParse(
                priceController.text.replaceAll(',', '.'),
              );
              if (newPrice == null) return;

              try {
                final today = DateTime.now().toIso8601String().split('T')[0];
                await supabase.from('daily_prices').upsert({
                  'instrument_id': inst['id'],
                  'date': today,
                  'price': newPrice,
                }, onConflict: 'instrument_id,date');

                PriceCache.set(inst['id'].toString(), newPrice);
                HistoricalPrices.clearCache();

                if (context.mounted) {
                  Navigator.pop(context);
                  _loadWatchlist();
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Erreur d'enregistrement : $e"),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text(
              "Enregistrer",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blueAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return RefreshIndicator(
      onRefresh: _loadWatchlist,
      color: Colors.greenAccent,
      backgroundColor: const Color(0xFF1C1C1E),
      child: ReorderableListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        itemCount: _watchlist.length,
        onReorder: _onReorder,
        buildDefaultDragHandles: false,
        proxyDecorator: (child, index, animation) {
          return Material(color: Colors.transparent, child: child);
        },
        itemBuilder: (context, index) {
          final inst = _watchlist[index];
          final double? price = inst['currentPrice'];
          final String isin = (inst['isin'] ?? '').toString();
          final String category = (inst['category'] ?? '').toString();

          final double? ref = _refPrices[inst['id'].toString()];
          final double? perfPct = (price != null && ref != null && ref > 0)
              ? (price - ref) / ref * 100
              : null;

          return ReorderableDelayedDragStartListener(
            key: ValueKey(inst['id']),
            index: index,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Slidable(
                key: ValueKey('slide_${inst['id']}'),
                endActionPane: ActionPane(
                  motion: const DrawerMotion(),
                  extentRatio: 0.28,
                  children: [
                    SlidableAction(
                      onPressed: (_) => _removeFromWatchlist(inst),
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      icon: Icons.delete_outline,
                      label: 'Supprimer',
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ],
                ),
                child: Card(
                  color: const Color(0xFF1C1C1E),
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => InstrumentPager(
                            instruments: _watchlist,
                            initialIndex: index,
                          ),
                        ),
                      );
                      _loadWatchlist();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  inst['name'] ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                                if (isin.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(isin,
                                      style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 13)),
                                ],
                                if (category.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(category,
                                      style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 13)),
                                ],
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                price != null
                                    ? "${price.toStringAsFixed(2)} €"
                                    : "-- €",
                                style: TextStyle(
                                  color: price != null
                                      ? Colors.white
                                      : Colors.white54,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              PerfBadge(
                                label: _perfRange,
                                pct: perfPct,
                                filled: true,
                              ),
                            ],
                          ),
                          const SizedBox(width: 10),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.edit,
                                    color: Colors.white38, size: 19),
                                onPressed: () => _showManualPriceDialog(inst),
                              ),
                              const SizedBox(width: 10),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.notifications_none,
                                    color: Colors.white38, size: 20),
                                onPressed: () =>
                                    showCreateAlertDialog(context, inst),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'Watchlist',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 24,
          ),
        ),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      const AddInstrumentScreen(isWatchlist: true),
                ),
              );
              if (result == true) _loadWatchlist();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 6),
          PerfRangeBar(
            ranges: PerfRange.watchlistRanges,
            selected: _perfRange,
            onSelected: (r) {
              if (r == _perfRange) return;
              setState(() {
                _perfRange = r;
                _refPrices = {};
              });
              _loadReferences();
            },
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white))
                : _watchlist.isEmpty
                    ? const Center(
                        child: Text(
                          "Aucune valeur suivie pour l'instant",
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : _buildList(),
          ),
        ],
      ),
    );
  }
}