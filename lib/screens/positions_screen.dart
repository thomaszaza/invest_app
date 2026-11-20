import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../utils/range_utils.dart';

class PositionsScreen extends StatefulWidget {
  const PositionsScreen({super.key});

  @override
  State<PositionsScreen> createState() => _PositionsScreenState();
}

class _PositionsScreenState extends State<PositionsScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;

  List<JsonMap> _allPositions = [];
  List<JsonMap> _positions = [];
  List<String> _accounts = ['Tous les comptes'];
  String _selectedAccount = 'Tous les comptes';

  double _totalPortfolioValue = 0.0;
  double _totalInvestedValue = 0.0;

  // Plage de performance : par défaut vs PRU
  String _perfRange = PerfRange.pru;
  Map<String, double> _refPrices = {};

  @override
  void initState() {
    super.initState();
    _loadPositions();
  }

  Future<void> _loadReferences() async {
    if (_perfRange == PerfRange.pru || _allPositions.isEmpty) return;
    final requested = _perfRange;
    final refs = await HistoricalPrices.fetch(
      supabase,
      _allPositions,
      requested,
    );
    if (mounted && requested == _perfRange) {
      setState(() => _refPrices = refs);
    }
  }

  void _filterPositions() {
    double newInvested = 0.0;
    double newGlobal = 0.0;
    List<JsonMap> filtered = [];

    for (var pos in _allPositions) {
      if (_selectedAccount == 'Tous les comptes' ||
          pos['account'] == _selectedAccount) {
        filtered.add(pos);
        if (!pos['pru'].isNaN && !pos['quantity'].isNaN) {
          newInvested += (pos['pru'] * pos['quantity']);
          newGlobal += pos['totalValue'];
        }
      }
    }

    filtered.sort(
      (a, b) =>
          (b['totalValue'] as double).compareTo(a['totalValue'] as double),
    );

    setState(() {
      _positions = filtered;
      _totalInvestedValue = newInvested.isNaN ? 0.0 : newInvested;
      _totalPortfolioValue = newGlobal.isNaN ? 0.0 : newGlobal;
    });
  }

  Future<void> _loadPositions() async {
    setState(() => _isLoading = true);

    try {
      final viewData = await supabase.from('portfolio_view').select('*');

      List<JsonMap> validPositions = [];
      Set<String> foundAccounts = {'Tous les comptes'};

      for (var row in viewData) {
        String nameStr = row['name'].toString().toLowerCase();

        if (!nameStr.contains('liquidit') && !nameStr.contains('cash')) {
          double qty = (row['quantity'] ?? 0).toDouble();
          double pru = (row['pru'] ?? 0).toDouble();
          String accountName = row['account_name'] ?? 'Autre';

          foundAccounts.add(accountName);

          JsonMap pos = {
            'id': row['id'],
            'name': row['name'],
            'isin': row['isin'] ?? '',
            'category': row['category'],
            'comment': row['comment'],
            'account': accountName,
            'quantity': qty,
            'pru': pru,
            'currentPrice': null,
            'totalValue': pru * qty,
          };

          validPositions.add(pos);
        }
      }

      if (mounted) {
        _accounts = foundAccounts.toList();
        _allPositions = validPositions;
        _filterPositions();
        setState(() => _isLoading = false);
      }

      _loadReferences();

      List<FutureVoid> fetchFutures = _allPositions.map((pos) async {
        try {
          double? livePrice = await PriceService.fetchLivePrice(
            pos['name'],
            pos['isin'],
            pos['id'],
          );

          if (livePrice != null && !livePrice.isNaN) {
            double oldTotalValue = pos['totalValue'];
            double newTotalValue = livePrice * pos['quantity'];

            await AlertsService.checkAlerts(pos, livePrice);

            if (mounted) {
              setState(() {
                pos['currentPrice'] = livePrice;
                pos['totalValue'] = newTotalValue;

                // Correctif : 'Tous' ne correspondait jamais
                if (_selectedAccount == 'Tous les comptes' ||
                    _selectedAccount == pos['account']) {
                  _totalPortfolioValue =
                      _totalPortfolioValue - oldTotalValue + newTotalValue;
                }
              });
            }
          }
        } catch (e) {}
      }).toList();

      await Future.wait(fetchFutures);

      if (mounted) _filterPositions();
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showFeedbackDialog(BuildContext context) {
    final TextEditingController feedbackController = TextEditingController();
    String feedbackType = 'Bug';
    bool isSending = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          title: const Text(
            "Signaler un bug / suggestion",
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        "Bug",
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                      value: 'Bug',
                      groupValue: feedbackType,
                      onChanged: (v) => setDialogState(() => feedbackType = v!),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        "Suggestion",
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                      value: 'Suggestion',
                      groupValue: feedbackType,
                      onChanged: (v) => setDialogState(() => feedbackType = v!),
                    ),
                  ),
                ],
              ),
              TextField(
                controller: feedbackController,
                maxLines: 4,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: "Décris le problème ou ton idée...",
                  hintStyle: TextStyle(color: Colors.white54),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSending ? null : () => Navigator.pop(context),
              style: TextButton.styleFrom(foregroundColor: Colors.blueAccent),
              child: const Text("Annuler"),
            ),
            TextButton(
              onPressed: isSending
                  ? null
                  : () async {
                      if (feedbackController.text.trim().isEmpty) return;
                      setDialogState(() => isSending = true);
                      try {
                        await Supabase.instance.client.functions.invoke(
                          'send_feedback',
                          body: {
                            'type': feedbackType,
                            'message': feedbackController.text.trim(),
                            'user_email':
                                Supabase
                                    .instance
                                    .client
                                    .auth
                                    .currentUser
                                    ?.email ??
                                'inconnu',
                          },
                        );
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "Merci, ton message a été envoyé !",
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => isSending = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text("Erreur d'envoi : $e"),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              child: isSending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.blueAccent,
                      ),
                    )
                  : const Text(
                      "Envoyer",
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

  @override
  Widget build(BuildContext context) {
    final bool pruMode = _perfRange == PerfRange.pru;
    double globalPerfPct = 0.0;
    double globalPerfAbs = 0.0;

    if (pruMode) {
      if (!_totalPortfolioValue.isNaN && !_totalInvestedValue.isNaN) {
        globalPerfAbs = _totalPortfolioValue - _totalInvestedValue;
        if (_totalInvestedValue > 0.001) {
          globalPerfPct = (globalPerfAbs / _totalInvestedValue) * 100;
        }
      }
    } else {
      double refValue = 0, curValue = 0;
      for (final pos in _positions) {
        final ref = _refPrices[pos['id'].toString()];
        final cur = pos['currentPrice'] as double?;
        if (ref == null || cur == null) continue;
        refValue += ref * pos['quantity'];
        curValue += cur * pos['quantity'];
      }
      globalPerfAbs = curValue - refValue;
      if (refValue > 0.001) globalPerfPct = globalPerfAbs / refValue * 100;
    }

    Color globalColor = globalPerfAbs >= 0
        ? Colors.greenAccent
        : Colors.redAccent;
    String globalSign = globalPerfAbs >= 0 ? "+" : "";

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'Positions',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 24,
          ),
        ),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined, color: Colors.white),
            tooltip: 'Signaler un bug / suggestion',
            onPressed: () => _showFeedbackDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AddTransactionScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 15,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Capital Actuel",
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "${_totalPortfolioValue.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]} ').replaceFirst('.', ',')} €",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.left,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    "$globalSign${globalPerfAbs.toStringAsFixed(2)} € ($globalSign${globalPerfPct.toStringAsFixed(2)}%)",
                                    style: TextStyle(
                                      color: globalColor,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  pruMode ? "vs PRU" : "sur $_perfRange",
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedAccount,
                            dropdownColor: const Color(0xFF2C2C2E),
                            icon: const Icon(
                              Icons.arrow_drop_down,
                              color: Colors.white,
                            ),
                            isExpanded: false,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            items: _accounts.map((String account) {
                              return DropdownMenuItem<String>(
                                value: account,
                                child: Text(account),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              if (newValue != null &&
                                  newValue != _selectedAccount) {
                                setState(() => _selectedAccount = newValue);
                                _filterPositions();
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Sélecteur de plage sous la sélection de compte
                PerfRangeBar(
                  ranges: PerfRange.positionsRanges,
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
                  child: RefreshIndicator(
                    onRefresh: _loadPositions,
                    color: Colors.white,
                    backgroundColor: const Color(0xFF1C1C1E),
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      itemCount: _positions.length,
                      itemBuilder: (context, index) {
                        final pos = _positions[index];
                        final double? currentPrice = pos['currentPrice'];
                        final double pru = pos['pru'];
                        final double qty = pos['quantity'];

                        // Référence : PRU ou prix historique de la plage
                        final double? ref = pruMode
                            ? pru
                            : _refPrices[pos['id'].toString()];
                        double? perfPct;
                        double? perfAbs;
                        if (currentPrice != null &&
                            !currentPrice.isNaN &&
                            ref != null &&
                            ref > 0) {
                          perfPct = (currentPrice - ref) / ref * 100;
                          perfAbs = (currentPrice - ref) * qty;
                        }
                        final Color valueColor = perfPct == null
                            ? Colors.white
                            : (perfPct >= 0
                                  ? Colors.greenAccent
                                  : Colors.redAccent);

                        return Card(
                          color: const Color(0xFF1C1C1E),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          margin: const EdgeInsets.only(bottom: 6),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => InstrumentPager(
                                  instruments: _positions,
                                  initialIndex: index,
                                ),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
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
                                          pos['name'],
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          "Qté: ${qty.toStringAsFixed(2)}",
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 13,
                                          ),
                                        ),
                                        Text(
                                          "PRU: ${pru.toStringAsFixed(2)} €",
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 13,
                                          ),
                                        ),
                                        Text(
                                          currentPrice != null
                                              ? "Actuel: ${currentPrice.toStringAsFixed(2)} €"
                                              : "Non coté",
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        currentPrice != null
                                            ? "${pos['totalValue'].toStringAsFixed(2)} €"
                                            : "-- €",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: valueColor,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      // PRU = badge contour / plage = badge rempli
                                      PerfBadge(
                                        label: pruMode ? 'PRU' : _perfRange,
                                        pct: perfPct,
                                        filled: !pruMode,
                                      ),
                                      if (perfAbs != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          "${pruMode ? 'PV' : 'Δ'} : ${perfAbs >= 0 ? '+' : ''}${perfAbs.toStringAsFixed(2)} €",
                                          style: TextStyle(
                                            color: valueColor,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    icon: const Icon(
                                      Icons.notifications_none,
                                      color: Colors.white38,
                                      size: 20,
                                    ),
                                    onPressed: () =>
                                        showCreateAlertDialog(context, pos),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
