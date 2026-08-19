import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;



void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://pfzsgikdqpnbyhaokdwn.supabase.co',
    // ignore: deprecated_member_use
    anonKey: 'sb_publishable_owIZox6AqByWrqOiE_bbhQ_opZNPqaG',
  );

  runApp(const InvestApp());
}

class InvestApp extends StatelessWidget {
  const InvestApp({super.key});

  @override
  Widget build(BuildContext context) {
   return MaterialApp(
      title: 'ZaZa Invest',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.blueAccent,
        cardColor: const Color(0xFF1C1C1E),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        fontFamily: 'Helvetica Neue',
      ),
      // On met ton vrai écran d'accueil ici, sans le "const" pour éviter l'erreur !
      home: MainNavigationScreen(), 
    );
  }
}

// ==========================================
// 1. L'ÉCRAN PRINCIPAL (La barre de navigation)
// ==========================================
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const PositionsScreen(),
    const PerformanceScreen(),
    const PortfolioScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex], 
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        selectedItemColor: Colors.blueAccent,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt),
            label: 'Positions',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.show_chart),
            label: 'Performance',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.pie_chart),
            label: 'Portfolio',
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 2. LA PAGE "POSITIONS" (Accueil)
// ==========================================
class PositionsScreen extends StatefulWidget {
  const PositionsScreen({super.key});

  @override
  State<PositionsScreen> createState() => _PositionsScreenState();
}

class _PositionsScreenState extends State<PositionsScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _positions = [];
  
  double _totalPortfolioValue = 0.0;
  double _totalInvestedValue = 0.0; 

  @override
  void initState() {
    super.initState();
    _loadPositions();
  }

  Future<double?> _fetchLivePrice(String instrumentName, String isin, dynamic instrumentId) async {
    if (instrumentName.startsWith('EPA:')) {
      String yahooSymbol = '${instrumentName.replaceAll('EPA:', '')}.PA';
      final targetUrl = 'https://query1.finance.yahoo.com/v8/finance/chart/$yahooSymbol';
      final proxyUrl = Uri.parse('https://corsproxy.io/?${Uri.encodeComponent(targetUrl)}');
      try {
        final response = await http.get(proxyUrl);
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final price = data['chart']['result'][0]['meta']['regularMarketPrice'];
          double? finalPrice = (price as num).toDouble();
          if (finalPrice.isNaN) return null; // Sécurité anti-NaN
          return finalPrice;
        }
      } catch (e) {
        print("Erreur Yahoo pour $yahooSymbol : $e");
      }
      return null;
    } else if (isin.isNotEmpty) {
      final targetUrl = 'https://markets.ft.com/data/funds/tearsheet/summary?s=$isin:EUR';
      final proxyUrl = Uri.parse('https://corsproxy.io/?${Uri.encodeComponent(targetUrl)}');
      try {
        final response = await http.get(proxyUrl);
        if (response.statusCode == 200) {
          var document = parser.parse(response.body);
          var elements = document.querySelectorAll('.mod-ui-data-list__value');
          if (elements.isNotEmpty) {
            String cleanValue = elements[0].text.replaceAll(',', '').replaceAll(' ', '');
            double? price = double.tryParse(cleanValue);
            
            // Sécurité anti-NaN
            if (price != null && price.isNaN) {
              price = null;
            }

            if (price != null) {
              final today = DateTime.now().toIso8601String().split('T')[0];
              try {
                await supabase.from('daily_prices').upsert({'instrument_id': instrumentId, 'date': today, 'price': price});
              } catch (e) {}
            }
            return price;
          }
        }
      } catch (e) {}
    }
    return null;
  }

  Future<void> _loadPositions() async {
    setState(() => _isLoading = true);

    try {
      final txData = await supabase
          .from('transactions')
          .select('*, instruments(id, name, ticker_isin)')
          .order('date', ascending: true);

      Map<String, Map<String, dynamic>> tempPositions = {};

      for (var tx in txData) {
        if (tx['instruments'] == null) continue;
        String name = tx['instruments']['name'];
        String isin = tx['instruments']['ticker_isin'];
        String type = tx['transaction_type'];
        double qty = (tx['quantity'] ?? 0).toDouble();
        double price = (tx['unit_price'] ?? 0).toDouble();

        if (!tempPositions.containsKey(name)) {
          tempPositions[name] = {
            'name': name,
            'isin': isin,
            'id': tx['instruments']['id'],
            'quantity': 0.0,
            'totalBoughtQty': 0.0,
            'totalInvested': 0.0,
            'pru': 0.0,
          };
        }

        if (type == 'Buy' || type == 'Deposit') {
          tempPositions[name]!['quantity'] += qty;
          tempPositions[name]!['totalBoughtQty'] += qty;
          tempPositions[name]!['totalInvested'] += (qty * price);
        } else if (type == 'Sell') {
          tempPositions[name]!['quantity'] -= qty;
        }
      }

      List<Map<String, dynamic>> finalPositions = [];
      double totalGlobalValue = 0.0;
      double totalInvested = 0.0;

      for (var pos in tempPositions.values) {
        // CORRECTION : On ignore les "poussières" inférieures à 0.001 (les actions vendues à 100%)
        if (pos['quantity'] > 0.001) {
          
          // Sécurité anti division par zéro
          pos['pru'] = pos['totalBoughtQty'] > 0.001 ? (pos['totalInvested'] / pos['totalBoughtQty']) : 0.0;
          
          double? livePrice = await _fetchLivePrice(pos['name'], pos['isin'], pos['id']);
          pos['currentPrice'] = livePrice;
          
          if (livePrice != null && !livePrice.isNaN) {
            pos['totalValue'] = livePrice * pos['quantity'];
          } else {
            pos['totalValue'] = pos['pru'] * pos['quantity'];
          }
          
          // Sécurité ultime pour le total global
          if (!pos['totalValue'].isNaN) {
            totalGlobalValue += pos['totalValue'];
          }
          if (!pos['pru'].isNaN && !pos['quantity'].isNaN) {
            totalInvested += (pos['pru'] * pos['quantity']);
          }
          
          finalPositions.add(pos);
        }
      }

      finalPositions.sort((a, b) => (b['totalValue'] as double).compareTo(a['totalValue'] as double));

      if (mounted) {
        setState(() {
          _positions = finalPositions;
          _totalPortfolioValue = totalGlobalValue.isNaN ? 0.0 : totalGlobalValue;
          _totalInvestedValue = totalInvested.isNaN ? 0.0 : totalInvested;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Erreur Positions: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                
                ListTile(
                  leading: const CircleAvatar(backgroundColor: Color.fromARGB(255, 116, 114, 114), child: Icon(Icons.swap_horiz, color: Colors.white)),
                  title: const Text('Transaction', style: TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.pop(context);
                    final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const AddTransactionScreen()));
                    if (result == true) _loadPositions();
                  },
                ),
                ListTile(
                  leading: CircleAvatar(backgroundColor:Color.fromARGB(255, 116, 114, 114), child: const Icon(Icons.business_center, color: Colors.white)),
                  title: const Text('Instrument', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const AddInstrumentScreen()));
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(backgroundColor: Color.fromARGB(255, 116, 114, 114), child: Icon(Icons.account_balance, color: Colors.white)),
                  title: const Text('Compte', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const AddAccountScreen()));
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Calcul sécurisé de la progression globale
    double globalPerfPct = 0.0;
    double globalPerfAbs = 0.0;
    
    if (!_totalPortfolioValue.isNaN && !_totalInvestedValue.isNaN) {
      globalPerfAbs = _totalPortfolioValue - _totalInvestedValue;
      if (_totalInvestedValue > 0.001) {
        globalPerfPct = (globalPerfAbs / _totalInvestedValue) * 100;
      }
    }

    Color globalColor = globalPerfAbs >= 0 ? Colors.greenAccent : Colors.redAccent;
    String globalSign = globalPerfAbs >= 0 ? "+" : "";

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Positions', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadPositions)
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. La performance globale passe en premier tout en haut
                      Text(
                        "$globalSign${globalPerfAbs.toStringAsFixed(2)} € ($globalSign${globalPerfPct.toStringAsFixed(2)}%)", 
                        style: TextStyle(color: globalColor, fontSize: 18, fontWeight: FontWeight.bold)
                      ),
                      const SizedBox(height: 5),
                      // 2. Le capital total actuel passe juste en dessous en plus petit / discret
                      const Text("Capital Total Actuel", style: TextStyle(color: Colors.white54, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text("${_totalPortfolioValue.toStringAsFixed(2)} €", style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    itemCount: _positions.length,
                    itemBuilder: (context, index) {
                      final pos = _positions[index];
                      double currentPrice = pos['currentPrice'] ?? 0.0;
                      double pru = pos['pru'];
                      
                      Color valueColor = Colors.white;
                      String perfText = "";
                      
                      // Calcul sécurisé de la progression individuelle
                      if (currentPrice > 0 && pru > 0 && !currentPrice.isNaN && !pru.isNaN) {
                        double perfRatio = ((currentPrice - pru) / pru) * 100;
                        String sign = perfRatio >= 0 ? "+" : "";
                        perfText = " $sign${perfRatio.toStringAsFixed(2)}%";
                        
                        if (currentPrice > pru) valueColor = Colors.greenAccent;
                        else if (currentPrice < pru) valueColor = Colors.redAccent;
                      }

                      return Card(
                        color: const Color(0xFF1C1C1E),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(14.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(pos['name'], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                                    const SizedBox(height: 6),
                                    Text("Qté: ${pos['quantity'].toStringAsFixed(2)}", style: const TextStyle(color: Colors.white54, fontSize: 13)),
                                    Text("PRU: ${pru.toStringAsFixed(2)} €", style: const TextStyle(color: Colors.white54, fontSize: 13)),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    pos['currentPrice'] != null ? "${pos['totalValue'].toStringAsFixed(2)} €" : "-- €",
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: valueColor),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        pos['currentPrice'] != null ? "Actuel: ${currentPrice.toStringAsFixed(2)} €" : "Non coté",
                                        style: const TextStyle(color: Colors.white54, fontSize: 13),
                                      ),
                                      if (perfText.isNotEmpty)
                                        Text(
                                          perfText,
                                          style: TextStyle(color: valueColor, fontSize: 13, fontWeight: FontWeight.bold),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        onPressed: () => _showAddMenu(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}
// ==========================================
// 3. LA PAGE "PERFORMANCE"
// ==========================================

class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  
  String _selectedPeriod = '1M';
  final List<String> _periods = ['1S', '1M', '3M', 'YTD', '1A', 'ALL'];
  
  List<Map<String, dynamic>> _accountsList = [];
  String? _selectedAccountId;

  double _totalDividends = 0.0;
  double _periodPerformanceAbs = 0.0;
  double _periodPerformancePct = 0.0;
  double _currentPortfolioValue = 0.0;
  
  // NOUVEAU : Deux listes pour stocker les deux graphiques
  List<FlSpot> _chartDataValue = [];
  List<FlSpot> _chartDataPercent = [];
  bool _showPercent = false; // Permet de basculer entre Valeur et Profit
  
  List<String> _chartDates = []; 

  List<Map<String, dynamic>> _allTransactions = [];
  Map<String, Map<String, double>> _yahooHistories = {}; 
  Map<String, Map<String, dynamic>> _aferData = {}; 

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);

    try {
      final accountsData = await supabase.from('accounts').select('id, name').order('name');
      final txData = await supabase.from('transactions').select('*, instruments(id, name, ticker_isin)').order('date', ascending: true);
      _allTransactions = List<Map<String, dynamic>>.from(txData);

      final dailyData = await supabase.from('daily_prices').select('*, instruments(name)').order('date', ascending: true);
      Map<String, double> aferLatestPrices = {};
      for (var row in dailyData) {
        if (row['instruments'] != null) {
          aferLatestPrices[row['instruments']['name']] = (row['price'] as num).toDouble();
        }
      }

      final instrumentsData = await supabase.from('instruments').select('*');
      for (var inst in instrumentsData) {
        String name = inst['name'];
        if (name.startsWith('EPA:')) {
          _yahooHistories[name] = await _fetchYahooHistory(name);
        } else {
          var aferBuys = _allTransactions.where((tx) => tx['instruments'] != null && tx['instruments']['name'] == name && (tx['transaction_type'] == 'Buy' || tx['transaction_type'] == 'Deposit')).toList();
          
          if (aferBuys.isNotEmpty) {
            aferBuys.sort((a, b) => a['date'].compareTo(b['date']));
            DateTime firstDate = DateTime.parse(aferBuys.first['date'].toString().split('T')[0]);
            
            double totalInv = 0.0;
            double totalQty = 0.0;
            for (var b in aferBuys) {
              double q = (b['quantity'] ?? 0).toDouble();
              double p = (b['unit_price'] ?? 0).toDouble();
              totalInv += (q * p);
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

      if (mounted) {
        setState(() {
          _accountsList = [{'id': 'ALL', 'name': 'Tous les comptes'}, ...List<Map<String, dynamic>>.from(accountsData)];
          if (_selectedAccountId == null && _accountsList.isNotEmpty) {
            _selectedAccountId = 'ALL';
          }
        });
        _calculateChart(); 
      }
    } catch (e) {
      print("Erreur globale Perf: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<Map<String, double>> _fetchYahooHistory(String instrumentName) async {
    Map<String, double> history = {};
    String yahooSymbol = '${instrumentName.replaceAll('EPA:', '')}.PA';
    final targetUrl = 'https://query1.finance.yahoo.com/v8/finance/chart/$yahooSymbol?range=5y&interval=1d';
    final proxyUrl = Uri.parse('https://corsproxy.io/?${Uri.encodeComponent(targetUrl)}');

    try {
      final response = await http.get(proxyUrl);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final result = data['chart']['result'][0];
        List<dynamic> timestamps = result['timestamp'];
        List<dynamic> closePrices = result['indicators']['quote'][0]['close'];

        for (int i = 0; i < timestamps.length; i++) {
          if (closePrices[i] != null) {
            DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamps[i] * 1000);
            String dateString = date.toIso8601String().split('T')[0];
            history[dateString] = (closePrices[i] as num).toDouble();
          }
        }
      }
    } catch (e) {}
    return history;
  }

  void _calculateChart() {
    if (_allTransactions.isEmpty) return;

    DateTime endDate = DateTime.now();
    DateTime startDate = endDate;
    
    List<Map<String, dynamic>> filteredTx = _allTransactions;
    if (_selectedAccountId != 'ALL') {
      filteredTx = _allTransactions.where((tx) => tx['account_id'].toString() == _selectedAccountId).toList();
    }

    if (_selectedPeriod == '1S') startDate = endDate.subtract(const Duration(days: 7));
    else if (_selectedPeriod == '1M') startDate = endDate.subtract(const Duration(days: 30));
    else if (_selectedPeriod == '3M') startDate = endDate.subtract(const Duration(days: 90));
    else if (_selectedPeriod == '1A') startDate = endDate.subtract(const Duration(days: 365));
    else if (_selectedPeriod == 'YTD') startDate = DateTime(endDate.year, 1, 1);
    else if (_selectedPeriod == 'ALL') {
      if (filteredTx.isNotEmpty) {
        startDate = DateTime.parse(filteredTx.first['date'].toString().split('T')[0]);
        DateTime maxPast = endDate.subtract(const Duration(days: 365 * 5));
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

    List<FlSpot> spotsValue = [];
    List<FlSpot> spotsPercent = [];
    _chartDates.clear(); 
    
    double firstValue = 0.0;
    double lastValue = 0.0;
    int dayIndex = 0;

    for (DateTime d = startDate; d.isBefore(endDate) || d.isAtSameMomentAs(endDate); d = d.add(const Duration(days: 1))) {
      String currentDateStr = d.toIso8601String().split('T')[0];
      
      // NOUVEAU : Calcul du capital investi et de la valeur pour chaque jour
      Map<String, Map<String, double>> instStats = {};
      
      for (var tx in filteredTx) {
        DateTime txDate = DateTime.parse(tx['date'].toString().split('T')[0]);
        if (txDate.isAfter(d)) continue; 
        
        if (tx['instruments'] == null) continue;
        String instName = tx['instruments']['name'];
        String type = tx['transaction_type'];
        double q = (tx['quantity'] ?? 0).toDouble();
        double p = (tx['unit_price'] ?? 0).toDouble();

        if (!instStats.containsKey(instName)) {
          instStats[instName] = {'qty': 0.0, 'boughtQty': 0.0, 'invested': 0.0};
        }

        if (type == 'Buy' || type == 'Deposit') {
          instStats[instName]!['qty'] = instStats[instName]!['qty']! + q;
          instStats[instName]!['boughtQty'] = instStats[instName]!['boughtQty']! + q;
          instStats[instName]!['invested'] = instStats[instName]!['invested']! + (q * p);
        } else if (type == 'Sell') {
          instStats[instName]!['qty'] = instStats[instName]!['qty']! - q;
        }
      }

      double dailyPortfolioValue = 0.0;
      double dailyInvestedCapital = 0.0;

      instStats.forEach((instName, stats) {
        double qty = stats['qty']!;
        if (qty <= 0.001) return;
        
        // Calcul du PRU exact à ce jour précis
        double pru = stats['boughtQty']! > 0.001 ? stats['invested']! / stats['boughtQty']! : 0.0;
        dailyInvestedCapital += (pru * qty);

        double price = 0.0;
        if (instName.startsWith('EPA:')) {
          var hist = _yahooHistories[instName];
          if (hist != null) {
            for (int i = 0; i < 5; i++) {
              String lookbackDate = d.subtract(Duration(days: i)).toIso8601String().split('T')[0];
              if (hist.containsKey(lookbackDate)) {
                price = hist[lookbackDate]!;
                break;
              }
            }
          }
        } else {
          var aferInfo = _aferData[instName];
          if (aferInfo != null) {
            DateTime firstDate = aferInfo['firstDate'];
            double globalPru = aferInfo['pru'];
            double latestPrice = aferInfo['latestPrice'];
            
            if (d.isBefore(firstDate)) {
              price = globalPru;
            } else {
              int totalDays = endDate.difference(firstDate).inDays;
              if (totalDays <= 0) {
                price = globalPru;
              } else {
                int daysSinceFirst = d.difference(firstDate).inDays;
                price = globalPru + ((latestPrice - globalPru) * (daysSinceFirst / totalDays));
              }
            }
          }
        }
        
        dailyPortfolioValue += (qty * price);
      });

      // Calcul du pourcentage de profit ce jour-là
      double dailyPct = dailyInvestedCapital > 0.001 
          ? ((dailyPortfolioValue - dailyInvestedCapital) / dailyInvestedCapital) * 100 
          : 0.0;

      spotsValue.add(FlSpot(dayIndex.toDouble(), dailyPortfolioValue));
      spotsPercent.add(FlSpot(dayIndex.toDouble(), dailyPct));
      _chartDates.add(currentDateStr); 
      
      if (dayIndex == 0) firstValue = dailyPortfolioValue;
      lastValue = dailyPortfolioValue;
      dayIndex++;
    }

    setState(() {
      _totalDividends = divs;
      _currentPortfolioValue = lastValue.isNaN ? 0.0 : lastValue;
      _chartDataValue = spotsValue;
      _chartDataPercent = spotsPercent;
      _periodPerformanceAbs = lastValue - firstValue;
      _periodPerformancePct = firstValue > 0.001 ? (_periodPerformanceAbs / firstValue) * 100 : 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    // On sélectionne la liste de points à afficher en fonction du bouton choisi
    List<FlSpot> activeChartData = _showPercent ? _chartDataPercent : _chartDataValue;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Performance', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
          : Column(
              children: [
                Container(
                  color: Colors.black, 
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true, 
                      dropdownColor: const Color(0xFF1C1C1E), 
                      value: _selectedAccountId,
                      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.blueAccent),
                      items: _accountsList.map((acc) {
                        return DropdownMenuItem<String>(
                          value: acc['id'].toString(),
                          child: Text(acc['name'], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() => _selectedAccountId = value);
                        _calculateChart(); 
                      },
                    ),
                  ),
                ),

                Container(
                  width: double.infinity, 
                  color: const Color(0xFF1C1C1E), 
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text("${_currentPortfolioValue.toStringAsFixed(2)} €", style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _periodPerformanceAbs >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                            color: _periodPerformanceAbs >= 0 ? Colors.greenAccent : Colors.redAccent, size: 20,
                          ),
                          Text(
                            "${_periodPerformanceAbs >= 0 ? '+' : ''}${_periodPerformanceAbs.toStringAsFixed(2)} € (${_periodPerformancePct >= 0 ? '+' : ''}${_periodPerformancePct.toStringAsFixed(2)}%)",
                            style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold,
                              color: _periodPerformanceAbs >= 0 ? Colors.greenAccent : Colors.redAccent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Les boutons pour basculer entre Valeur et Profit
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: () => setState(() => _showPercent = false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              decoration: BoxDecoration(
                                color: !_showPercent ? Colors.blueAccent : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.blueAccent),
                              ),
                              child: Text("Valeur (€)", style: TextStyle(color: !_showPercent ? Colors.white : Colors.blueAccent, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () => setState(() => _showPercent = true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              decoration: BoxDecoration(
                                color: _showPercent ? Colors.blueAccent : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.blueAccent),
                              ),
                              child: Text("Profit (%)", style: TextStyle(color: _showPercent ? Colors.white : Colors.blueAccent, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                      
                      // LE RETOUR DE L'AFFICHAGE DES DIVIDENDES ICI :
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                        child: Text(
                          "Dividendes encaissés : ${_totalDividends.toStringAsFixed(2)} €",
                          style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 20, left: 10, bottom: 20),
                    child: activeChartData.isEmpty 
                    ? const Center(child: Text("Pas de données sur cette période", style: TextStyle(color: Colors.white54)))
                    : LineChart(
                      LineChartData(
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 1),
                        ),
                        titlesData: FlTitlesData(
                          show: true,
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 30,
                              interval: (activeChartData.length / 5).ceilToDouble() == 0 ? 1 : (activeChartData.length / 5).ceilToDouble(),
                              getTitlesWidget: (value, meta) {
                                int index = value.toInt();
                                if (index >= 0 && index < _chartDates.length) {
                                  DateTime d = DateTime.parse(_chartDates[index]);
                                  String day = d.day.toString().padLeft(2, '0');
                                  String month = d.month.toString().padLeft(2, '0');
                                  
                                  if (_selectedPeriod == 'ALL' || _selectedPeriod == '1A') {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text('$month/${d.year.toString().substring(2)}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                    );
                                  }
                                  
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text('$day/$month', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                  );
                                }
                                return const Text('');
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 50, 
                              getTitlesWidget: (value, meta) {
                                // NOUVEAU : Changement de l'axe Y selon le mode choisi
                                if (_showPercent) {
                                  return Text('${value.toInt()}%', style: const TextStyle(color: Colors.white54, fontSize: 11));
                                } else {
                                  return Text('${value.toInt()} €', style: const TextStyle(color: Colors.white54, fontSize: 11));
                                }
                              },
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipItems: (touchedSpots) {
                              return touchedSpots.map((spot) {
                                int index = spot.x.toInt();
                                String date = index < _chartDates.length ? _chartDates[index] : "";
                                // NOUVEAU : Changement de l'infobulle selon le mode choisi
                                String valStr = _showPercent
                                    ? "${spot.y > 0 ? '+' : ''}${spot.y.toStringAsFixed(2)} %"
                                    : "${spot.y.toStringAsFixed(2)} €";
                                    
                                return LineTooltipItem(
                                  "$date\n$valStr",
                                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                );
                              }).toList();
                            },
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: activeChartData,
                            isCurved: true,
                            color: _periodPerformanceAbs >= 0 ? Colors.greenAccent : Colors.redAccent,
                            barWidth: 2, 
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false), 
                            belowBarData: BarAreaData(
                              show: true,
                              color: (_periodPerformanceAbs >= 0 ? Colors.greenAccent : Colors.redAccent).withOpacity(0.1),
                            ),
                          ),
                        ],
                      ),
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
                        onTap: () {
                          setState(() => _selectedPeriod = period);
                          _calculateChart(); 
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF333333) : Colors.transparent,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Text(
                            period,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white54,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
    );
  }
}
// ==========================================
// 4. LA PAGE "PORTFOLIO" (Valeurs & Historique)
// ==========================================
class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _instruments = [];
  List<Map<String, dynamic>> _history = [];
  Map<String, double> _livePrices = {}; 
  Map<String, double> _ownedQuantities = {};

  @override
  void initState() {
    super.initState();
    _loadPortfolioData();
  }

  // Boîte de dialogue pour modifier une transaction existante
  Future<void> _showEditTransactionDialog(Map<String, dynamic> tx) async {
    final TextEditingController qtyController = TextEditingController(text: tx['quantity'].toString());
    final TextEditingController priceController = TextEditingController(text: tx['unit_price'].toString());
    
    DateTime selectedDate = DateTime.parse(tx['date'].toString().split('T')[0]);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          title: Text("Modifier la transaction", style: const TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Instrument : ${tx['instruments']?['name'] ?? 'Inconnu'}", style: const TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 15),
                // Modification de la date
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text("Date : ${selectedDate.toLocal().toString().split(' ')[0]}", style: const TextStyle(color: Colors.white)),
                  trailing: const Icon(Icons.calendar_today, color: Colors.blueAccent),
                  onTap: () async {
                    final DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        selectedDate = picked;
                      });
                    }
                  },
                ),
                const SizedBox(height: 10),
                // Modification de la quantité
                TextField(
                  controller: qtyController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "Quantité",
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
                  ),
                ),
                const SizedBox(height: 10),
                // Modification du prix unitaire
                TextField(
                  controller: priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "Prix unitaire (€)",
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
            TextButton(
              onPressed: () async {
                double? newQty = double.tryParse(qtyController.text.replaceAll(',', '.'));
                double? newPrice = double.tryParse(priceController.text.replaceAll(',', '.'));
                
                if (newQty != null && newPrice != null) {
                  await supabase.from('transactions').update({
                    'quantity': newQty,
                    'unit_price': newPrice,
                    'date': selectedDate.toIso8601String(),
                  }).eq('id', tx['id']);

                  Navigator.pop(context);
                  _loadPortfolioData(); // Recharge tout pour actualiser les graphiques et totaux
                }
              },
              child: const Text("Mettre à jour", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showManualPriceDialog(Map<String, dynamic> inst) async {
    final TextEditingController priceController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: Text("Prix manuel : ${inst['name']}", style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: priceController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Entrez le prix unitaire",
            hintStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
          TextButton(
            onPressed: () async {
              double? newPrice = double.tryParse(priceController.text.replaceAll(',', '.'));
              if (newPrice != null) {
                final today = DateTime.now().toIso8601String().split('T')[0];
                await supabase.from('daily_prices').upsert({
                  'instrument_id': inst['id'],
                  'date': today,
                  'price': newPrice,
                });
                Navigator.pop(context);
                _loadPortfolioData();
              }
            },
            child: const Text("Enregistrer", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<double?> _fetchLivePrice(String instrumentName, String isin, dynamic instrumentId) async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    final manualPrice = await supabase
        .from('daily_prices')
        .select('price')
        .eq('instrument_id', instrumentId)
        .eq('date', today)
        .maybeSingle();

    if (manualPrice != null) return (manualPrice['price'] as num).toDouble();

    if (instrumentName.startsWith('EPA:')) {
      String yahooSymbol = '${instrumentName.replaceAll('EPA:', '')}.PA';
      final targetUrl = 'https://query1.finance.yahoo.com/v8/finance/chart/$yahooSymbol';
      final proxyUrl = Uri.parse('https://corsproxy.io/?${Uri.encodeComponent(targetUrl)}');
      try {
        final response = await http.get(proxyUrl);
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final price = data['chart']['result'][0]['meta']['regularMarketPrice'];
          return (price as num).toDouble();
        }
      } catch (e) {}
    } else if (isin.isNotEmpty) {
      final targetUrl = 'https://markets.ft.com/data/funds/tearsheet/summary?s=$isin:EUR';
      final proxyUrl = Uri.parse('https://corsproxy.io/?${Uri.encodeComponent(targetUrl)}');
      try {
        final response = await http.get(proxyUrl);
        if (response.statusCode == 200) {
          var document = parser.parse(response.body);
          var elements = document.querySelectorAll('.mod-ui-data-list__value');
          if (elements.isNotEmpty) {
            String cleanValue = elements[0].text.replaceAll(',', '').replaceAll(' ', '');
            return double.tryParse(cleanValue);
          }
        }
      } catch (e) {}
    }
    return null;
  }

  Future<void> _loadPortfolioData() async {
    setState(() => _isLoading = true);
    try {
      final historyData = await supabase.from('transactions').select('*, instruments(name, ticker_isin), accounts(name)').order('date', ascending: false);
      final instrumentsData = await supabase.from('instruments').select('id, name, ticker_isin').order('name');

      Map<String, double> qtys = {};
      for (var tx in historyData) {
        if (tx['instruments'] == null) continue;
        String instName = tx['instruments']['name'];
        double qty = (tx['quantity'] ?? 0).toDouble();
        String type = tx['transaction_type'];
        if (!qtys.containsKey(instName)) qtys[instName] = 0.0;
        if (type == 'Buy' || type == 'Deposit') qtys[instName] = qtys[instName]! + qty;
        else if (type == 'Sell') qtys[instName] = qtys[instName]! - qty;
      }
      _ownedQuantities = qtys;

      Map<String, double> prices = {};
      for (var inst in instrumentsData) {
        double? livePrice = await _fetchLivePrice(inst['name'], inst['ticker_isin'], inst['id']); 
        if (livePrice != null) prices[inst['name']] = livePrice;
      }

      if (mounted) {
        setState(() {
          _history = List<Map<String, dynamic>>.from(historyData);
          _instruments = List<Map<String, dynamic>>.from(instrumentsData);
          _livePrices = prices;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Portfolio'),
          backgroundColor: Colors.black,
          bottom: const TabBar(
            labelColor: Colors.blueAccent,
            unselectedLabelColor: Colors.white54,
            indicatorColor: Colors.blueAccent,
            tabs: [Tab(text: 'Valeurs (Live)'), Tab(text: 'Historique')],
          ),
        ),
        body: _isLoading ? const Center(child: CircularProgressIndicator()) : TabBarView(
          children: [
            // --- ONGLET 1 : VALEURS ---
            ListView.builder(
              itemCount: _instruments.length,
            itemBuilder: (context, index) {
                final inst = _instruments[index];
                final ownedQty = _ownedQuantities[inst['name']] ?? 0.0;
                if (ownedQty <= 0) return const SizedBox.shrink();
                
                final currentPrice = _livePrices[inst['name']];

                return Card(
                  color: const Color(0xFF1C1C1E),
                  child: ListTile(
                    onTap: () => _showManualPriceDialog(inst),
                    title: Text(inst['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    trailing: Text(
                      currentPrice != null ? "${currentPrice.toStringAsFixed(2)} €" : "Non coté", 
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                );
              },
            ),
            // --- ONGLET 2 : HISTORIQUE (AVEC CLIC DE MODIFICATION) ---
            ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _history.length,
              itemBuilder: (context, index) {
                final tx = _history[index];
                return Card(
                  color: const Color(0xFF1C1C1E),
                  child: ListTile(
                    onTap: () => _showEditTransactionDialog(tx), // <-- Déclencheur de modification au clic !
                    title: Text(tx['instruments']?['name'] ?? 'Inconnu', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text("${tx['transaction_type']} • ${tx['date'].toString().split('T')[0]}", style: const TextStyle(color: Colors.white54)),
                    trailing: Text("${tx['quantity']} x ${tx['unit_price']} €", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
// ==========================================
// 5. LA PAGE D'AJOUT DE TRANSACTION
// ==========================================
class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  
  DateTime _selectedDate = DateTime.now();

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  String _selectedType = 'Buy';
  final List<String> _types = ['Buy', 'Sell', 'Dividend', 'Deposit', 'Withdrawal'];

  // Gestion des listes (Instruments et Comptes)
  List<Map<String, dynamic>> _instrumentsList = [];
  dynamic _selectedInstrumentId;
  
  List<Map<String, dynamic>> _accountsList = [];
  dynamic _selectedAccountId;
  
  bool _isLoadingData = true;

final _quantityController = TextEditingController();
  final _priceController = TextEditingController();
  final _feesController = TextEditingController(); // <-- LA LIGNE À AJOUTER
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadData(); // On charge maintenant les instruments ET les comptes
  }

  Future<void> _loadData() async {
    try {
      // 1. Charger les instruments
      final instrumentsData = await supabase
          .from('instruments')
          .select('id, name, ticker_isin')
          .order('name');

      // 2. Charger les comptes
      final accountsData = await supabase
          .from('accounts')
          .select('id, name')
          .order('name');

      if (!mounted) return;
      
      setState(() {
        // Remplir la liste des instruments
        _instrumentsList = List<Map<String, dynamic>>.from(instrumentsData);
        if (_instrumentsList.isNotEmpty) {
          _selectedInstrumentId = _instrumentsList.first['id'];
        }

        // Remplir la liste des comptes
        _accountsList = List<Map<String, dynamic>>.from(accountsData);
        if (_accountsList.isNotEmpty) {
          _selectedAccountId = _accountsList.first['id'];
        }

        _isLoadingData = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingData = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur de chargement: $e"), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _submitTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedInstrumentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner un instrument'), backgroundColor: Colors.red),
      );
      return;
    }
    if (_selectedAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner un compte'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // 1. C'est ICI qu'on prépare toutes nos variables (les "final" et les vérifications)
      // 1. C'est ICI qu'on prépare toutes nos variables (les "final" et les vérifications)
      final quantity = double.parse(_quantityController.text.replaceAll(',', '.'));
      final unitPrice = double.parse(_priceController.text.replaceAll(',', '.'));
      
      // On prépare les frais (0.0 par défaut si la case est vide)
      double fees = 0.0;
      if (_feesController.text.isNotEmpty) {
        fees = double.parse(_feesController.text.replaceAll(',', '.'));
      }

      await supabase.from('transactions').insert({
        'transaction_type': _selectedType,
        'instrument_id': _selectedInstrumentId,
        'account_id': _selectedAccountId, 
        'quantity': quantity,           // <-- On utilise enfin la variable !
        'unit_price': unitPrice,        // <-- On utilise enfin la variable !
        'fees': fees,                   // <-- On envoie les frais !
        'date': _selectedDate.toIso8601String(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaction enregistrée !'), backgroundColor: Colors.green),
      );

      Navigator.pop(context, true);
      
    } on PostgrestException catch (error) {
      print('🛑 ERREUR SUPABASE : ${error.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur BDD: ${error.message}'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      print('🛑 AUTRE ERREUR : $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nouvelle Transaction'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: _isLoadingData
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    // --- Date ---
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text("Date : ${_selectedDate.toLocal().toString().split(' ')[0]}"),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () => _selectDate(context),
                    ),
                    const SizedBox(height: 16),
                    
                    // --- Compte ---
                    DropdownButtonFormField<dynamic>(
                      value: _selectedAccountId,
                      decoration: const InputDecoration(
                        labelText: 'Compte',
                        border: OutlineInputBorder(),
                      ),
                      items: _accountsList.map((acc) {
                        return DropdownMenuItem(
                          value: acc['id'],
                          child: Text(acc['name']),
                        );
                      }).toList(),
                      onChanged: (value) => setState(() => _selectedAccountId = value),
                    ),
                    const SizedBox(height: 16),

                    // --- Type de transaction ---
                    DropdownButtonFormField<String>(
                      value: _selectedType,
                      decoration: const InputDecoration(
                        labelText: 'Type de transaction',
                        border: OutlineInputBorder(),
                      ),
                      items: _types.map((type) {
                        return DropdownMenuItem(value: type, child: Text(type));
                      }).toList(),
                      onChanged: (value) => setState(() => _selectedType = value!),
                    ),
                    const SizedBox(height: 16),
                    
                    // --- Instrument ---
                    DropdownButtonFormField<dynamic>(
                      value: _selectedInstrumentId,
                      decoration: const InputDecoration(
                        labelText: 'Instrument',
                        border: OutlineInputBorder(),
                      ),
                      items: _instrumentsList.map((inst) {
                        return DropdownMenuItem(
                          value: inst['id'],
                          child: Text("${inst['name']}"),
                        );
                      }).toList(),
                      onChanged: (value) => setState(() => _selectedInstrumentId = value),
                    ),
                    const SizedBox(height: 16),
                    
                    // --- Quantité ---
                    TextFormField(
                      controller: _quantityController,
                      decoration: const InputDecoration(
                        labelText: 'Quantité',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (val) => (val == null || val.isEmpty) ? 'Champ requis' : null,
                    ),
                    const SizedBox(height: 16),
                    
                   // --- Prix unitaire ---
                    TextFormField(
                      controller: _priceController,
                      decoration: const InputDecoration(
                        labelText: 'Prix unitaire (€)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (val) => (val == null || val.isEmpty) ? 'Champ requis' : null,
                    ),
                    const SizedBox(height: 16),

                    // --- Frais de courtage ---
                    TextFormField(
                      controller: _feesController,
                      decoration: const InputDecoration(
                        labelText: 'Frais de courtage (€)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 24),

                   

                    // --- Bouton Enregistrer ---
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _isSubmitting ? null : _submitTransaction,
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Enregistrer la transaction', style: TextStyle(fontSize: 16)),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}


// ==========================================
// 6. LA PAGE D'AJOUT DE COMPTE
// ==========================================
class AddAccountScreen extends StatefulWidget {
  const AddAccountScreen({super.key});

  @override
  State<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends State<AddAccountScreen> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _isSubmitting = false;

  Future<void> _submitAccount() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    try {
      await supabase.from('accounts').insert({
        'name': _nameController.text.trim(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compte créé avec succès !'), backgroundColor: Colors.green),
      );
      Navigator.pop(context); // Retour à l'écran précédent
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau Compte'), backgroundColor: Colors.white, foregroundColor: Colors.white),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nom du compte (ex: PEA, CTO...)', border: OutlineInputBorder()),
                validator: (val) => (val == null || val.isEmpty) ? 'Champ requis' : null,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white, foregroundColor: Colors.blueAccent,
                  minimumSize: const Size(double.infinity, 50),
                ),
                onPressed: _isSubmitting ? null : _submitAccount,
                child: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : const Text('Créer le compte'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 7. LA PAGE D'AJOUT D'INSTRUMENT
// ==========================================
class AddInstrumentScreen extends StatefulWidget {
  const AddInstrumentScreen({super.key});

  @override
  State<AddInstrumentScreen> createState() => _AddInstrumentScreenState();
}

class _AddInstrumentScreenState extends State<AddInstrumentScreen> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _tickerController = TextEditingController();
  bool _isSubmitting = false;

  Future<void> _submitInstrument() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    try {
      await supabase.from('instruments').insert({
        'name': _nameController.text.trim(),
        'ticker_isin': _tickerController.text.trim().toUpperCase(), // On force en majuscules
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Instrument ajouté avec succès !'), backgroundColor: Colors.green),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvel Instrument'), backgroundColor: Colors.white, foregroundColor: Colors.blueAccent),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nom (ex: LVMH, S&P 500)', border: OutlineInputBorder()),
                validator: (val) => (val == null || val.isEmpty) ? 'Champ requis' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _tickerController,
                decoration: const InputDecoration(labelText: 'Ticker ou ISIN (ex: MC.PA)', border: OutlineInputBorder()),
                validator: (val) => (val == null || val.isEmpty) ? 'Champ requis' : null,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white, foregroundColor: Colors.blueAccent,
                  minimumSize: const Size(double.infinity, 50),
                ),
                onPressed: _isSubmitting ? null : _submitInstrument,
                child: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : const Text('Ajouter l\'instrument'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
