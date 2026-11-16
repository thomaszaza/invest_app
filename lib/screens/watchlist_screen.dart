import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  List _watchlist = [];

  @override
  void initState() {
    super.initState();
    _loadWatchlist();
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _watchlist.isEmpty
              ? const Center(
                  child: Text(
                    "Aucune valeur suivie pour l'instant",
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadWatchlist,
                  color: Colors.greenAccent,
                  backgroundColor: const Color(0xFF1C1C1E),
                  child: ReorderableListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    itemCount: _watchlist.length,
                    onReorder: _onReorder,
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, index, animation) {
                      return Material(
                        color: Colors.transparent,
                        child: child,
                      );
                    },
                    itemBuilder: (context, index) {
                      final inst = _watchlist[index];
                      final double? price = inst['currentPrice'];
                      final String isin = (inst['isin'] ?? '').toString();
                      final String category =
                          (inst['category'] ?? '').toString();

                      return ReorderableDelayedDragStartListener(
                        key: ValueKey(inst['id']),
                        index: index,
                        child: Card(
                          color: const Color(0xFF1C1C1E),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          margin: const EdgeInsets.only(bottom: 6),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => InstrumentDetailScreen(
                                      instrument: inst),
                                ),
                              );
                              _loadWatchlist();
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(10.0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                          Text(
                                            isin,
                                            style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                        if (category.isNotEmpty) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            category,
                                            style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 13,
                                              
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        price != null
                                            ? "${price.toStringAsFixed(2)} €"
                                            : "-- €",
                                        style: TextStyle(
                                          color: price != null
                                              ? Colors.greenAccent
                                              : Colors.white54,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(
                                          Icons.edit,
                                          color: Colors.white38,
                                          size: 19,
                                        ),
                                        onPressed: () =>
                                            _showManualPriceDialog(inst),
                                      ),
                                      const SizedBox(width: 10),
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(
                                          Icons.notifications_none,
                                          color: Colors.white38,
                                          size: 20,
                                        ),
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
                      );
                    },
                  ),
                ),
    );
  }
}