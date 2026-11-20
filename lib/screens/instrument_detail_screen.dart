import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../services/price_service.dart';
import '../utils/range_utils.dart'; // [NEW]

class InstrumentDetailScreen extends StatefulWidget {
  final JsonMap instrument;
  const InstrumentDetailScreen({super.key, required this.instrument});

  @override
  State<InstrumentDetailScreen> createState() => _InstrumentDetailScreenState();
}

class _InstrumentDetailScreenState extends State<InstrumentDetailScreen> {
  bool _isLoading = true;
  bool _isChartLoading = false;

  // [NEW] dernière plage choisie (1M au démarrage de l'app)
  String _selectedPeriod = ChartRangeStore.value;
  final List<String> _periods = ['1D', '1W', '1M', '3M', 'YTD', '1A', 'ALL'];
  List<FlSpot> _spots = [];
  List<String> _dates = [];
  DoubleMap _fullHistory = {};
  double? _currentPrice;
  double? _pruLine;
  List<double> _alertThresholdLines = [];

  double? _periodFirstPrice;
  double? _periodLastPrice;

  // --- Mesure à deux doigts ---
  static const double _leftReserved = 55.0; // = reservedSize des leftTitles
  final Map<int, Offset> _pointers = {};
  int? _measureA;
  int? _measureB;

  late Future<JsonMap?> _dividendFuture;
  late Future<JsonMap?> _fundamentalsFuture;

  bool get _canEditManualPrice =>
      (widget.instrument['ticker_isin'] ?? '').toString().trim().isEmpty;

  @override
  void initState() {
    super.initState();
    if (!_periods.contains(_selectedPeriod)) _selectedPeriod = '1M'; // [NEW]
    _dividendFuture = _fetchDividendData();
    _fundamentalsFuture = _fetchFundamentalsData();
    _loadHistory(isInitial: true);
  }

  // [NEW] libère le verrou du swipe si la page disparaît pendant un toucher
  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PagerLock.locked.value = false;
    });
    super.dispose();
  }

  // ---------------------------------------------------------------
  // MESURE ENTRE DEUX POINTS
  // ---------------------------------------------------------------
  void _recomputeMeasure(double chartWidth) {
    if (_pointers.length < 2 || _spots.length < 2) {
      _measureA = null;
      _measureB = null;
      return;
    }
    final plotW = chartWidth - _leftReserved;
    if (plotW <= 0) return;

    int toIndex(double dx) =>
        (((dx - _leftReserved) / plotW) * (_spots.length - 1))
            .round()
            .clamp(0, _spots.length - 1)
            .toInt();

    final idx = _pointers.values.take(2).map((o) => toIndex(o.dx)).toList()
      ..sort();
    _measureA = idx[0];
    _measureB = idx[1];
  }

  void _clearMeasure() {
    _pointers.clear();
    _measureA = null;
    _measureB = null;
    PagerLock.locked.value = false; // [NEW]
  }

  Widget _buildMeasureBox() {
    final a = _measureA!, b = _measureB!;
    if (a >= _spots.length || b >= _spots.length) return const SizedBox();

    final y1 = _spots[a].y, y2 = _spots[b].y;
    final diff = y2 - y1;
    final pct = y1.abs() > 0.0001 ? diff / y1 * 100 : 0.0;
    final color = diff >= 0 ? Colors.greenAccent : Colors.redAccent;
    final sign = diff >= 0 ? '+' : '';
    final intraday = _selectedPeriod == '1D' || _selectedPeriod == '1W';
    final fmt = DateFormat(intraday ? 'dd/MM HH:mm' : 'dd/MM/yyyy');
    final d1 = fmt.format(DateTime.parse(_dates[a]));
    final d2 = fmt.format(DateTime.parse(_dates[b]));

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "$d1  →  $d2",
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
            const SizedBox(height: 2),
            Text(
              "$sign${pct.toStringAsFixed(2)} %   ($sign${diff.toStringAsFixed(2)} €)",
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatMarketCap(double value) {
    if (value >= 1e9) return "${(value / 1e9).toStringAsFixed(2)} Md";
    if (value >= 1e6) return "${(value / 1e6).toStringAsFixed(2)} M";
    return value.toStringAsFixed(0);
  }

  Future<JsonMap?> _fetchFundamentalsData() async {
    final String isin =
        widget.instrument['ticker_isin'] ?? widget.instrument['isin'] ?? '';
    if (isin.isEmpty) return null;

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'fetch_fundamentals',
        body: {'ticker': isin},
      );
      debugPrint('fetch_fundamentals → ${response.status} : ${response.data}');

      final data = response.data;
      if (data is Map && data['found'] == true) {
        return {
          'dividendYield': (data['dividendYield'] as num?)?.toDouble(),
          'marketCap': (data['marketCap'] as num?)?.toDouble(),
          'trailingPE': (data['trailingPE'] as num?)?.toDouble(),
        };
      }
    } catch (e) {
      debugPrint('fetch_fundamentals erreur : $e');
    }
    return null;
  }

  Future<void> _loadHistory({bool isInitial = false}) async {
    if (isInitial) {
      setState(() => _isLoading = true);
    } else {
      setState(() => _isChartLoading = true);
    }

    String name = widget.instrument['name'];
    String isin =
        widget.instrument['ticker_isin'] ?? widget.instrument['isin'] ?? '';
    dynamic id = widget.instrument['id'];

    try {
      if (_selectedPeriod == '1D') {
        _fullHistory = await PriceService.fetchYahooIntraday(
          name,
          isin: isin,
          range: '1d',
          interval: '5m',
        );
      } else if (_selectedPeriod == '1W') {
        _fullHistory = await PriceService.fetchYahooIntraday(
          name,
          isin: isin,
          range: '7d',
          interval: '1h',
        );
      } else {
        String yahooRange = 'max';
        if (_selectedPeriod == '1M') {
          yahooRange = '1mo';
        } else if (_selectedPeriod == '3M') {
          yahooRange = '3mo';
        } else if (_selectedPeriod == 'YTD') {
          yahooRange = 'ytd';
        } else if (_selectedPeriod == '1A') {
          yahooRange = '1y';
        } else if (_selectedPeriod == 'ALL') {
          yahooRange = 'max';
        }

        _fullHistory = await PriceService.fetchYahooHistory(
          name,
          isin: isin,
          range: yahooRange,
        );
      }

      final manual = await PriceService.fetchManualHistory(id);
      if (manual.isNotEmpty) {
        _fullHistory = manual;
      } else if (_fullHistory.isEmpty) {
        final supabase = Supabase.instance.client;
        final rows = await supabase
            .from('daily_prices')
            .select('date, price')
            .eq('instrument_id', id)
            .order('date');
        for (var row in rows) {
          _fullHistory[row['date'].toString()] =
              (row['price'] as num).toDouble();
        }
      }
    } catch (e) {}

    double? live = await PriceService.fetchLivePrice(name, isin, id);
    _currentPrice = live;
    if (live != null) {
      final now = DateTime.now().toIso8601String();
      _fullHistory[now] = live;
    }

    if (isInitial) {
      await _loadReferenceLines();
    }

    _buildChart();
    if (mounted) {
      setState(() {
        _isLoading = false;
        _isChartLoading = false;
      });
    }
  }

  Future<void> _loadReferenceLines() async {
    final supabase = Supabase.instance.client;
    dynamic id = widget.instrument['id'];

    if (widget.instrument['pru'] != null &&
        (widget.instrument['pru'] as num).toDouble() > 0.001) {
      _pruLine = (widget.instrument['pru'] as num).toDouble();
    } else if (id != null) {
      try {
        final txData = await supabase
            .from('transactions')
            .select('transaction_type, quantity, unit_price, fees')
            .eq('instrument_id', id)
            .order('date', ascending: true);

        double qty = 0.0;
        double boughtQty = 0.0;
        double invested = 0.0;

        for (var tx in txData) {
          double q = (tx['quantity'] ?? 0).toDouble();
          double p = (tx['unit_price'] ?? 0).toDouble();
          double fee = (tx['fees'] ?? 0).toDouble();
          String type = tx['transaction_type'];

          if (type == 'Buy' || type == 'Deposit') {
            qty += q;
            boughtQty += q;
            invested += (q * p) + fee;
          } else if (type == 'Sell') {
            double currentPru = boughtQty > 0.001 ? invested / boughtQty : 0.0;
            qty -= q;
            boughtQty -= q;
            invested -= (q * currentPru);
          }
        }

        if (qty > 0.001 && boughtQty > 0.001) {
          _pruLine = invested / boughtQty;
        }
      } catch (e) {}
    }

    if (id != null) {
      try {
        final alerts = await supabase
            .from('alerts')
            .select('threshold_price')
            .eq('instrument_id', id)
            .eq('active', true)
            .eq('triggered', false)
            .order('threshold_price');
        _alertThresholdLines = alerts
            .map<double>((a) => (a['threshold_price'] as num).toDouble())
            .toList();
      } catch (e) {}
    }
  }

  void _buildChart() {
    if (_fullHistory.isEmpty) {
      _spots = [];
      _dates = [];
      _periodFirstPrice = null;
      _periodLastPrice = null;
      return;
    }

    List<String> sortedDates = _fullHistory.keys.toList()..sort();
    DateTime endDate = DateTime.parse(sortedDates.last);
    DateTime startDate = endDate;

    if (_selectedPeriod == '1D') {
      startDate = endDate.subtract(const Duration(hours: 24));
    } else if (_selectedPeriod == '1W') {
      startDate = endDate.subtract(const Duration(days: 7));
    } else if (_selectedPeriod == '1M') {
      startDate = endDate.subtract(const Duration(days: 30));
    } else if (_selectedPeriod == '3M') {
      startDate = endDate.subtract(const Duration(days: 90));
    } else if (_selectedPeriod == '1A') {
      startDate = endDate.subtract(const Duration(days: 365));
    } else if (_selectedPeriod == 'YTD') {
      startDate = DateTime(endDate.year, 1, 1);
    } else if (_selectedPeriod == 'ALL') {
      startDate = DateTime.parse(sortedDates.first);
    }

    List<String> filteredDates = sortedDates.where((dateStr) {
      return !DateTime.parse(dateStr).isBefore(startDate);
    }).toList();

    if (filteredDates.isEmpty) return;

    _periodFirstPrice = _fullHistory[filteredDates.first];
    _periodLastPrice = _fullHistory[filteredDates.last];

    List<String> dates = [];

    if (_selectedPeriod == '1D') {
      dates = List.from(filteredDates);
    } else if (_selectedPeriod == '1W') {
      Set<String> seenHours = {};
      for (var dateStr in filteredDates) {
        DateTime d = DateTime.parse(dateStr);
        String dayHour = "${d.year}-${d.month}-${d.day} ${d.hour}";
        if (!seenHours.contains(dayHour)) {
          seenHours.add(dayHour);
          dates.add(dateStr);
        }
      }
    } else if (_selectedPeriod == '1M' || _selectedPeriod == '3M') {
      Set<String> seenDays = {};
      for (var dateStr in filteredDates) {
        String day = dateStr.split('T')[0];
        if (!seenDays.contains(day)) {
          seenDays.add(day);
          dates.add(dateStr);
        }
      }
    } else if (_selectedPeriod == '1A') {
      DateTime? lastAddedDate;
      for (var dateStr in filteredDates) {
        DateTime d = DateTime.parse(dateStr);
        if (lastAddedDate == null || d.difference(lastAddedDate).inDays >= 7) {
          dates.add(dateStr);
          lastAddedDate = d;
        }
      }
    } else {
      int targetCount = 50;
      if (filteredDates.length <= targetCount) {
        dates = List.from(filteredDates);
      } else {
        double step = filteredDates.length / targetCount;
        for (int i = 0; i < targetCount; i++) {
          int index = (i * step).round();
          if (index < filteredDates.length) {
            dates.add(filteredDates[index]);
          }
        }
        if (dates.last != filteredDates.last) {
          dates.add(filteredDates.last);
        }
      }
    }

    if (dates.isNotEmpty) {
      if (dates.first != filteredDates.first) {
        dates.insert(0, filteredDates.first);
      }
      if (dates.last != filteredDates.last) {
        dates.add(filteredDates.last);
      }
    }

    List<FlSpot> spots = [];
    int i = 0;
    for (var dateStr in dates) {
      spots.add(FlSpot(i.toDouble(), _fullHistory[dateStr]!));
      i++;
    }

    _spots = spots;
    _dates = dates;
  }

  Future<void> _showEditInstrumentDialog() async {
    JsonMap instrumentData = widget.instrument;
    try {
      final freshData = await Supabase.instance.client
          .from('instruments')
          .select()
          .eq('id', widget.instrument['id'])
          .single();
      instrumentData = freshData;
    } catch (e) {}

    String? selectedCategory = instrumentData['category'];
    if (selectedCategory != null && !kCategories.contains(selectedCategory)) {
      selectedCategory = null;
    }

    final now = DateTime.now();
    final datePrefix =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} - ';

    String existingComment =
        (instrumentData['comment'] ?? '').toString().trim();

    final String initialCommentText = existingComment.isEmpty
        ? datePrefix
        : '$existingComment\n$datePrefix';

    final TextEditingController commentController = TextEditingController(
      text: initialCommentText,
    );

    final nameController = TextEditingController(
      text: instrumentData['name'] ?? '',
    );
    final isinController = TextEditingController(
      text: instrumentData['ticker_isin'] ?? '',
    );

    List<JsonMap> dialogAccountsList = [];
    dynamic selectedAccountId = instrumentData['account_id'];

    try {
      final accountsData = await Supabase.instance.client
          .from('accounts')
          .select('id, name')
          .order('name');
      dialogAccountsList = List<JsonMap>.from(accountsData);
    } catch (e) {}

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          title: Text(
            "Modifier : ${widget.instrument['name']}",
            style: const TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Nom de l\'action / ETF / crypto',
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: isinController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Ticker / ISIN',
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<dynamic>(
                  value: selectedAccountId,
                  dropdownColor: const Color(0xFF2C2C2E),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Compte associé',
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ),
                  items: dialogAccountsList.map((acc) {
                    return DropdownMenuItem(
                      value: acc['id'],
                      child: Text(
                        acc['name'],
                        style: const TextStyle(color: Colors.white),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) =>
                      setDialogState(() => selectedAccountId = value),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  dropdownColor: const Color(0xFF2C2C2E),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Catégorie',
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ),
                  items: kCategories
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(
                            c,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => selectedCategory = value),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: commentController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Commentaire',
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ),
                ),
              ],
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
                String finalComment = commentController.text.trim();
                String prefixToMatch = datePrefix.trim();

                if (finalComment.endsWith(prefixToMatch)) {
                  finalComment = finalComment
                      .substring(0, finalComment.length - prefixToMatch.length)
                      .trim();
                }

                try {
                  await Supabase.instance.client
                      .from('instruments')
                      .update({
                        'name': nameController.text.trim(),
                        'ticker_isin': isinController.text.trim(),
                        'category': selectedCategory,
                        'comment': finalComment,
                        'account_id': selectedAccountId,
                      })
                      .eq('id', widget.instrument['id']);

                  setState(() {
                    widget.instrument['name'] = nameController.text.trim();
                    widget.instrument['ticker_isin'] =
                        isinController.text.trim();
                    widget.instrument['account_id'] = selectedAccountId;
                    widget.instrument['category'] = selectedCategory;
                    widget.instrument['comment'] = finalComment;
                  });

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Instrument mis à jour !"),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Erreur: $e"),
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
      ),
    );
  }

  Future<void> _showManualPricesDialog() async {
    if (!_canEditManualPrice) return;
    final supabase = Supabase.instance.client;
    final id = widget.instrument['id'];
    List<JsonMap> rows = [];
    bool changed = false;

    Future<void> reload() async {
      final data = await supabase
          .from('manual_prices')
          .select('id, date, price')
          .eq('instrument_id', id)
          .order('date', ascending: false);
      rows = List<JsonMap>.from(data);
    }

    try {
      await reload();
    } catch (e) {}

    DateTime selectedDate = DateTime.now();
    final priceController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          title: const Text(
            "Valeurs manuelles",
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Entre deux dates, l'évolution est considérée linéaire.",
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white30),
                          ),
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(
                            DateFormat('dd/MM/yyyy').format(selectedDate),
                          ),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: selectedDate,
                              firstDate: DateTime(2000),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (picked != null) {
                              setD(() => selectedDate = picked);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: priceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Valeur (€)',
                            labelStyle: TextStyle(color: Colors.white54),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () async {
                        final v = double.tryParse(
                          priceController.text.trim().replaceAll(',', '.'),
                        );
                        if (v == null || v <= 0) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text("Valeur invalide"),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        try {
                          await supabase.from('manual_prices').upsert({
                            'instrument_id': id,
                            'date':
                                DateFormat('yyyy-MM-dd').format(selectedDate),
                            'price': v,
                          }, onConflict: 'instrument_id,date');
                          await reload();
                          changed = true;
                          priceController.clear();
                          setD(() {});
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text("Erreur : $e"),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      child: const Text(
                        "Ajouter / remplacer",
                        style: TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const Divider(color: Colors.white24),
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        "Aucune valeur saisie.",
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  ...rows.map((r) {
                    final d = DateTime.parse(r['date'].toString());
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        "${DateFormat('dd/MM/yyyy').format(d)}  —  ${(r['price'] as num).toDouble().toStringAsFixed(2)} €",
                        style: const TextStyle(color: Colors.white),
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                        onPressed: () async {
                          try {
                            await supabase
                                .from('manual_prices')
                                .delete()
                                .eq('id', r['id']);
                            await reload();
                            changed = true;
                            setD(() {});
                          } catch (e) {}
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                "Fermer",
                style: TextStyle(color: Colors.blueAccent),
              ),
            ),
          ],
        ),
      ),
    );

    priceController.dispose();
    if (changed && mounted) {
      HistoricalPrices.clearCache(); // [NEW] les perfs des listes doivent se recalculer
      _loadHistory(isInitial: true);
    }
  }

  Future<JsonMap?> _fetchDividendData() async {
    try {
      String ticker =
          widget.instrument['ticker_isin'] ?? widget.instrument['isin'] ?? '';
      if (ticker.isEmpty) return null;

      final response = await Supabase.instance.client.functions.invoke(
        'fetch_dividend',
        body: {'ticker': ticker},
      );

      final data = response.data;

      if (data != null && data['found'] == true) {
        final double amount = (data['amount'] as num).toDouble();
        final String displayDate = data['displayDate'];
        final String sqlDate = data['sqlDate'];

        try {
          await Supabase.instance.client
              .from('instruments')
              .update({
                'last_dividend_date': sqlDate,
                'last_dividend_amount': amount,
              })
              .eq('id', widget.instrument['id']);
        } catch (e) {
          debugPrint("Erreur de sauvegarde en base : $e");
        }

        return {'amount': amount, 'date': displayDate};
      }

      return null;
    } catch (e) {
      debugPrint("Erreur lors de l'appel à fetch_dividend : $e");
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    double perfPct = 0.0;
    Color perfColor = Colors.white;
    if (_periodFirstPrice != null &&
        _periodLastPrice != null &&
        _periodFirstPrice! > 0.001) {
      perfPct =
          ((_periodLastPrice! - _periodFirstPrice!) / _periodFirstPrice!) * 100;
      perfColor = perfPct >= 0 ? Colors.greenAccent : Colors.redAccent;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.instrument['name'],
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (_canEditManualPrice)
            IconButton(
              icon: const Icon(Icons.add_chart, color: Colors.white),
              tooltip: 'Valeurs manuelles',
              onPressed: _showManualPricesDialog,
            ),
          IconButton(
            icon: const Icon(Icons.edit_note, color: Colors.white),
            onPressed: _showEditInstrumentDialog,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () async {
              final confirm =
                  await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: const Color(0xFF1C1C1E),
                      title: const Text(
                        "Supprimer la valeur",
                        style: TextStyle(color: Colors.white),
                      ),
                      content: Text(
                        "Supprimer définitivement \"${widget.instrument['name']}\" et tout son historique de transactions ? Cette action est irréversible.",
                        style: const TextStyle(color: Colors.white70),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.blueAccent,
                          ),
                          child: const Text("Annuler"),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text(
                            "Supprimer",
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ) ??
                  false;

              if (!confirm) return;

              try {
                final id = widget.instrument['id'];
                await Supabase.instance.client
                    .from('alerts')
                    .delete()
                    .eq('instrument_id', id);
                await Supabase.instance.client
                    .from('transactions')
                    .delete()
                    .eq('instrument_id', id);
                await Supabase.instance.client
                    .from('daily_prices')
                    .delete()
                    .eq('instrument_id', id);
                await Supabase.instance.client
                    .from('instruments')
                    .delete()
                    .eq('id', id);

                if (context.mounted) {
                  Navigator.pop(context, true);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Erreur lors de la suppression : $e"),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : SingleChildScrollView(
              // Bloque le scroll vertical pendant la mesure à deux doigts
              physics: _pointers.length >= 2
                  ? const NeverScrollableScrollPhysics()
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentPrice != null
                              ? "${_currentPrice!.toStringAsFixed(2)} €"
                              : "Non coté",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (_periodFirstPrice != null &&
                            _periodLastPrice != null)
                          Text(
                            "${perfPct >= 0 ? '+' : ''}${perfPct.toStringAsFixed(2)} % sur la période",
                            style: TextStyle(
                              color: perfColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        if ((widget.instrument['category'] ?? '')
                            .toString()
                            .isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              widget.instrument['category'],
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                        if ((widget.instrument['comment'] ?? '')
                            .toString()
                            .isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            widget.instrument['comment'],
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 300,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        right: 20,
                        left: 10,
                        bottom: 10,
                      ),
                      child: _isChartLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            )
                          : _spots.isEmpty
                              ? const Center(
                                  child: Text(
                                    "Pas de données disponibles",
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                )
                              : LayoutBuilder(
                                  builder: (context, constraints) {
                                    final w = constraints.maxWidth;

                                    void onPointer(
                                      PointerEvent e, {
                                      bool remove = false,
                                    }) {
                                      final before = _pointers.length;
                                      if (remove) {
                                        _pointers.remove(e.pointer);
                                      } else {
                                        _pointers[e.pointer] = e.localPosition;
                                      }
                                      // [NEW] verrouille le swipe entre fiches
                                      // tant qu'un doigt est sur le graphique
                                      PagerLock.locked.value =
                                          _pointers.isNotEmpty;

                                      // Un seul doigt : on laisse fl_chart gérer
                                      // le tooltip, pas besoin de reconstruire.
                                      if (_pointers.length < 2 && before < 2) {
                                        return;
                                      }
                                      setState(() => _recomputeMeasure(w));
                                    }

                                    return Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Listener(
                                          onPointerDown: onPointer,
                                          onPointerMove: onPointer,
                                          onPointerUp: (e) =>
                                              onPointer(e, remove: true),
                                          onPointerCancel: (e) =>
                                              onPointer(e, remove: true),
                                          child: LineChart(
                                            LineChartData(
                                              gridData: FlGridData(
                                                show: true,
                                                drawVerticalLine: false,
                                                getDrawingHorizontalLine: (v) =>
                                                    FlLine(
                                                  color: Colors.white10,
                                                  strokeWidth: 1,
                                                ),
                                              ),
                                              titlesData: FlTitlesData(
                                                show: true,
                                                rightTitles: const AxisTitles(
                                                  sideTitles: SideTitles(
                                                    showTitles: false,
                                                  ),
                                                ),
                                                topTitles: const AxisTitles(
                                                  sideTitles: SideTitles(
                                                    showTitles: false,
                                                  ),
                                                ),
                                                bottomTitles: AxisTitles(
                                                  sideTitles: SideTitles(
                                                    showTitles: true,
                                                    reservedSize: 40,
                                                    interval: (_spots.length / 5)
                                                                .ceilToDouble() ==
                                                            0
                                                        ? 1
                                                        : (_spots.length / 5)
                                                            .ceilToDouble(),
                                                    getTitlesWidget:
                                                        (value, meta) {
                                                      int index = value.toInt();
                                                      if (index >= 0 &&
                                                          index <
                                                              _dates.length) {
                                                        DateTime d =
                                                            DateTime.parse(
                                                          _dates[index],
                                                        );
                                                        String day = d.day
                                                            .toString()
                                                            .padLeft(2, '0');
                                                        String month = d.month
                                                            .toString()
                                                            .padLeft(2, '0');

                                                        String text;
                                                        if (_selectedPeriod ==
                                                            '1D') {
                                                          String hour = d.hour
                                                              .toString()
                                                              .padLeft(2, '0');
                                                          String min = d.minute
                                                              .toString()
                                                              .padLeft(2, '0');
                                                          text = '$hour:$min';
                                                        } else if (_selectedPeriod ==
                                                            '1W') {
                                                          String hour = d.hour
                                                              .toString()
                                                              .padLeft(2, '0');
                                                          String min = d.minute
                                                              .toString()
                                                              .padLeft(2, '0');
                                                          text =
                                                              '$day/$month\n$hour:$min';
                                                        } else if (_selectedPeriod ==
                                                                'ALL' ||
                                                            _selectedPeriod ==
                                                                '1A' ||
                                                            _selectedPeriod ==
                                                                'YTD') {
                                                          text =
                                                              '$month/${d.year.toString().substring(2)}';
                                                        } else {
                                                          text = '$day/$month';
                                                        }

                                                        return Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(
                                                            top: 8.0,
                                                          ),
                                                          child: Text(
                                                            text,
                                                            textAlign: TextAlign
                                                                .center,
                                                            style:
                                                                const TextStyle(
                                                              color: Colors
                                                                  .white54,
                                                              fontSize: 10,
                                                            ),
                                                          ),
                                                        );
                                                      }
                                                      return const Text('');
                                                    },
                                                  ),
                                                ),
                                                leftTitles: AxisTitles(
                                                  sideTitles: SideTitles(
                                                    showTitles: true,
                                                    reservedSize: _leftReserved,
                                                    getTitlesWidget:
                                                        (value, meta) => Text(
                                                      '${value.toStringAsFixed(0)} €',
                                                      style: const TextStyle(
                                                        color: Colors.white54,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              borderData:
                                                  FlBorderData(show: false),
                                              extraLinesData: ExtraLinesData(
                                                horizontalLines: [
                                                  if (_pruLine != null)
                                                    HorizontalLine(
                                                      y: _pruLine!,
                                                      color: Colors.white70,
                                                      strokeWidth: 1.5,
                                                      dashArray: [6, 4],
                                                      label:
                                                          HorizontalLineLabel(
                                                        show: true,
                                                        alignment:
                                                            Alignment.topRight,
                                                        style: const TextStyle(
                                                          color: Colors.white70,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                        labelResolver: (line) =>
                                                            "PRU ${_pruLine!.toStringAsFixed(2)} €",
                                                      ),
                                                    ),
                                                  for (final t
                                                      in _alertThresholdLines)
                                                    HorizontalLine(
                                                      y: t,
                                                      color: Colors.white70,
                                                      strokeWidth: 1,
                                                      label:
                                                          HorizontalLineLabel(
                                                        show: true,
                                                        alignment: Alignment
                                                            .bottomRight,
                                                        style: const TextStyle(
                                                          color: Colors.white70,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                        labelResolver: (line) =>
                                                            "Alerte ${t.toStringAsFixed(2)} €",
                                                      ),
                                                    ),
                                                ],
                                                verticalLines: [
                                                  if (_measureA != null)
                                                    VerticalLine(
                                                      x: _measureA!.toDouble(),
                                                      color: Colors.white54,
                                                      strokeWidth: 1,
                                                      dashArray: [4, 4],
                                                    ),
                                                  if (_measureB != null)
                                                    VerticalLine(
                                                      x: _measureB!.toDouble(),
                                                      color: Colors.white54,
                                                      strokeWidth: 1,
                                                      dashArray: [4, 4],
                                                    ),
                                                ],
                                              ),
                                              lineTouchData: LineTouchData(
                                                // Coupe le tooltip pendant la mesure
                                                enabled: _pointers.length < 2,
                                                touchTooltipData:
                                                    LineTouchTooltipData(
                                                  getTooltipItems:
                                                      (touchedSpots) =>
                                                          touchedSpots
                                                              .map((spot) {
                                                    int index = spot.x.toInt();
                                                    String formattedDate = "";
                                                    if (index < _dates.length) {
                                                      DateTime parsedDate =
                                                          DateTime.parse(
                                                        _dates[index],
                                                      );
                                                      formattedDate =
                                                          DateFormat(
                                                        'dd/MM/yyyy',
                                                      ).format(parsedDate);
                                                    }
                                                    return LineTooltipItem(
                                                      "$formattedDate\n${spot.y.toStringAsFixed(2)} €",
                                                      const TextStyle(
                                                        color: Colors.white,
                                                      ),
                                                    );
                                                  }).toList(),
                                                ),
                                              ),
                                              lineBarsData: [
                                                LineChartBarData(
                                                  spots: _spots,
                                                  isCurved: false,
                                                  color: perfColor,
                                                  barWidth: 2,
                                                  isStrokeCapRound: true,
                                                  dotData: FlDotData(
                                                    show: _measureA != null &&
                                                        _measureB != null,
                                                    checkToShowDot:
                                                        (spot, barData) {
                                                      final index =
                                                          spot.x.toInt();

                                                      return index ==
                                                              _measureA ||
                                                          index == _measureB;
                                                    },
                                                    getDotPainter: (
                                                      spot,
                                                      percent,
                                                      barData,
                                                      index,
                                                    ) {
                                                      return FlDotCirclePainter(
                                                        radius: 5,
                                                        color: perfColor,
                                                        strokeWidth: 2,
                                                        strokeColor:
                                                            Colors.white,
                                                      );
                                                    },
                                                  ),
                                                  belowBarData: BarAreaData(
                                                    show: true,
                                                    color: perfColor
                                                        .withOpacity(0.1),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (_measureA != null &&
                                            _measureB != null)
                                          Positioned(
                                            top: 0,
                                            left: _leftReserved,
                                            right: 0,
                                            child: IgnorePointer(
                                              child: _buildMeasureBox(),
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: _periods.map((period) {
                        final isSelected = _selectedPeriod == period;
                        return GestureDetector(
                          onTap: () {
                            if (_selectedPeriod != period) {
                              ChartRangeStore.value = period; // [NEW]
                              setState(() {
                                _selectedPeriod = period;
                                _clearMeasure();
                              });
                              _loadHistory();
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF333333)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Text(
                              period,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white54,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      "Dividendes",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  FutureBuilder<JsonMap?>(
                    future: _dividendFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(24.0),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                        );
                      }
                      if (snapshot.hasError ||
                          !snapshot.hasData ||
                          snapshot.data == null) {
                        return const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            "Aucun dividende récent trouvé pour cette action.",
                            style: TextStyle(color: Colors.white54),
                          ),
                        );
                      }

                      final divData = snapshot.data!;
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 12.0,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1C1E),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.monetization_on,
                                color: Colors.greenAccent,
                                size: 32,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  "Dernier versement : ${divData['amount'].toStringAsFixed(2)} €/unité le ${divData['date']}",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      "Fondamentaux",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  FutureBuilder<JsonMap?>(
                    future: _fundamentalsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(24.0),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                        );
                      }
                      if (!snapshot.hasData || snapshot.data == null) {
                        return const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            "Données fondamentales non disponibles.",
                            style: TextStyle(color: Colors.white54),
                          ),
                        );
                      }

                      final data = snapshot.data!;
                      Widget statTile(String label, String value) => Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1C1E),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Text(
                                value,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                label,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 12.0,
                        ),
                        child: Row(
                          children: [
                            statTile(
                              "Rendement dividende",
                              data['dividendYield'] != null
                                  ? "${data['dividendYield'].toStringAsFixed(2)} %"
                                  : "-",
                            ),
                            statTile(
                              "Capitalisation",
                              data['marketCap'] != null
                                  ? _formatMarketCap(data['marketCap'])
                                  : "-",
                            ),
                            statTile(
                              "P/E ratio",
                              data['trailingPE'] != null
                                  ? data['trailingPE'].toStringAsFixed(1)
                                  : "-",
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }
}