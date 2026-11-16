import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../main.dart';

class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  List<JsonMap> _benchmarkList = [];
  String? _selectedBenchmarkId;
  List<FlSpot> _chartDataBenchmark = [];

  final supabase = Supabase.instance.client;
  bool _isLoading = true;

  String _selectedPeriod = '1M';
  final List<String> _periods = ['1D', '1W', '1M', '3M', 'YTD', '1A', 'ALL'];

  List<JsonMap> _accountsList = [];
  String? _selectedAccountId;

  double _totalDividends = 0.0;
  double _periodPerformanceAbs = 0.0;
  double _periodPerformancePct = 0.0;
  double _currentPortfolioValue = 0.0;

  List<FlSpot> _chartDataValue = [];
  List<FlSpot> _chartDataPercent = [];
  bool _showPercent = false;

  List<String> _chartDates = [];

  // --- Mesure à deux doigts ---
  static const double _leftReserved = 50.0; // = reservedSize des leftTitles
  final Map<int, Offset> _pointers = {};
  int? _measureA;
  int? _measureB;

  List<JsonMap> _allTransactions = [];
  Map<String, DoubleMap> _yahooHistories = {};
  Map<String, DoubleMap> _yahooIntraday = {};
  Map<String, DoubleMap> _manualHistories = {}; // NEW
  Map<String, String> _instrumentIsins = {};
  Map<String, JsonMap> _aferData = {};
  bool _isLoadingIntraday = false;

  List<JsonMap> _pieData = [];
  bool _isPieLoading = true;

  final List<Color> _pieColors = [
    Colors.greenAccent,
    Colors.blueAccent,
    Colors.orangeAccent,
    Colors.purpleAccent,
    Colors.redAccent,
    Colors.cyanAccent,
    Colors.pinkAccent,
    Colors.amberAccent,
    Colors.tealAccent,
    Colors.indigoAccent,
  ];

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  // ---------------------------------------------------------------
  // MESURE ENTRE DEUX POINTS
  // ---------------------------------------------------------------
  void _recomputeMeasure(double chartWidth, int count) {
    if (_pointers.length < 2 || count < 2) {
      _measureA = null;
      _measureB = null;
      return;
    }
    final plotW = chartWidth - _leftReserved;
    if (plotW <= 0) return;

    int toIndex(double dx) => (((dx - _leftReserved) / plotW) * (count - 1))
        .round()
        .clamp(0, count - 1)
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
  }

  Widget _buildMeasureBox() {
    final a = _measureA!, b = _measureB!;
    if (a >= _chartDataValue.length ||
        b >= _chartDataValue.length ||
        a >= _chartDataPercent.length ||
        b >= _chartDataPercent.length ||
        a >= _chartDates.length ||
        b >= _chartDates.length) {
      return const SizedBox();
    }

    final v1 = _chartDataValue[a].y, v2 = _chartDataValue[b].y;
    final p1 = _chartDataPercent[a].y, p2 = _chartDataPercent[b].y;

    final diffAbs = v2 - v1;
    // Performance cumulée entre A et B : on rapporte les deux
    // rendements cumulés depuis le début de la période.
    final pct = (1 + p1 / 100).abs() > 0.0001
        ? ((1 + p2 / 100) / (1 + p1 / 100) - 1) * 100
        : 0.0;

    final isPositive = _showPercent ? pct >= 0 : diffAbs >= 0;
    final color = isPositive ? Colors.greenAccent : Colors.redAccent;
    final signAbs = diffAbs >= 0 ? '+' : '';
    final signPct = pct >= 0 ? '+' : '';

    final intraday = _selectedPeriod == '1D' || _selectedPeriod == '1W';
    final fmt = DateFormat(intraday ? 'dd/MM HH:mm' : 'dd/MM/yyyy');
    final d1 = fmt.format(DateTime.parse(_chartDates[a]));
    final d2 = fmt.format(DateTime.parse(_chartDates[b]));

    final String line = _showPercent
        ? "$signPct${pct.toStringAsFixed(2)} %"
        : "$signAbs${diffAbs.toStringAsFixed(2)} €   ($signPct${pct.toStringAsFixed(2)} %)";

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
              line,
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

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        supabase.from('accounts').select('id, name').order('name'),
        supabase
            .from('transactions')
            .select('*, instruments(id, name, ticker_isin, account_id)')
            .order('date', ascending: true),
        supabase
            .from('daily_prices')
            .select('*, instruments(name)')
            .order('date', ascending: true),
      ]);
      final accountsData = results[0];
      final txData = results[1];
      _allTransactions = List<JsonMap>.from(txData);
      final dailyData = results[2];
      DoubleMap aferLatestPrices = {};
      for (var row in dailyData) {
        if (row['instruments'] != null) {
          aferLatestPrices[row['instruments']['name']] = (row['price'] as num)
              .toDouble();
        }
      }

      final instrumentsData = await supabase.from('instruments').select('*');

      final yahooFutures = <Future>[];
      for (var inst in instrumentsData) {
        String name = inst['name'];
        String isin = inst['ticker_isin'] ?? '';
        _instrumentIsins[name] = isin;
        if (name.startsWith('EPA:') || (isin.isNotEmpty && isin != 'CASH')) {
          yahooFutures.add(
            PriceService.fetchYahooHistory(name, isin: isin, range: '5y').then((
              hist,
            ) {
              if (hist.isNotEmpty) _yahooHistories[name] = hist;
            }),
          );
        }
      }
      await Future.wait(yahooFutures);

      // NEW : valeurs manuelles (fonds sans ISIN, etc.)
      _manualHistories = {};
      try {
        final manualRows = await supabase
            .from('manual_prices')
            .select('instrument_id, date, price')
            .order('date');
        final idToName = <String, String>{
          for (var inst in instrumentsData)
            inst['id'].toString(): inst['name'] as String,
        };
        for (var r in manualRows) {
          final n = idToName[r['instrument_id'].toString()];
          if (n == null) continue;
          (_manualHistories[n] ??= {})[r['date'].toString()] =
              (r['price'] as num).toDouble();
        }
      } catch (e) {}

      for (var inst in instrumentsData) {
        String name = inst['name'];

        if (!_yahooHistories.containsKey(name)) {
          var aferBuys = _allTransactions
              .where(
                (tx) =>
                    tx['instruments'] != null &&
                    tx['instruments']['name'] == name &&
                    (tx['transaction_type'] == 'Buy' ||
                        tx['transaction_type'] == 'Deposit'),
              )
              .toList();

          if (aferBuys.isNotEmpty) {
            aferBuys.sort((a, b) => a['date'].compareTo(b['date']));
            DateTime firstDate = DateTime.parse(
              aferBuys.first['date'].toString().split('T')[0],
            );

            double totalInv = 0.0;
            double totalQty = 0.0;
            for (var b in aferBuys) {
              double q = (b['quantity'] ?? 0).toDouble();
              double p = (b['unit_price'] ?? 0).toDouble();
              double fee = (b['fees'] ?? 0).toDouble();
              totalInv += (q * p) + fee;
              totalQty += q;
            }
            double pru = totalQty > 0.001 ? totalInv / totalQty : 0.0;
            double latest = aferLatestPrices[name] ?? pru;

            _aferData[name] = {
              'firstDate': firstDate,
              'pru': pru,
              'latestPrice': latest,
            };
          }
        }
      }

      final benchmarkData = await supabase
          .from('instruments')
          .select('id, name')
          .order('name');

      if (mounted) {
        setState(() {
          _accountsList = [
            {'id': 'ALL', 'name': 'Tous les comptes'},
            ...List<JsonMap>.from(accountsData),
          ];

          if (_selectedAccountId == null && _accountsList.isNotEmpty) {
            _selectedAccountId = 'ALL';
          }

          _benchmarkList = [
            {'id': 'NONE', 'name': 'Aucun Benchmark'},
            ...List<JsonMap>.from(benchmarkData),
          ];

          if (_selectedBenchmarkId == null) {
            _selectedBenchmarkId = 'NONE';
          }
        });

        _calculateChart();
        await _calculatePieData();
      }
    } catch (e) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double _interpolatedPrice(
    PriceEntryList hist,
    DateTime d,
    double fallbackPru,
  ) {
    if (hist.isEmpty) return fallbackPru;
    if (d.isBefore(hist.first.key)) return hist.first.value;
    if (!d.isBefore(hist.last.key)) return hist.last.value;

    int lo = 0, hi = hist.length - 1;
    while (lo < hi - 1) {
      int mid = (lo + hi) ~/ 2;
      if (hist[mid].key.isAfter(d)) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    final before = hist[lo];
    final after = hist[hi];
    final totalGapMs = after.key.difference(before.key).inMilliseconds;
    if (totalGapMs <= 0) return before.value;
    final progressMs = d.difference(before.key).inMilliseconds;
    final progress = progressMs / totalGapMs;
    return before.value + (after.value - before.value) * progress;
  }

  Future<void> _ensureIntradayLoaded() async {
    if (_yahooIntraday.isNotEmpty) return;

    setState(() => _isLoadingIntraday = true);

    final futures = <Future>[];
    for (var name in _yahooHistories.keys) {
      futures.add(
        PriceService.fetchYahooIntraday(
          name,
          isin: _instrumentIsins[name],
        ).then((hist) {
          if (hist.isNotEmpty) _yahooIntraday[name] = hist;
        }),
      );
    }
    await Future.wait(futures);

    if (mounted) setState(() => _isLoadingIntraday = false);
  }

  Future<double> _getCurrentPortfolioValue() async {
    try {
      List<JsonMap> filteredTx = _allTransactions;
      if (_selectedAccountId != null && _selectedAccountId != 'ALL') {
        filteredTx = _allTransactions
            .where(
              (tx) =>
                  tx['instruments'] != null &&
                  tx['instruments']['account_id'].toString() ==
                      _selectedAccountId,
            )
            .toList();
      }

      Map<String, JsonMap> tempPositions = {};

      for (var tx in filteredTx) {
        if (tx['instruments'] == null) continue;
        String name = tx['instruments']['name'];
        String isin = tx['instruments']['ticker_isin'] ?? '';
        String type = tx['transaction_type'];
        double qty = (tx['quantity'] ?? 0).toDouble();
        double price = (tx['unit_price'] ?? 0).toDouble();
        double fee = (tx['fees'] ?? 0).toDouble();

        if (!tempPositions.containsKey(name)) {
          tempPositions[name] = {
            'name': name,
            'isin': isin,
            'id': tx['instruments']['id'],
            'quantity': 0.0,
            'totalBoughtQty': 0.0,
            'totalInvested': 0.0,
          };
        }

        if (type == 'Buy' || type == 'Deposit') {
          tempPositions[name]!['quantity'] += qty;
          tempPositions[name]!['totalBoughtQty'] += qty;
          tempPositions[name]!['totalInvested'] += (qty * price) + fee;
        } else if (type == 'Sell') {
          double currentPru = tempPositions[name]!['totalBoughtQty'] > 0.001
              ? tempPositions[name]!['totalInvested'] /
                    tempPositions[name]!['totalBoughtQty']
              : 0.0;
          tempPositions[name]!['quantity'] -= qty;
          tempPositions[name]!['totalBoughtQty'] -= qty;
          tempPositions[name]!['totalInvested'] -= (qty * currentPru);
        }
      }

      double totalValue = 0.0;

      for (var pos in tempPositions.values) {
        if (pos['quantity'] <= 0.001) continue;
        if (pos['name'].toString().toLowerCase().contains('liquidit') ||
            pos['name'].toString().toUpperCase().contains('CASH')) {
          continue;
        }

        double pru = pos['totalBoughtQty'] > 0.001
            ? pos['totalInvested'] / pos['totalBoughtQty']
            : 0.0;

        double? livePrice = await PriceService.fetchLivePrice(
          pos['name'],
          pos['isin'],
          pos['id'],
        );

        double value = (livePrice != null && !livePrice.isNaN)
            ? livePrice * pos['quantity']
            : pru * pos['quantity'];

        if (value.isNaN || value <= 0) continue;

        totalValue += value;
      }

      return totalValue;
    } catch (e) {
      return 0.0;
    }
  }

  void _calculateChart() {
    if (_allTransactions.isEmpty) return;

    DateTime endDate = DateTime.now();
    DateTime startDate = endDate;

    List<JsonMap> filteredTx = _allTransactions;
    if (_selectedAccountId != 'ALL') {
      filteredTx = _allTransactions
          .where(
            (tx) =>
                tx['instruments'] != null &&
                tx['instruments']['account_id'].toString() ==
                    _selectedAccountId,
          )
          .toList();
    }

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
      if (filteredTx.isNotEmpty) {
        startDate = DateTime.parse(
          filteredTx.first['date'].toString().split('T')[0],
        );
        DateTime maxPast = endDate.subtract(const Duration(days: 365 * 10));
        if (startDate.isBefore(maxPast)) startDate = maxPast;
      } else {
        startDate = endDate.subtract(const Duration(days: 30));
      }
    }

    double divs = 0.0;
    for (var tx in filteredTx) {
      if (tx['transaction_type'] == 'Dividend') {
        DateTime txDate = DateTime.parse(tx['date'].toString().split('T')[0]);
        if (txDate.isAfter(startDate) || txDate.isAtSameMomentAs(startDate)) {
          divs += ((tx['quantity'] ?? 0) * (tx['unit_price'] ?? 1));
        }
      }
    }

    final Map<String, DoubleMap> histSource =
        ((_selectedPeriod == '1W' || _selectedPeriod == '1D') &&
            _yahooIntraday.isNotEmpty)
        ? _yahooIntraday
        : _yahooHistories;

    Map<String, PriceEntryList> sortedHistories = {};
    histSource.forEach((name, hist) {
      final entries =
          hist.entries
              .map((e) => MapEntry(DateTime.parse(e.key), e.value))
              .toList()
            ..sort((a, b) => a.key.compareTo(b.key));
      sortedHistories[name] = entries;
    });

    // NEW : les valeurs manuelles priment (et restent valables en 1D / 1W)
    _manualHistories.forEach((name, hist) {
      final entries =
          hist.entries
              .map((e) => MapEntry(DateTime.parse(e.key), e.value))
              .toList()
            ..sort((a, b) => a.key.compareTo(b.key));
      sortedHistories[name] = entries;
    });

    List<FlSpot> spotsValue = [];
    List<FlSpot> spotsPercent = [];
    List<FlSpot> spotsBenchmark = [];
    List<double> investedSeries = [];
    _chartDates.clear();

    int dayIndex = 0;

    String? benchName;
    if (_selectedBenchmarkId != 'NONE' && _selectedBenchmarkId != null) {
      try {
        benchName = _benchmarkList.firstWhere(
          (e) => e['id'].toString() == _selectedBenchmarkId,
        )['name'];
      } catch (e) {}
    }

    PriceEntryList? benchSortedHist = benchName != null
        ? sortedHistories[benchName]
        : null;
    JsonMap? benchAferInfo = benchName != null ? _aferData[benchName] : null;

    if (benchName != null &&
        (benchSortedHist == null || benchSortedHist.isEmpty) &&
        benchAferInfo == null) {
      benchName = null;
    }
    double? benchStartPrice;

    List<JsonMap> sortedTx = List<JsonMap>.from(filteredTx)
      ..sort((a, b) => a['date'].toString().compareTo(b['date'].toString()));

    Map<String, DoubleMap> instStats = {};
    double cumulativeRealizedGains = 0.0;
    int txPointer = 0;

    Duration chartStep;
    switch (_selectedPeriod) {
      case '1D':
        chartStep = const Duration(minutes: 15);
        break;
      case '1W':
        chartStep = const Duration(hours: 1);
        break;
      case '1M':
      case '3M':
      case 'YTD':
        chartStep = const Duration(days: 1);
        break;
      case '1A':
        chartStep = const Duration(days: 7);
        break;
      case 'ALL':
      default:
        int totalDays = endDate.difference(startDate).inDays;
        int stepDays = (totalDays / 45).ceil();
        if (stepDays < 1) stepDays = 1;
        chartStep = Duration(days: stepDays);
        break;
    }

    for (
      DateTime d = startDate;
      d.isBefore(endDate) || d.isAtSameMomentAs(endDate);
      d = d.add(chartStep)
    ) {
      if (_selectedPeriod == '1W' || _selectedPeriod == '1D') {
        if (d.hour < 9 || d.hour > 17) continue;
        if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
          continue;
        }
      } else if (chartStep.inDays == 1) {
        if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
          continue;
        }
      }
      String currentDateStr = chartStep.inHours < 24
          ? d.toIso8601String().substring(0, 16).replaceFirst('T', ' ')
          : d.toIso8601String().split('T')[0];

      while (txPointer < sortedTx.length) {
        final tx = sortedTx[txPointer];
        DateTime txDate = DateTime.parse(tx['date'].toString().split('T')[0]);
        if (txDate.isAfter(d)) break;

        if (tx['instruments'] != null) {
          String instName = tx['instruments']['name'];
          String type = tx['transaction_type'];
          double q = (tx['quantity'] ?? 0).toDouble();
          double p = (tx['unit_price'] ?? 0).toDouble();
          double fee = (tx['fees'] ?? 0).toDouble();

          if (!instStats.containsKey(instName)) {
            instStats[instName] = {
              'qty': 0.0,
              'boughtQty': 0.0,
              'invested': 0.0,
            };
          }

          if (type == 'Buy' || type == 'Deposit') {
            instStats[instName]!['qty'] = instStats[instName]!['qty']! + q;
            instStats[instName]!['boughtQty'] =
                instStats[instName]!['boughtQty']! + q;
            instStats[instName]!['invested'] =
                instStats[instName]!['invested']! + (q * p) + fee;
          } else if (type == 'Sell') {
            double currentPru = instStats[instName]!['boughtQty']! > 0.001
                ? instStats[instName]!['invested']! /
                      instStats[instName]!['boughtQty']!
                : 0.0;
            cumulativeRealizedGains += q * (p - currentPru) - fee;
            instStats[instName]!['qty'] = instStats[instName]!['qty']! - q;
            instStats[instName]!['boughtQty'] =
                instStats[instName]!['boughtQty']! - q;
            instStats[instName]!['invested'] =
                instStats[instName]!['invested']! - (q * currentPru);
          } else if (type == 'Dividend') {
            cumulativeRealizedGains += (q * p);
          }
        }
        txPointer++;
      }

      double dailyPortfolioValue = cumulativeRealizedGains;
      double dailyInvestedCapital = 0.0;

      instStats.forEach((instName, stats) {
        double qty = stats['qty']!;
        if (qty <= 0.001) return;

        if (instName.toLowerCase().contains('liquidit') ||
            instName.toUpperCase().contains('CASH')) {
          return;
        }

        double pru = stats['boughtQty']! > 0.001
            ? stats['invested']! / stats['boughtQty']!
            : 0.0;
        dailyInvestedCapital += (pru * qty);

        double price = pru;

        if (sortedHistories.containsKey(instName)) {
          price = _interpolatedPrice(sortedHistories[instName]!, d, pru);
        } else {
          var aferInfo = _aferData[instName];
          if (aferInfo != null) {
            DateTime firstDate = aferInfo['firstDate'];
            double globalPru = aferInfo['pru'];
            double latestPrice = aferInfo['latestPrice'];

            if (d.isBefore(firstDate) ||
                endDate.difference(firstDate).inDays <= 0) {
              price = globalPru;
            } else {
              int totalDays = endDate.difference(firstDate).inDays;
              int daysSinceFirst = d.difference(firstDate).inDays;
              price =
                  globalPru +
                  ((latestPrice - globalPru) * (daysSinceFirst / totalDays));
            }
          }
        }

        dailyPortfolioValue += (qty * price);
      });

      investedSeries.add(dailyInvestedCapital);
      spotsValue.add(FlSpot(dayIndex.toDouble(), dailyPortfolioValue));

      if (benchName != null) {
        double benchPrice;

        if (benchSortedHist != null && benchSortedHist.isNotEmpty) {
          benchPrice = _interpolatedPrice(
            benchSortedHist,
            d,
            benchSortedHist.first.value,
          );
        } else {
          double globalPru = benchAferInfo!['pru'];
          double latestPrice = benchAferInfo['latestPrice'];
          DateTime firstDate = benchAferInfo['firstDate'];

          if (d.isBefore(firstDate) ||
              endDate.difference(firstDate).inDays <= 0) {
            benchPrice = globalPru;
          } else {
            int totalDays = endDate.difference(firstDate).inDays;
            int daysSinceFirst = d.difference(firstDate).inDays;
            benchPrice =
                globalPru +
                ((latestPrice - globalPru) * (daysSinceFirst / totalDays));
          }
        }

        benchStartPrice ??= benchPrice;

        double benchPct = benchStartPrice > 0.001
            ? ((benchPrice - benchStartPrice) / benchStartPrice) * 100
            : 0.0;
        spotsBenchmark.add(FlSpot(dayIndex.toDouble(), benchPct));
      }

      _chartDates.add(currentDateStr);
      dayIndex++;
    }

    double startValue = spotsValue.isNotEmpty ? spotsValue.first.y : 0.0;
    double endValue = spotsValue.isNotEmpty ? spotsValue.last.y : 0.0;
    double startInvested = investedSeries.isNotEmpty
        ? investedSeries.first
        : 0.0;
    double endInvested = investedSeries.isNotEmpty ? investedSeries.last : 0.0;

    double netDeposits = endInvested - startInvested;
    double periodAbs = (endValue - startValue) - netDeposits;
    double periodPct = startValue > 0.001
        ? (periodAbs / startValue) * 100
        : (endInvested > 0 ? (periodAbs / endInvested) * 100 : 0.0);

    if (spotsValue.isNotEmpty) {
      double refValue = spotsValue.first.y;
      double refInvested = investedSeries.first;
      for (int i = 0; i < spotsValue.length; i++) {
        double val = spotsValue[i].y;
        double invested = investedSeries[i];
        double dayNetDeposits = invested - refInvested;
        double dayAbs = (val - refValue) - dayNetDeposits;
        double dayPct = refValue > 0.001
            ? (dayAbs / refValue) * 100
            : (refInvested > 0.001 ? (dayAbs / refInvested) * 100 : 0.0);
        spotsPercent.add(FlSpot(i.toDouble(), dayPct));
      }
    }

    setState(() {
      _clearMeasure();
      _totalDividends = divs;
      _chartDataValue = spotsValue;
      _chartDataPercent = spotsPercent;
      _chartDataBenchmark = spotsBenchmark;
      _periodPerformanceAbs = periodAbs;
      _periodPerformancePct = periodPct;
    });
  }

  Future<void> _calculatePieData() async {
    setState(() => _isPieLoading = true);

    List<JsonMap> filteredTx = _allTransactions;
    if (_selectedAccountId != null && _selectedAccountId != 'ALL') {
      filteredTx = _allTransactions
          .where(
            (tx) =>
                tx['instruments'] != null &&
                tx['instruments']['account_id'].toString() ==
                    _selectedAccountId,
          )
          .toList();
    }

    Map<String, JsonMap> tempPositions = {};

    for (var tx in filteredTx) {
      if (tx['instruments'] == null) continue;
      String name = tx['instruments']['name'];
      String isin = tx['instruments']['ticker_isin'] ?? '';
      String type = tx['transaction_type'];
      double qty = (tx['quantity'] ?? 0).toDouble();
      double price = (tx['unit_price'] ?? 0).toDouble();
      double fee = (tx['fees'] ?? 0).toDouble();

      if (!tempPositions.containsKey(name)) {
        tempPositions[name] = {
          'name': name,
          'isin': isin,
          'id': tx['instruments']['id'],
          'quantity': 0.0,
          'totalBoughtQty': 0.0,
          'totalInvested': 0.0,
        };
      }

      if (type == 'Buy' || type == 'Deposit') {
        tempPositions[name]!['quantity'] += qty;
        tempPositions[name]!['totalBoughtQty'] += qty;
        tempPositions[name]!['totalInvested'] += (qty * price) + fee;
      } else if (type == 'Sell') {
        double currentPru = tempPositions[name]!['totalBoughtQty'] > 0.001
            ? tempPositions[name]!['totalInvested'] /
                  tempPositions[name]!['totalBoughtQty']
            : 0.0;
        tempPositions[name]!['quantity'] -= qty;
        tempPositions[name]!['totalBoughtQty'] -= qty;
        tempPositions[name]!['totalInvested'] -= (qty * currentPru);
      }
    }

    List<JsonMap> slices = [];

    for (var pos in tempPositions.values) {
      if (pos['quantity'] <= 0.001) continue;
      if (pos['name'].toString().toLowerCase().contains('liquidit') ||
          pos['name'].toString().toUpperCase().contains('CASH')) {
        continue;
      }

      double pru = pos['totalBoughtQty'] > 0.001
          ? pos['totalInvested'] / pos['totalBoughtQty']
          : 0.0;

      double? livePrice = await PriceService.fetchLivePrice(
        pos['name'],
        pos['isin'],
        pos['id'],
      );

      double value = (livePrice != null && !livePrice.isNaN)
          ? livePrice * pos['quantity']
          : pru * pos['quantity'];

      if (value.isNaN || value <= 0) continue;

      slices.add({'name': pos['name'], 'value': value});
    }

    slices.sort(
      (a, b) => (b['value'] as double).compareTo(a['value'] as double),
    );

    double total = slices.fold(0.0, (sum, s) => sum + (s['value'] as double));

    for (int i = 0; i < slices.length; i++) {
      slices[i]['color'] = _pieColors[i % _pieColors.length];
      slices[i]['percent'] = total > 0.001
          ? (slices[i]['value'] / total) * 100
          : 0.0;
    }

    if (mounted) {
      setState(() {
        _currentPortfolioValue = total;
        _pieData = slices;
        _isPieLoading = false;
      });
    }
  }

  String get _selectedBenchmarkName {
    try {
      return _benchmarkList.firstWhere(
        (e) => e['id'].toString() == _selectedBenchmarkId,
      )['name'];
    } catch (e) {
      return 'Aucun Benchmark';
    }
  }

  void _showBenchmarkPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  "Choisir un benchmark",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _benchmarkList.length,
                  itemBuilder: (context, index) {
                    final b = _benchmarkList[index];
                    final bool selected =
                        b['id'].toString() == _selectedBenchmarkId;
                    return ListTile(
                      title: Text(
                        b['name'],
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      trailing: selected
                          ? const Icon(Icons.check, color: Colors.greenAccent)
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedBenchmarkId = b['id'].toString();
                        });
                        Navigator.pop(context);
                        _calculateChart();
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    List<FlSpot> activeChartData = _showPercent
        ? _chartDataPercent
        : _chartDataValue;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Performance',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : SingleChildScrollView(
              // Bloque le scroll vertical pendant la mesure à deux doigts
              physics: _pointers.length >= 2
                  ? const NeverScrollableScrollPhysics()
                  : null,
              child: Column(
                children: [
                  Container(
                    color: Colors.black,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: _showBenchmarkPicker,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _selectedBenchmarkId != 'NONE'
                                  ? Colors.purpleAccent.withOpacity(0.15)
                                  : Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _selectedBenchmarkId != 'NONE'
                                    ? Colors.purpleAccent
                                    : Colors.white24,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.compare_arrows,
                                  size: 16,
                                  color: _selectedBenchmarkId != 'NONE'
                                      ? Colors.purpleAccent
                                      : Colors.white54,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _selectedBenchmarkId != 'NONE'
                                      ? _selectedBenchmarkName
                                      : "Benchmark",
                                  style: TextStyle(
                                    color: _selectedBenchmarkId != 'NONE'
                                        ? Colors.purpleAccent
                                        : Colors.white54,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),
                  Container(
                    color: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 0,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1C1C1E),
                        value: _selectedAccountId,
                        icon: const Icon(
                          Icons.keyboard_arrow_down,
                          color: Colors.white,
                        ),
                        items: _accountsList.map((acc) {
                          return DropdownMenuItem<String>(
                            value: acc['id'].toString(),
                            child: Text(
                              acc['name'],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() => _selectedAccountId = value);
                          _calculateChart();
                          _calculatePieData();
                        },
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    color: const Color.fromARGB(255, 30, 30, 30),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(
                          "${_currentPortfolioValue.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]} ').replaceFirst('.', ',')} €",
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _periodPerformanceAbs >= 0
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward,
                              color: _periodPerformanceAbs >= 0
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
                              size: 20,
                            ),
                            Text(
                              "${_periodPerformanceAbs >= 0 ? '+' : ''}${_periodPerformanceAbs.toStringAsFixed(2)} € (${_periodPerformancePct >= 0 ? '+' : ''}${_periodPerformancePct.toStringAsFixed(2)}%)",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _periodPerformanceAbs >= 0
                                    ? Colors.greenAccent
                                    : Colors.redAccent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: () => setState(() {
                                _showPercent = false;
                                _clearMeasure();
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: !_showPercent
                                      ? Colors.white30
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white30),
                                ),
                                child: Text(
                                  "Valeur (€)",
                                  style: TextStyle(
                                    color: !_showPercent
                                        ? Colors.white
                                        : Colors.white30,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: () => setState(() {
                                _showPercent = true;
                                _clearMeasure();
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: _showPercent
                                      ? Colors.white30
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white30),
                                ),
                                child: Text(
                                  "Profit (%)",
                                  style: TextStyle(
                                    color: _showPercent
                                        ? Colors.white
                                        : Colors.white30,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            "Dividendes encaissés : ${_totalDividends.toStringAsFixed(2)} €",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 300,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        right: 20,
                        left: 10,
                        bottom: 20,
                      ),
                      child: _isLoadingIntraday
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            )
                          : activeChartData.isEmpty
                          ? const Center(
                              child: Text(
                                "Pas de données sur cette période",
                                style: TextStyle(color: Colors.white54),
                              ),
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final w = constraints.maxWidth;
                                final count = activeChartData.length;

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
                                  if (_pointers.length < 2 && before < 2) {
                                    return;
                                  }
                                  setState(() => _recomputeMeasure(w, count));
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
                                            getDrawingHorizontalLine: (value) =>
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
                                                reservedSize: 30,
                                                interval:
                                                    (activeChartData.length / 5)
                                                            .ceilToDouble() ==
                                                        0
                                                    ? 1
                                                    : (activeChartData.length /
                                                              5)
                                                          .ceilToDouble(),
                                                getTitlesWidget: (value, meta) {
                                                  int index = value.toInt();
                                                  if (index >= 0 &&
                                                      index <
                                                          _chartDates.length) {
                                                    DateTime d = DateTime.parse(
                                                      _chartDates[index],
                                                    );
                                                    String day = d.day
                                                        .toString()
                                                        .padLeft(2, '0');
                                                    String month = d.month
                                                        .toString()
                                                        .padLeft(2, '0');

                                                    if (_selectedPeriod ==
                                                        '1D') {
                                                      String hour = d.hour
                                                          .toString()
                                                          .padLeft(2, '0');
                                                      String min = d.minute
                                                          .toString()
                                                          .padLeft(2, '0');
                                                      return Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              top: 8.0,
                                                            ),
                                                        child: Text(
                                                          '$hour:$min',
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .white54,
                                                                fontSize: 11,
                                                              ),
                                                        ),
                                                      );
                                                    }

                                                    if (_selectedPeriod ==
                                                            'ALL' ||
                                                        _selectedPeriod ==
                                                            '1A') {
                                                      return Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              top: 8.0,
                                                            ),
                                                        child: Text(
                                                          '$month/${d.year.toString().substring(2)}',
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .white54,
                                                                fontSize: 11,
                                                              ),
                                                        ),
                                                      );
                                                    }

                                                    return Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            top: 8.0,
                                                          ),
                                                      child: Text(
                                                        '$day/$month',
                                                        style: const TextStyle(
                                                          color: Colors.white54,
                                                          fontSize: 11,
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
                                                getTitlesWidget: (value, meta) {
                                                  if (_showPercent) {
                                                    return Text(
                                                      '${value.toInt()}%',
                                                      style: const TextStyle(
                                                        color: Colors.white54,
                                                        fontSize: 11,
                                                      ),
                                                    );
                                                  } else {
                                                    return Text(
                                                      '${value.toInt()} €',
                                                      style: const TextStyle(
                                                        color: Colors.white54,
                                                        fontSize: 11,
                                                      ),
                                                    );
                                                  }
                                                },
                                              ),
                                            ),
                                          ),
                                          borderData: FlBorderData(show: false),
                                          extraLinesData: ExtraLinesData(
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
                                            touchTooltipData: LineTouchTooltipData(
                                              getTooltipItems: (touchedSpots) {
                                                String formattedDate = "";
                                                if (touchedSpots.isNotEmpty) {
                                                  int index = touchedSpots
                                                      .first
                                                      .x
                                                      .toInt();
                                                  if (index <
                                                      _chartDates.length) {
                                                    DateTime parsedDate =
                                                        DateTime.parse(
                                                          _chartDates[index],
                                                        );
                                                    formattedDate = DateFormat(
                                                      'dd/MM/yyyy',
                                                    ).format(parsedDate);
                                                  }
                                                }

                                                return touchedSpots.map((spot) {
                                                  bool isBenchmark =
                                                      spot.barIndex == 1;
                                                  bool isFirst =
                                                      spot ==
                                                      touchedSpots.first;

                                                  String valStr = _showPercent
                                                      ? "${spot.y > 0 ? '+' : ''}${spot.y.toStringAsFixed(2)} %"
                                                      : "${spot.y.toStringAsFixed(2)} €";

                                                  Color valueColor;
                                                  if (isBenchmark) {
                                                    valueColor =
                                                        Colors.purpleAccent;
                                                  } else {
                                                    valueColor =
                                                        _periodPerformanceAbs >=
                                                            0
                                                        ? Colors.greenAccent
                                                        : Colors.redAccent;
                                                  }

                                                  List<TextSpan> children = [];

                                                  if (isFirst) {
                                                    children.add(
                                                      TextSpan(
                                                        text:
                                                            "$formattedDate\n",
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    );
                                                  }

                                                  children.add(
                                                    TextSpan(
                                                      text: valStr,
                                                      style: TextStyle(
                                                        color: valueColor,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  );

                                                  return LineTooltipItem(
                                                    '',
                                                    const TextStyle(),
                                                    children: children,
                                                  );
                                                }).toList();
                                              },
                                            ),
                                          ),
                                          lineBarsData: [
                                            LineChartBarData(
                                              spots: activeChartData,
                                              isCurved: false,
                                              color: _periodPerformanceAbs >= 0
                                                  ? Colors.greenAccent
                                                  : Colors.redAccent,
                                              barWidth: 2,
                                              isStrokeCapRound: true,
                                              dotData: FlDotData(
                                                show:
                                                    _measureA != null &&
                                                    _measureB != null,
                                                checkToShowDot:
                                                    (spot, barData) {
                                                      final index = spot.x
                                                          .toInt();

                                                      return index ==
                                                              _measureA ||
                                                          index == _measureB;
                                                    },
                                                getDotPainter:
                                                    (
                                                      spot,
                                                      percent,
                                                      barData,
                                                      index,
                                                    ) {
                                                      return FlDotCirclePainter(
                                                        radius: 5,
                                                        color:
                                                            _periodPerformanceAbs >=
                                                                0
                                                            ? Colors.greenAccent
                                                            : Colors.redAccent,
                                                        strokeWidth: 2,
                                                        strokeColor:
                                                            Colors.white,
                                                      );
                                                    },
                                              ),
                                              belowBarData: BarAreaData(
                                                show: true,
                                                color:
                                                    (_periodPerformanceAbs >= 0
                                                            ? Colors.greenAccent
                                                            : Colors.redAccent)
                                                        .withOpacity(0.1),
                                              ),
                                            ),
                                            if (_showPercent &&
                                                _chartDataBenchmark.isNotEmpty)
                                              LineChartBarData(
                                                spots: _chartDataBenchmark,
                                                isCurved: false,
                                                color: Colors.purpleAccent,
                                                barWidth: 2,
                                                isStrokeCapRound: true,
                                                dotData: FlDotData(
                                                  show:
                                                      _measureA != null &&
                                                      _measureB != null,
                                                  checkToShowDot:
                                                      (spot, barData) {
                                                        final index = spot.x
                                                            .toInt();

                                                        return index ==
                                                                _measureA ||
                                                            index == _measureB;
                                                      },
                                                  getDotPainter:
                                                      (
                                                        spot,
                                                        percent,
                                                        barData,
                                                        index,
                                                      ) {
                                                        return FlDotCirclePainter(
                                                          radius: 5,
                                                          color: Colors
                                                              .purpleAccent,
                                                          strokeWidth: 2,
                                                          strokeColor:
                                                              Colors.white,
                                                        );
                                                      },
                                                ),
                                                belowBarData: BarAreaData(
                                                  show: false,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (_measureA != null && _measureB != null)
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
                  Container(
                    color: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: _periods.map((period) {
                        final isSelected = _selectedPeriod == period;
                        return GestureDetector(
                          onTap: () async {
                            setState(() {
                              _selectedPeriod = period;
                              _clearMeasure();
                            });
                            if (period == '1W' || period == '1D') {
                              await _ensureIntradayLoaded();
                            }
                            _calculateChart();
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
                  const SizedBox(height: 24),
                  _buildPieChartSection(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildPieChartSection() {
    if (_isPieLoading) {
      return const Padding(
        padding: EdgeInsets.all(30),
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_pieData.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(30),
        child: Center(
          child: Text(
            "Aucune position sur ce compte",
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Répartition du portefeuille",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 50,
                sections: _pieData.map((slice) {
                  return PieChartSectionData(
                    color: slice['color'] as Color,
                    value: slice['value'] as double,
                    title:
                        "${(slice['percent'] as double).toStringAsFixed(0)}%",
                    radius: 60,
                    titleStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ..._pieData.map((slice) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: slice['color'] as Color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      slice['name'],
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                  Text(
                    "${(slice['value'] as double).toStringAsFixed(2)} €",
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    "${(slice['percent'] as double).toStringAsFixed(1)}%",
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
