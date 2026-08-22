import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const String supabaseUrl = 'https://pfzsgikdqpnbyhaokdwn.supabase.co';
const String supabaseAnonKey = 'sb_publishable_owIZox6AqByWrqOiE_bbhQ_opZNPqaG';
const List<String> kCategories = ['Croissance', 'Rendement', 'Opportunité'];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  await NotificationService.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zaza Invest',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      // L'aiguilleur central : vérifie si l'utilisateur est connecté
      home: const AuthGate(),
    );
  }
}

/// Widget qui écoute l'état de l'authentification en temps réel
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session =
            snapshot.data?.session ??
            Supabase.instance.client.auth.currentSession;

        if (session != null) {
          // Utilisateur connecté -> Envoi vers l'app principale
          return const MainNavigationScreen();
        } else {
          // Non connecté -> Envoi vers l'écran de connexion / inscription
          return const LoginScreen();
        }
      },
    );
  }
}

/// ==========================================
/// 1. ÉCRAN DE CONNEXION / INSCRIPTION
/// ==========================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _isLoading = false;
  bool _isSignUp = false;

  Future<void> _authenticate() async {
    setState(() => _isLoading = true);
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      if (_isSignUp) {
        await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Compte créé ! Vérifie tes emails si besoin ou connecte-toi.',
              ),
            ),
          );
        }
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Fond sombre cohérent avec l'app
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(
          _isSignUp ? 'Créer un compte' : 'Connexion',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo ou Titre stylisé
                  const Icon(
                    Icons.account_balance_wallet,
                    size: 64,
                    color: Colors.greenAccent,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Zaza Invest',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isSignUp
                        ? 'Inscris-toi pour suivre ton portefeuille'
                        : 'Bon retour ! Connecte-toi à ton espace',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                  ),
                  const SizedBox(height: 36),

                  // Champ Email
                  TextField(
                    controller: _emailController,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      labelStyle: TextStyle(color: Colors.grey[400]),
                      filled: true,
                      fillColor: Colors.grey[900],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.greenAccent,
                          width: 1.5,
                        ),
                      ),
                      prefixIcon: const Icon(
                        Icons.email_outlined,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Champ Mot de passe
                  TextField(
                    controller: _passwordController,
                    style: const TextStyle(color: Colors.white),
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      labelStyle: TextStyle(color: Colors.grey[400]),
                      filled: true,
                      fillColor: Colors.grey[900],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.greenAccent,
                          width: 1.5,
                        ),
                      ),
                      prefixIcon: const Icon(
                        Icons.lock_outline,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Bouton Valider
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _authenticate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.black,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              _isSignUp ? "Créer mon compte" : 'Se connecter',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Bouton bascule Inscription / Connexion
                  TextButton(
                    onPressed: () => setState(() => _isSignUp = !_isSignUp),
                    child: Text(
                      _isSignUp
                          ? 'Déjà un compte ? Connecte-toi'
                          : "Pas encore de compte ? Crée-en un",
                      style: const TextStyle(color: Colors.greenAccent),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// SERVICES PARTAGÉS
// ==========================================

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    try {
      await _plugin.initialize(settings);
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (e) {}
  }

  static Future<void> showAlert(int id, String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'price_alerts',
      'Alertes de prix',
      channelDescription: 'Notifications quand un seuil de prix est atteint',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );
    try {
      await _plugin.show(id, title, body, details);
    } catch (e) {
      print("Erreur notification: $e");
    }
  }
}

// Cache en mémoire pour éviter les requêtes réseau répétitives
class PriceCache {
  static final Map<String, double> _prices = {};
  static final Map<String, DateTime> _timestamps = {};
  static final Map<String, Map<String, double>> _histories = {};
  static final Map<String, DateTime> _historyTimestamps = {};

  static void set(String instrumentId, double price) {
    _prices[instrumentId] = price;
    _timestamps[instrumentId] = DateTime.now();
  }

  static double? get(String instrumentId) {
    if (_timestamps.containsKey(instrumentId) &&
        DateTime.now().difference(_timestamps[instrumentId]!).inMinutes < 15) {
      return _prices[instrumentId];
    }
    return null;
  }

  static void setHistory(String cacheKey, Map<String, double> history) {
    _histories[cacheKey] = history;
    _historyTimestamps[cacheKey] = DateTime.now();
  }

  static Map<String, double>? getHistory(String cacheKey) {
    if (_historyTimestamps.containsKey(cacheKey) &&
        DateTime.now().difference(_historyTimestamps[cacheKey]!).inHours < 6) {
      return _histories[cacheKey];
    }
    return null;
  }
}

class PriceService {
  static final supabase = Supabase.instance.client;

  static Future<double?> fetchLivePrice(
    String instrumentName,
    String isin,
    dynamic instrumentId,
  ) async {
    // 1. Vérifier le cache (si présent, retour immédiat)
    double? cached = PriceCache.get(instrumentId.toString());
    if (cached != null) return cached;

    // 2. Vérifier prix manuel dans Supabase
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final manual = await supabase
          .from('daily_prices')
          .select('price')
          .eq('instrument_id', instrumentId)
          .eq('date', today)
          .maybeSingle();
      if (manual != null) {
        final p = (manual['price'] as num).toDouble();
        if (!p.isNaN) {
          PriceCache.set(instrumentId.toString(), p);
          return p;
        }
      }
    } catch (e) {
      print("Erreur prix manuel : $e");
    }

    double? finalPrice;

    // 3. Logique Yahoo Finance / ISIN
    try {
      String symbol = "";
      if (instrumentName.startsWith('EPA:')) {
        symbol = '${instrumentName.replaceAll('EPA:', '')}.PA';
      } else if (isin.isNotEmpty && isin != 'CASH') {
        final targetSearchUrl =
            'https://query2.finance.yahoo.com/v1/finance/search?q=$isin';
        final searchUrl = Uri.parse(
          'https://corsproxy.io/?${Uri.encodeComponent(targetSearchUrl)}',
        );
        final searchResponse = await http.get(searchUrl);
        if (searchResponse.statusCode == 200) {
          final data = json.decode(searchResponse.body);
          if (data['quotes'] != null && data['quotes'].isNotEmpty) {
            symbol = data['quotes'][0]['symbol'];
          }
        }
      }

      if (symbol.isNotEmpty) {
        final targetChartUrl =
            'https://query1.finance.yahoo.com/v8/finance/chart/$symbol';
        final chartUrl = Uri.parse(
          'https://corsproxy.io/?${Uri.encodeComponent(targetChartUrl)}',
        );
        final response = await http.get(chartUrl);
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final price =
              data['chart']['result'][0]['meta']['regularMarketPrice'];
          finalPrice = (price as num).toDouble();
        }
      }
    } catch (e) {
      print("Erreur fetchLivePrice : $e");
    }

    // 4. Stocker dans le cache et retourner
    if (finalPrice != null && !finalPrice.isNaN) {
      PriceCache.set(instrumentId.toString(), finalPrice);
      return finalPrice;
    }

    return null;
  }

  static Future<Map<String, double>> fetchYahooHistory(
    String instrumentName, {
    String? isin,
    String range = 'max',
  }) async {
    final cacheKey = '${instrumentName}|${isin ?? ''}|$range';

    final cachedHistory = PriceCache.getHistory(cacheKey);
    if (cachedHistory != null && cachedHistory.isNotEmpty) {
      return cachedHistory;
    }

    Map<String, double> history = {};
    String? symbol;

    if (instrumentName.startsWith('EPA:')) {
      symbol = '${instrumentName.replaceAll('EPA:', '')}.PA';
    } else if (isin != null && isin.isNotEmpty && isin != 'CASH') {
      try {
        final searchUrl = Uri.parse(
          'https://corsproxy.io/?${Uri.encodeComponent('https://query2.finance.yahoo.com/v1/finance/search?q=$isin')}',
        );
        final res = await http.get(searchUrl);
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          if (data['quotes'] != null && data['quotes'].isNotEmpty) {
            symbol = data['quotes'][0]['symbol'];
          }
        }
      } catch (e) {}
    }

    if (symbol == null) return history;

    final targetUrl =
        'https://query1.finance.yahoo.com/v8/finance/chart/$symbol?range=$range&interval=1d';
    final proxyUrl = Uri.parse(
      'https://corsproxy.io/?${Uri.encodeComponent(targetUrl)}',
    );

    try {
      final response = await http.get(proxyUrl);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final result = data['chart']['result'][0];
        List<dynamic> timestamps = result['timestamp'];
        List<dynamic> closePrices = result['indicators']['quote'][0]['close'];

        for (int i = 0; i < timestamps.length; i++) {
          if (closePrices[i] != null) {
            DateTime date = DateTime.fromMillisecondsSinceEpoch(
              timestamps[i] * 1000,
            );
            history[date.toIso8601String().split('T')[0]] =
                (closePrices[i] as num).toDouble();
          }
        }
      }
    } catch (e) {
      print("Erreur historique: $e");
    }

    if (history.isNotEmpty) {
      PriceCache.setHistory(cacheKey, history);
    }

    return history;
  }
}

class AlertsService {
  static final supabase = Supabase.instance.client;

  static Future<void> checkAlerts(
    Map<String, dynamic> instrument,
    double? currentPrice,
  ) async {
    if (currentPrice == null || instrument['id'] == null) return;
    try {
      final alerts = await supabase
          .from('alerts')
          .select()
          .eq('instrument_id', instrument['id'])
          .eq('active', true)
          .eq('triggered', false);

      for (var alert in alerts) {
        double threshold = (alert['threshold_price'] as num).toDouble();
        String direction = alert['direction'];
        bool hit =
            (direction == 'above' && currentPrice >= threshold) ||
            (direction == 'below' && currentPrice <= threshold);
        if (hit) {
          await NotificationService.showAlert(
            (alert['id'] as num).toInt(),
            "Alerte : ${instrument['name']}",
            "Le prix a atteint ${currentPrice.toStringAsFixed(2)} € (seuil : ${threshold.toStringAsFixed(2)} €)",
          );
          await supabase
              .from('alerts')
              .update({'triggered': true})
              .eq('id', alert['id']);
        }
      }
    } catch (e) {
      print("Erreur vérification alertes: $e");
    }
  }

  static Future<void> createAlert(
    dynamic instrumentId,
    double threshold,
    String direction,
  ) async {
    await supabase.from('alerts').insert({
      'instrument_id': instrumentId,
      'threshold_price': threshold,
      'direction': direction,
      'active': true,
      'triggered': false,
    });
  }
}

void showCreateAlertDialog(
  BuildContext context,
  Map<String, dynamic> instrument,
) {
  final TextEditingController thresholdController = TextEditingController();
  String direction = 'above';
  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: Text(
          "Alerte : ${instrument['name']}",
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: thresholdController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Seuil de prix (€)",
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.blueAccent),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      "Au-dessus",
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    value: 'above',
                    groupValue: direction,
                    onChanged: (v) => setDialogState(() => direction = v!),
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      "En dessous",
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    value: 'below',
                    groupValue: direction,
                    onChanged: (v) => setDialogState(() => direction = v!),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Annuler"),
          ),
          TextButton(
            onPressed: () async {
              double? threshold = double.tryParse(
                thresholdController.text.replaceAll(',', '.'),
              );
              if (threshold != null && instrument['id'] != null) {
                await AlertsService.createAlert(
                  instrument['id'],
                  threshold,
                  direction,
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Alerte créée !"),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              }
            },
            child: const Text(
              "Créer l'alerte",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    ),
  );
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
    const WatchlistScreen(),
    const PerformanceScreen(),
    const PortfolioScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        backgroundColor: const Color.fromARGB(255, 26, 26, 26),
        unselectedItemColor: const Color.fromARGB(255, 141, 139, 139),
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        selectedItemColor: const Color.fromARGB(255, 255, 255, 255),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt),
            label: 'Positions',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.visibility),
            label: 'Watchlist',
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

  Future<void> _loadPositions() async {
    setState(() => _isLoading = true);

    try {
      final txData = await supabase
          .from('transactions')
          .select('*, instruments(id, name, ticker_isin, category, comment)')
          .order('date', ascending: true);

      Map<String, Map<String, dynamic>> tempPositions = {};

      for (var tx in txData) {
        if (tx['instruments'] == null) continue;
        String name = tx['instruments']['name'];
        String isin = tx['instruments']['ticker_isin'] ?? '';
        String type = tx['transaction_type'];
        double qty = (tx['quantity'] ?? 0).toDouble();
        double price = (tx['unit_price'] ?? 0).toDouble();

        if (!tempPositions.containsKey(name)) {
          tempPositions[name] = {
            'name': name,
            'isin': isin,
            'id': tx['instruments']['id'],
            'category': tx['instruments']['category'],
            'comment': tx['instruments']['comment'],
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
          // CORRECTION: Diminuer le total investi proportionnellement (correction PRU)
          double currentPru = tempPositions[name]!['totalBoughtQty'] > 0.001
              ? tempPositions[name]!['totalInvested'] /
                    tempPositions[name]!['totalBoughtQty']
              : 0.0;
          tempPositions[name]!['quantity'] -= qty;
          tempPositions[name]!['totalBoughtQty'] -= qty;
          tempPositions[name]!['totalInvested'] -= (qty * currentPru);
        }
      }

      List<Map<String, dynamic>> finalPositions = [];
      double totalGlobalValue = 0.0;
      double totalInvested = 0.0;

      for (var pos in tempPositions.values) {
        if (pos['quantity'] > 0.001) {
          // On ignore totalement le cash
          if (pos['name'].toString().toLowerCase().contains('liquidit') ||
              pos['name'].toString().toUpperCase().contains('CASH')) {
            continue;
          }

          pos['pru'] = pos['totalBoughtQty'] > 0.001
              ? (pos['totalInvested'] / pos['totalBoughtQty'])
              : 0.0;

          double? livePrice = await PriceService.fetchLivePrice(
            pos['name'],
            pos['isin'],
            pos['id'],
          );
          pos['currentPrice'] = livePrice;

          if (livePrice != null && !livePrice.isNaN) {
            pos['totalValue'] = livePrice * pos['quantity'];
          } else {
            pos['totalValue'] = pos['pru'] * pos['quantity'];
          }

          await AlertsService.checkAlerts(pos, livePrice);

          if (!pos['totalValue'].isNaN) {
            totalGlobalValue += pos['totalValue'];
          }
          if (!pos['pru'].isNaN && !pos['quantity'].isNaN) {
            totalInvested += (pos['pru'] * pos['quantity']);
          }

          finalPositions.add(pos);
        }
      }

      finalPositions.sort(
        (a, b) =>
            (b['totalValue'] as double).compareTo(a['totalValue'] as double),
      );

      if (mounted) {
        setState(() {
          _positions = finalPositions;
          _totalPortfolioValue = totalGlobalValue.isNaN
              ? 0.0
              : totalGlobalValue;
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color.fromARGB(255, 116, 114, 114),
                    child: Icon(Icons.swap_horiz, color: Colors.white),
                  ),
                  title: const Text(
                    'Transaction',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AddTransactionScreen(),
                      ),
                    );
                    if (result == true) _loadPositions();
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color.fromARGB(255, 116, 114, 114),
                    child: Icon(Icons.business_center, color: Colors.white),
                  ),
                  title: const Text(
                    'Instrument',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AddInstrumentScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color.fromARGB(255, 116, 114, 114),
                    child: Icon(Icons.account_balance, color: Colors.white),
                  ),
                  title: const Text(
                    'Compte',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AddAccountScreen(),
                      ),
                    );
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
    double globalPerfPct = 0.0;
    double globalPerfAbs = 0.0;

    if (!_totalPortfolioValue.isNaN && !_totalInvestedValue.isNaN) {
      globalPerfAbs = _totalPortfolioValue - _totalInvestedValue;
      if (_totalInvestedValue > 0.001) {
        globalPerfPct = (globalPerfAbs / _totalInvestedValue) * 100;
      }
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
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () => _showAddMenu(context),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 15,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Capital Total Actuel",
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "${_totalPortfolioValue.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]} ').replaceFirst('.', ',')} €",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "$globalSign${globalPerfAbs.toStringAsFixed(2)} € ($globalSign${globalPerfPct.toStringAsFixed(2)}%)",
                        style: TextStyle(
                          color: globalColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    itemCount: _positions.length,
                    itemBuilder: (context, index) {
                      final pos = _positions[index];
                      double currentPrice = pos['currentPrice'] ?? 0.0;
                      double pru = pos['pru'];

                      Color valueColor = Colors.white;
                      String perfText = "";

                      if (currentPrice > 0 &&
                          pru > 0 &&
                          !currentPrice.isNaN &&
                          !pru.isNaN) {
                        double perfRatio = ((currentPrice - pru) / pru) * 100;
                        String sign = perfRatio >= 0 ? "+" : "";
                        perfText = "$sign${perfRatio.toStringAsFixed(2)}%";

                        if (currentPrice > pru) {
                          valueColor = Colors.greenAccent;
                        } else if (currentPrice < pru) {
                          valueColor = Colors.redAccent;
                        }
                      }

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
                              builder: (context) =>
                                  InstrumentDetailScreen(instrument: pos),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                        "Qté: ${pos['quantity'].toStringAsFixed(2)}",
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
                                        pos['currentPrice'] != null
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
                                      pos['currentPrice'] != null
                                          ? "${pos['totalValue'].toStringAsFixed(2)} €"
                                          : "-- €",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: valueColor,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    if (perfText.isNotEmpty)
                                      Text(
                                        perfText,
                                        style: TextStyle(
                                          color: valueColor,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    if (currentPrice > 0 && pru > 0) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        "PV : ${((currentPrice - pru) * pos['quantity']) >= 0 ? '+' : ''}${((currentPrice - pru) * pos['quantity']).toStringAsFixed(2)} €",
                                        style: TextStyle(
                                          color: (currentPrice - pru) >= 0
                                              ? Colors.greenAccent
                                              : Colors.redAccent,
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
              ],
            ),
    );
  }
}

// ==========================================
// 2bis. LA PAGE "WATCHLIST"
// ==========================================
class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _watchlist = [];

  @override
  void initState() {
    super.initState();
    _loadWatchlist();
  }

  Future<void> _loadWatchlist() async {
    setState(() => _isLoading = true);
    final data = await supabase
        .from('instruments')
        .select('*')
        .eq('is_watchlist', true);

    List<Map<String, dynamic>> list = List<Map<String, dynamic>>.from(data);

    List<Future> futures = list.map((inst) async {
      String isin = inst['ticker_isin'] ?? '';
      double? price = await PriceService.fetchLivePrice(
        inst['name'],
        isin,
        inst['id'],
      );
      inst['currentPrice'] = price;
      inst['isin'] = isin;
    }).toList();

    await Future.wait(futures);

    if (mounted)
      setState(() {
        _watchlist = list;
        _isLoading = false;
      });
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
              borderSide: BorderSide(color: Colors.blueAccent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Annuler"),
          ),
          TextButton(
            onPressed: () async {
              double? newPrice = double.tryParse(
                priceController.text.replaceAll(',', '.'),
              );
              if (newPrice != null) {
                final today = DateTime.now().toIso8601String().split('T')[0];
                await supabase.from('daily_prices').upsert({
                  'instrument_id': inst['id'],
                  'date': today,
                  'price': newPrice,
                });
                Navigator.pop(context);
                _loadWatchlist();
              }
            },
            child: const Text(
              "Enregistrer",
              style: TextStyle(fontWeight: FontWeight.bold),
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
            color: Colors.white, // Remplace par la couleur de ton choix (ex: Colors.blue, Colors.white, etc.)
            fontSize: 24,
            fontWeight: FontWeight.bold,
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
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              itemCount: _watchlist.length,
              itemBuilder: (context, index) {
                final inst = _watchlist[index];
                double? price = inst['currentPrice'];

                return Card(
                  color: const Color(0xFF1C1C1E),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  margin: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              InstrumentDetailScreen(instrument: inst),
                        ),
                      );
                      _loadWatchlist();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  inst['name'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                                if ((inst['isin'] ?? '').toString().isNotEmpty)
                                  Text(
                                    inst['isin'],
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 13,
                                    ),
                                  ),
                                if ((inst['category'] ?? '')
                                    .toString()
                                    .isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      inst['category'],
                                      style: const TextStyle(
                                        color: Colors.blueAccent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                price != null
                                    ? "${price.toStringAsFixed(2)} €"
                                    : "Non coté",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.white38,
                                  size: 20,
                                ),
                                onPressed: () => _showManualPriceDialog(inst),
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
                                    showCreateAlertDialog(context, inst),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
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

// NOTE: garde tes imports existants (fl_chart, supabase_flutter, ton PriceService, etc.)
// Ce fichier reprend TA classe _PerformanceScreenState avec _calculateChart() corrigé.
// Le reste (initState, _loadAllData, build) est inchangé, tu peux remplacer
// directement la méthode _calculateChart dans ton fichier existant si tu préfères.

class _PerformanceScreenState extends State<PerformanceScreen> {
  List<Map<String, dynamic>> _benchmarkList = [];
  String? _selectedBenchmarkId;
  List<FlSpot> _chartDataBenchmark = [];

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

  List<FlSpot> _chartDataValue = [];
  List<FlSpot> _chartDataPercent = [];
  bool _showPercent = false;

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
      final accountsData = await supabase
          .from('accounts')
          .select('id, name')
          .order('name');
      final txData = await supabase
          .from('transactions')
          .select('*, instruments(id, name, ticker_isin)')
          .order('date', ascending: true);
      _allTransactions = List<Map<String, dynamic>>.from(txData);

      final dailyData = await supabase
          .from('daily_prices')
          .select('*, instruments(name)')
          .order('date', ascending: true);
      Map<String, double> aferLatestPrices = {};
      for (var row in dailyData) {
        if (row['instruments'] != null) {
          aferLatestPrices[row['instruments']['name']] = (row['price'] as num)
              .toDouble();
        }
      }

      final instrumentsData = await supabase.from('instruments').select('*');
      for (var inst in instrumentsData) {
        String name = inst['name'];
        String isin = inst['ticker_isin'] ?? '';

        if (name.startsWith('EPA:') || (isin.isNotEmpty && isin != 'CASH')) {
          var hist = await PriceService.fetchYahooHistory(name, isin: isin);
          if (hist.isNotEmpty) {
            _yahooHistories[name] = hist;
          }
        }

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

      final benchmarkData = await supabase
          .from('instruments')
          .select('id, name')
          .order('name');

      if (mounted) {
        setState(() {
          _accountsList = [
            {'id': 'ALL', 'name': 'Tous les comptes'},
            ...List<Map<String, dynamic>>.from(accountsData),
          ];
          if (_selectedAccountId == null && _accountsList.isNotEmpty) {
            _selectedAccountId = 'ALL';
          }

          _benchmarkList = [
            {'id': 'NONE', 'name': 'Aucun Benchmark'},
            ...List<Map<String, dynamic>>.from(benchmarkData),
          ];
          if (_selectedBenchmarkId == null) _selectedBenchmarkId = 'NONE';
        });
        _calculateChart();
      }
    } catch (e) {
      print("Erreur globale Perf: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------
  // MÉTHODE CORRIGÉE
  // ---------------------------------------------------------------------
  //
  // Bug #1 (créneaux) : l'ancien code ne regardait que 7 jours en arrière
  // pour trouver un prix Yahoo. Dès qu'un titre avait un trou de données
  // (jour férié, valeur peu liquide...) de plus de 7 jours, le prix
  // retombait brutalement sur le PRU, créant un "créneau" (chute puis
  // rebond) sur la courbe.
  //
  // Bug #2 (benchmark qui ne colle pas) : le prix de référence du
  // benchmark (base 100%) était calé, en cas de données manquantes le
  // premier jour, sur une valeur de repli arbitraire (1.0), ce qui
  // faussait tout le calcul en pourcentage et empêchait la courbe du
  // benchmark de se superposer à celle du portefeuille.
  //
  // Correctif : on trie une bonne fois l'historique de chaque titre et
  // on avance un pointeur jour après jour ("forward fill") : le prix
  // utilisé est toujours le DERNIER prix réellement connu, sans jamais
  // revenir en arrière sur le PRU une fois qu'une cotation a été
  // trouvée. Le PRU ne sert de repli qu'AVANT la toute première
  // cotation disponible. Même logique appliquée au benchmark, avec un
  // garde-fou : si le benchmark n'a aucune donnée de prix exploitable,
  // on n'affiche plus de fausse ligne plate à 0%.
  // ---------------------------------------------------------------------
  void _calculateChart() {
    if (_allTransactions.isEmpty) return;

    DateTime endDate = DateTime.now();
    DateTime startDate = endDate;

    List<Map<String, dynamic>> filteredTx = _allTransactions;
    if (_selectedAccountId != 'ALL') {
      filteredTx = _allTransactions
          .where((tx) => tx['account_id'].toString() == _selectedAccountId)
          .toList();
    }

    if (_selectedPeriod == '1S')
      startDate = endDate.subtract(const Duration(days: 7));
    else if (_selectedPeriod == '1M')
      startDate = endDate.subtract(const Duration(days: 30));
    else if (_selectedPeriod == '3M')
      startDate = endDate.subtract(const Duration(days: 90));
    else if (_selectedPeriod == '1A')
      startDate = endDate.subtract(const Duration(days: 365));
    else if (_selectedPeriod == 'YTD')
      startDate = DateTime(endDate.year, 1, 1);
    else if (_selectedPeriod == 'ALL') {
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

    // ---- Historique de prix trié + pointeurs pour le forward-fill ----
    Map<String, List<MapEntry<DateTime, double>>> sortedHistories = {};
    _yahooHistories.forEach((name, hist) {
      final entries =
          hist.entries
              .map((e) => MapEntry(DateTime.parse(e.key), e.value))
              .toList()
            ..sort((a, b) => a.key.compareTo(b.key));
      sortedHistories[name] = entries;
    });
    Map<String, int> historyPointer = {};
    Map<String, double> lastKnownPrice = {};

    List<FlSpot> spotsValue = [];
    List<FlSpot> spotsPercent = [];
    List<FlSpot> spotsBenchmark = [];
    List<double> investedSeries = [];
    _chartDates.clear();

    double lastValue = 0.0;
    int dayIndex = 0;

    // ---- Mise en place du benchmark ----
    String? benchName;
    if (_selectedBenchmarkId != 'NONE' && _selectedBenchmarkId != null) {
      try {
        benchName = _benchmarkList.firstWhere(
          (e) => e['id'].toString() == _selectedBenchmarkId,
        )['name'];
      } catch (e) {}
    }

    List<MapEntry<DateTime, double>>? benchSortedHist = benchName != null
        ? sortedHistories[benchName]
        : null;
    Map<String, dynamic>? benchAferInfo = benchName != null
        ? _aferData[benchName]
        : null;

    // Aucune donnée exploitable pour ce benchmark -> on désactive plutôt
    // que d'afficher une ligne plate trompeuse.
    if (benchName != null &&
        (benchSortedHist == null || benchSortedHist.isEmpty) &&
        benchAferInfo == null) {
      benchName = null;
    }

    int benchHistoryPointer = 0;
    double? benchLastKnownPrice;
    double? benchStartPrice;

    for (
      DateTime d = startDate;
      d.isBefore(endDate) || d.isAtSameMomentAs(endDate);
      d = d.add(const Duration(days: 1))
    ) {
      String currentDateStr = d.toIso8601String().split('T')[0];

      Map<String, Map<String, double>> instStats = {};
      double dailyRealizedGains = 0.0;

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
          instStats[instName]!['boughtQty'] =
              instStats[instName]!['boughtQty']! + q;
          instStats[instName]!['invested'] =
              instStats[instName]!['invested']! + (q * p);
        } else if (type == 'Sell') {
          double currentPru = instStats[instName]!['boughtQty']! > 0.001
              ? instStats[instName]!['invested']! /
                    instStats[instName]!['boughtQty']!
              : 0.0;
          dailyRealizedGains += q * (p - currentPru);
          instStats[instName]!['qty'] = instStats[instName]!['qty']! - q;
          instStats[instName]!['boughtQty'] =
              instStats[instName]!['boughtQty']! - q;
          instStats[instName]!['invested'] =
              instStats[instName]!['invested']! - (q * currentPru);
        } else if (type == 'Dividend') {
          dailyRealizedGains += (q * p);
        }
      }

      double dailyPortfolioValue = dailyRealizedGains;
      double dailyInvestedCapital = 0.0;

      instStats.forEach((instName, stats) {
        double qty = stats['qty']!;
        if (qty <= 0.001) return;

        // On exclut le cash
        if (instName.toLowerCase().contains('liquidit') ||
            instName.toUpperCase().contains('CASH'))
          return;

        double pru = stats['boughtQty']! > 0.001
            ? stats['invested']! / stats['boughtQty']!
            : 0.0;
        dailyInvestedCapital += (pru * qty);

        // Prix par défaut = PRU, seulement tant qu'aucune cotation réelle
        // n'a encore été rencontrée.
        double price = pru;

        if (sortedHistories.containsKey(instName)) {
          final hist = sortedHistories[instName]!;
          int ptr = historyPointer[instName] ?? 0;
          while (ptr < hist.length && !hist[ptr].key.isAfter(d)) {
            lastKnownPrice[instName] = hist[ptr].value;
            ptr++;
          }
          historyPointer[instName] = ptr;
          // Forward-fill : on garde le dernier prix RÉELLEMENT connu.
          price = lastKnownPrice[instName] ?? pru;
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
          while (benchHistoryPointer < benchSortedHist.length &&
              !benchSortedHist[benchHistoryPointer].key.isAfter(d)) {
            benchLastKnownPrice = benchSortedHist[benchHistoryPointer].value;
            benchHistoryPointer++;
          }
          // Avant la première cotation connue, on utilise la première
          // valeur disponible pour ne pas fausser le point de départ.
          benchPrice = benchLastKnownPrice ?? benchSortedHist.first.value;
        } else {
          // Cas AFER : interpolation linéaire PRU global -> dernier prix connu.
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

        // Référence 100% fixée une seule fois, sur le 1er jour affiché,
        // avec un vrai prix (plus de valeur de repli arbitraire).
        benchStartPrice ??= benchPrice;

        double benchPct = benchStartPrice! > 0.001
            ? ((benchPrice - benchStartPrice!) / benchStartPrice!) * 100
            : 0.0;
        spotsBenchmark.add(FlSpot(dayIndex.toDouble(), benchPct));
      }

      _chartDates.add(currentDateStr);
      lastValue = dailyPortfolioValue;
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

    // ---- Courbe "Profit (%)" rebasée sur le début de la plage ----
    // On veut que le % de profit parte de 0 au premier jour de la période
    // choisie (1S, 1M, 3M...), et pas depuis le tout début du portefeuille.
    // On utilise la même logique que le calcul d'en-tête ci-dessus
    // (valeur - capital net investi depuis le début de la plage), mais
    // appliquée jour par jour.
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
      _totalDividends = divs;
      _currentPortfolioValue = lastValue.isNaN ? 0.0 : lastValue;
      _chartDataValue = spotsValue;
      _chartDataPercent = spotsPercent;
      _chartDataBenchmark = spotsBenchmark;
      _periodPerformanceAbs = periodAbs;
      _periodPerformancePct = periodPct;
    });
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
          : Column(
              children: [
                Container(
                  color: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      dropdownColor: const Color(0xFF1C1C1E),
                      value: _selectedAccountId,
                      icon: const Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.blueAccent,
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
                      },
                    ),
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
                      value: _selectedBenchmarkId,
                      icon: const Icon(
                        Icons.compare_arrows,
                        color: Colors.purpleAccent,
                      ),
                      items: _benchmarkList.map((inst) {
                        return DropdownMenuItem<String>(
                          value: inst['id'].toString(),
                          child: Text(
                            inst['name'],
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.purpleAccent,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() => _selectedBenchmarkId = value);
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
                      Text(
                        "${_currentPortfolioValue.toStringAsFixed(2)} €",
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
                            onTap: () => setState(() => _showPercent = false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: !_showPercent
                                    ? Colors.blueAccent
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.blueAccent),
                              ),
                              child: Text(
                                "Valeur (€)",
                                style: TextStyle(
                                  color: !_showPercent
                                      ? Colors.white
                                      : Colors.blueAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () => setState(() => _showPercent = true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: _showPercent
                                    ? Colors.blueAccent
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.blueAccent),
                              ),
                              child: Text(
                                "Profit (%)",
                                style: TextStyle(
                                  color: _showPercent
                                      ? Colors.white
                                      : Colors.blueAccent,
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
                          color: Colors.blueAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          "Dividendes encaissés : ${_totalDividends.toStringAsFixed(2)} €",
                          style: const TextStyle(
                            color: Colors.blueAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      right: 20,
                      left: 10,
                      bottom: 20,
                    ),
                    child: activeChartData.isEmpty
                        ? const Center(
                            child: Text(
                              "Pas de données sur cette période",
                              style: TextStyle(color: Colors.white54),
                            ),
                          )
                        : LineChart(
                            LineChartData(
                              gridData: FlGridData(
                                show: true,
                                drawVerticalLine: false,
                                getDrawingHorizontalLine: (value) => FlLine(
                                  color: Colors.white10,
                                  strokeWidth: 1,
                                ),
                              ),
                              titlesData: FlTitlesData(
                                show: true,
                                rightTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                topTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
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
                                        : (activeChartData.length / 5)
                                              .ceilToDouble(),
                                    getTitlesWidget: (value, meta) {
                                      int index = value.toInt();
                                      if (index >= 0 &&
                                          index < _chartDates.length) {
                                        DateTime d = DateTime.parse(
                                          _chartDates[index],
                                        );
                                        String day = d.day.toString().padLeft(
                                          2,
                                          '0',
                                        );
                                        String month = d.month
                                            .toString()
                                            .padLeft(2, '0');

                                        if (_selectedPeriod == 'ALL' ||
                                            _selectedPeriod == '1A') {
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              top: 8.0,
                                            ),
                                            child: Text(
                                              '$month/${d.year.toString().substring(2)}',
                                              style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 11,
                                              ),
                                            ),
                                          );
                                        }

                                        return Padding(
                                          padding: const EdgeInsets.only(
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
                                    reservedSize: 50,
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
                              lineTouchData: LineTouchData(
                                touchTooltipData: LineTouchTooltipData(
                                  getTooltipItems: (touchedSpots) {
                                    return touchedSpots.map((spot) {
                                      int index = spot.x.toInt();
                                      String date = index < _chartDates.length
                                          ? _chartDates[index]
                                          : "";
                                      String valStr = _showPercent
                                          ? "${spot.y > 0 ? '+' : ''}${spot.y.toStringAsFixed(2)} %"
                                          : "${spot.y.toStringAsFixed(2)} €";

                                      return LineTooltipItem(
                                        "$date\n$valStr",
                                        const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      );
                                    }).toList();
                                  },
                                ),
                              ),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: activeChartData,
                                  isCurved: true,
                                  color: _periodPerformanceAbs >= 0
                                      ? Colors.greenAccent
                                      : Colors.redAccent,
                                  barWidth: 2,
                                  isStrokeCapRound: true,
                                  dotData: const FlDotData(show: false),
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
                                    isCurved: true,
                                    color: Colors.purpleAccent,
                                    barWidth: 2,
                                    isStrokeCapRound: true,
                                    dotData: const FlDotData(show: false),
                                    belowBarData: BarAreaData(show: false),
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
// 3bis. LA PAGE "DÉTAIL D'UNE VALEUR" (graph)
// ==========================================
class InstrumentDetailScreen extends StatefulWidget {
  final Map<String, dynamic> instrument;
  const InstrumentDetailScreen({super.key, required this.instrument});

  @override
  State<InstrumentDetailScreen> createState() => _InstrumentDetailScreenState();
}

class _InstrumentDetailScreenState extends State<InstrumentDetailScreen> {
  bool _isLoading = true;
  String _selectedPeriod = 'YTD';
  final List<String> _periods = ['1S', '1M', '3M', 'YTD', '1A', 'ALL'];
  List<FlSpot> _spots = [];
  List<String> _dates = [];
  Map<String, double> _fullHistory = {};
  double? _currentPrice;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    String name = widget.instrument['name'];
    String isin =
        widget.instrument['ticker_isin'] ?? widget.instrument['isin'] ?? '';
    dynamic id = widget.instrument['id'];

    try {
      _fullHistory = await PriceService.fetchYahooHistory(name, isin: isin);

      if (_fullHistory.isEmpty) {
        final supabase = Supabase.instance.client;
        final rows = await supabase
            .from('daily_prices')
            .select('date, price')
            .eq('instrument_id', id)
            .order('date');
        for (var row in rows) {
          _fullHistory[row['date'].toString().split('T')[0]] =
              (row['price'] as num).toDouble();
        }
      }
    } catch (e) {
      print("Erreur historique: $e");
    }

    double? live = await PriceService.fetchLivePrice(name, isin, id);
    _currentPrice = live;
    if (live != null) {
      final today = DateTime.now().toIso8601String().split('T')[0];
      _fullHistory[today] = live;
    }

    _buildChart();
    if (mounted) setState(() => _isLoading = false);
  }

  void _buildChart() {
    if (_fullHistory.isEmpty) {
      _spots = [];
      _dates = [];
      return;
    }
    List<String> sortedDates = _fullHistory.keys.toList()..sort();
    DateTime endDate = DateTime.parse(sortedDates.last);
    DateTime startDate = endDate;

    if (_selectedPeriod == '1S') {
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

    List<FlSpot> spots = [];
    List<String> dates = [];
    int i = 0;
    for (var dateStr in sortedDates) {
      DateTime d = DateTime.parse(dateStr);
      if (d.isBefore(startDate)) continue;
      spots.add(FlSpot(i.toDouble(), _fullHistory[dateStr]!));
      dates.add(dateStr);
      i++;
    }
    _spots = spots;
    _dates = dates;
  }

  Future<void> _showEditInstrumentDialog() async {
    String? selectedCategory = widget.instrument['category'];
    if (selectedCategory != null && !kCategories.contains(selectedCategory)) {
      selectedCategory = null;
    }
    final TextEditingController commentController = TextEditingController(
      text: widget.instrument['comment'] ?? '',
    );

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          title: Text(
            "Modifier : ${widget.instrument['name']}",
            style: const TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedCategory,
                dropdownColor: const Color(0xFF2C2C2E),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Catégorie',
                  labelStyle: TextStyle(color: Colors.white54),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.blueAccent),
                  ),
                ),
                items: kCategories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
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
                    borderSide: BorderSide(color: Colors.blueAccent),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Annuler"),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await Supabase.instance.client
                      .from('instruments')
                      .update({
                        'category': selectedCategory,
                        'comment': commentController.text.trim(),
                      })
                      .eq('id', widget.instrument['id']);

                  setState(() {
                    widget.instrument['category'] = selectedCategory;
                    widget.instrument['comment'] = commentController.text
                        .trim();
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
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double perfPct = 0.0;
    Color perfColor = Colors.white;
    if (_spots.length > 1) {
      double first = _spots.first.y;
      double last = _spots.last.y;
      if (first > 0.001) perfPct = ((last - first) / first) * 100;
      perfColor = perfPct >= 0 ? Colors.greenAccent : Colors.redAccent;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.instrument['name'],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note, color: Colors.blueAccent),
            onPressed: _showEditInstrumentDialog,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () async {
              bool confirm =
                  await showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: const Color(0xFF1C1C1E),
                      title: const Text(
                        "Supprimer",
                        style: TextStyle(color: Colors.white),
                      ),
                      content: Text(
                        "Voulez-vous retirer ${widget.instrument['name']} ?",
                        style: const TextStyle(color: Colors.white70),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
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

              if (confirm) {
                await Supabase.instance.client
                    .from('instruments')
                    .delete()
                    .eq('id', widget.instrument['id']);
                if (mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.blueAccent),
            )
          : Column(
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
                      if (_spots.length > 1)
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
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            widget.instrument['category'],
                            style: const TextStyle(
                              color: Colors.blueAccent,
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
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      right: 20,
                      left: 10,
                      bottom: 10,
                    ),
                    child: _spots.isEmpty
                        ? const Center(
                            child: Text(
                              "Pas de données disponibles",
                              style: TextStyle(color: Colors.white54),
                            ),
                          )
                        : LineChart(
                            LineChartData(
                              gridData: FlGridData(
                                show: true,
                                drawVerticalLine: false,
                                getDrawingHorizontalLine: (v) => FlLine(
                                  color: Colors.white10,
                                  strokeWidth: 1,
                                ),
                              ),
                              titlesData: FlTitlesData(
                                show: true,
                                rightTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                topTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 30,
                                    interval:
                                        (_spots.length / 5).ceilToDouble() == 0
                                        ? 1
                                        : (_spots.length / 5).ceilToDouble(),
                                    getTitlesWidget: (value, meta) {
                                      int index = value.toInt();
                                      if (index >= 0 && index < _dates.length) {
                                        DateTime d = DateTime.parse(
                                          _dates[index],
                                        );
                                        String day = d.day.toString().padLeft(
                                          2,
                                          '0',
                                        );
                                        String month = d.month
                                            .toString()
                                            .padLeft(2, '0');
                                        if (_selectedPeriod == 'ALL' ||
                                            _selectedPeriod == '1A') {
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              top: 8.0,
                                            ),
                                            child: Text(
                                              '$month/${d.year.toString().substring(2)}',
                                              style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 11,
                                              ),
                                            ),
                                          );
                                        }
                                        return Padding(
                                          padding: const EdgeInsets.only(
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
                                    reservedSize: 55,
                                    getTitlesWidget: (value, meta) => Text(
                                      '${value.toStringAsFixed(0)} €',
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              borderData: FlBorderData(show: false),
                              lineTouchData: LineTouchData(
                                touchTooltipData: LineTouchTooltipData(
                                  getTooltipItems: (touchedSpots) =>
                                      touchedSpots.map((spot) {
                                        int index = spot.x.toInt();
                                        String date = index < _dates.length
                                            ? _dates[index]
                                            : "";
                                        return LineTooltipItem(
                                          "$date\n${spot.y.toStringAsFixed(2)} €",
                                          const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        );
                                      }).toList(),
                                ),
                              ),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: _spots,
                                  isCurved: true,
                                  color: perfColor,
                                  barWidth: 2,
                                  isStrokeCapRound: true,
                                  dotData: const FlDotData(show: false),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: perfColor.withOpacity(0.1),
                                  ),
                                ),
                              ],
                            ),
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
                          setState(() => _selectedPeriod = period);
                          _buildChart();
                          setState(() {});
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

  Future<void> _showEditTransactionDialog(Map<String, dynamic> tx) async {
    final TextEditingController qtyController = TextEditingController(
      text: tx['quantity'].toString(),
    );
    final TextEditingController priceController = TextEditingController(
      text: tx['unit_price'].toString(),
    );

    DateTime selectedDate = DateTime.parse(tx['date'].toString().split('T')[0]);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          title: const Text(
            "Modifier la transaction",
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Instrument : ${tx['instruments']?['name'] ?? 'Inconnu'}",
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 15),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    "Date : ${selectedDate.toLocal().toString().split(' ')[0]}",
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: const Icon(
                    Icons.calendar_today,
                    color: Colors.blueAccent,
                  ),
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
                TextField(
                  controller: qtyController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "Quantité",
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.blueAccent),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: priceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "Prix unitaire (€)",
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.blueAccent),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Annuler"),
            ),
            TextButton(
              onPressed: () async {
                double? newQty = double.tryParse(
                  qtyController.text.replaceAll(',', '.'),
                );
                double? newPrice = double.tryParse(
                  priceController.text.replaceAll(',', '.'),
                );

                if (newQty != null && newPrice != null) {
                  await supabase
                      .from('transactions')
                      .update({
                        'quantity': newQty,
                        'unit_price': newPrice,
                        'date': selectedDate.toIso8601String(),
                      })
                      .eq('id', tx['id']);

                  Navigator.pop(context);
                  _loadPortfolioData();
                }
              },
              child: const Text(
                "Mettre à jour",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
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
              borderSide: BorderSide(color: Colors.blueAccent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Annuler"),
          ),
          TextButton(
            onPressed: () async {
              double? newPrice = double.tryParse(
                priceController.text.replaceAll(',', '.'),
              );
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
            child: const Text(
              "Enregistrer",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadPortfolioData() async {
    setState(() => _isLoading = true);
    try {
      final historyData = await supabase
          .from('transactions')
          .select('*, instruments(name, ticker_isin), accounts(name)')
          .order('date', ascending: false);
      final instrumentsData = await supabase
          .from('instruments')
          .select('id, name, ticker_isin, category, comment')
          .order('name');

      Map<String, double> qtys = {};
      for (var tx in historyData) {
        if (tx['instruments'] == null) continue;
        String instName = tx['instruments']['name'];
        double qty = (tx['quantity'] ?? 0).toDouble();
        String type = tx['transaction_type'];
        if (!qtys.containsKey(instName)) qtys[instName] = 0.0;
        if (type == 'Buy' || type == 'Deposit') {
          qtys[instName] = qtys[instName]! + qty;
        } else if (type == 'Sell')
          qtys[instName] = qtys[instName]! - qty;
      }
      _ownedQuantities = qtys;

      Map<String, double> prices = {};
      for (var inst in instrumentsData) {
        double? livePrice = await PriceService.fetchLivePrice(
          inst['name'],
          inst['ticker_isin'] ?? '',
          inst['id'],
        );
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
          title: const Text(
            'Portfolio',

            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.black,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Valeurs'),
              Tab(text: 'Historique'),
            ],
          ),

          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Se déconnecter',
              onPressed: () async {
                // Déconnexion de Supabase
                await Supabase.instance.client.auth.signOut();
                // L'AuthGate dans ton main.dart s'occupera de rediriger
                // automatiquement l'utilisateur vers la page de connexion.
              },
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
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
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  InstrumentDetailScreen(instrument: inst),
                            ),
                          ),
                          title: Text(
                            inst['name'],
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                currentPrice != null
                                    ? "${currentPrice.toStringAsFixed(2)} €"
                                    : "Non coté",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.white38,
                                  size: 18,
                                ),
                                onPressed: () => _showManualPriceDialog(inst),
                              ),
                            ],
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

                      // Définition de la couleur selon le type
                      Color typeColor;
                      switch (tx['transaction_type']) {
                        case 'Buy':
                          typeColor = Colors.greenAccent;
                          break;
                        case 'Sell':
                          typeColor = Colors.redAccent;
                          break;
                        case 'Dividend':
                          typeColor = Colors.blueAccent;
                          break;
                        case 'Deposit':
                          typeColor = Colors.white;
                          break;
                        default:
                          typeColor = Colors.white54;
                      }

                      return Card(
                        color: const Color(0xFF1C1C1E),
                        child: ListTile(
                          onTap: () => _showEditTransactionDialog(tx),
                          title: Text(
                            tx['instruments']?['name'] ?? 'Inconnu',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            "${tx['transaction_type']} • ${tx['date'].toString().split('T')[0]}",
                            style: TextStyle(color: typeColor.withOpacity(0.8)),
                          ),
                          trailing: Text(
                            "${tx['quantity']} x ${tx['unit_price']} €",
                            style: TextStyle(
                              color: typeColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
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
  final List<String> _types = [
    'Buy',
    'Sell',
    'Dividend',
    'Deposit',
    'Withdrawal',
  ];

  List<Map<String, dynamic>> _instrumentsList = [];
  dynamic _selectedInstrumentId;

  List<Map<String, dynamic>> _accountsList = [];
  dynamic _selectedAccountId;

  bool _isLoadingData = true;

  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();
  final _feesController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final instrumentsData = await supabase
          .from('instruments')
          .select('id, name, ticker_isin')
          .eq('is_watchlist', false)
          .order('name');

      final accountsData = await supabase
          .from('accounts')
          .select('id, name')
          .order('name');

      if (!mounted) return;

      setState(() {
        _instrumentsList = List<Map<String, dynamic>>.from(instrumentsData);
        if (_instrumentsList.isNotEmpty) {
          _selectedInstrumentId = _instrumentsList.first['id'];
        }

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
        SnackBar(
          content: Text("Erreur de chargement: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _submitTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedInstrumentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner un instrument'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_selectedAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner un compte'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final quantity = double.parse(
        _quantityController.text.replaceAll(',', '.'),
      );
      final unitPrice = double.parse(
        _priceController.text.replaceAll(',', '.'),
      );

      double fees = 0.0;
      if (_feesController.text.isNotEmpty) {
        fees = double.parse(_feesController.text.replaceAll(',', '.'));
      }

      await supabase.from('transactions').insert({
        'transaction_type': _selectedType,
        'instrument_id': _selectedInstrumentId,
        'account_id': _selectedAccountId,
        'quantity': quantity,
        'unit_price': unitPrice,
        'fees': fees,
        'date': _selectedDate.toIso8601String(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transaction enregistrée !'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, true);
    } on PostgrestException catch (error) {
      print('🛑 ERREUR SUPABASE : ${error.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur BDD: ${error.message}'),
            backgroundColor: Colors.red,
          ),
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Nouvelle Transaction'),
        backgroundColor: Colors.black,
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
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        "Date : ${_selectedDate.toLocal().toString().split(' ')[0]}",
                        style: const TextStyle(color: Colors.white70),
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () => _selectDate(context),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<dynamic>(
                      value: _selectedAccountId,
                      decoration: const InputDecoration(
                        labelText: 'Compte',
                        border: OutlineInputBorder(),
                      ),
                      items: _accountsList.map((acc) {
                        return DropdownMenuItem(
                          value: acc['id'],
                          child: Text(acc['name'], style: const TextStyle(color: Colors.white70)),
                        );
                      }).toList(),
                      onChanged: (value) =>
                          setState(() => _selectedAccountId = value),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _selectedType,
                      decoration: const InputDecoration(
                        labelText: 'Type de transaction',
                        border: OutlineInputBorder(),
                      ),
                      items: _types.map((type) {
                        return DropdownMenuItem(
                          value: type, 
                          child: Text(type, style: const TextStyle(color: Colors.white70)));
                      }).toList(),
                      onChanged: (value) =>
                          setState(() => _selectedType = value!),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<dynamic>(
                      value: _selectedInstrumentId,
                      decoration: const InputDecoration(
                        labelText: 'Instrument',
                        border: OutlineInputBorder(),
                      ),
                      items: _instrumentsList.map((inst) {
                        return DropdownMenuItem(
                          value: inst['id'],
                          child: Text("${inst['name']}", style: const TextStyle(color: Colors.white70)),
                        );
                      }).toList(),
                      onChanged: (value) =>
                          setState(() => _selectedInstrumentId = value),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _quantityController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Quantité',
                        labelStyle: TextStyle(color: Colors.white70),
                        floatingLabelStyle: TextStyle(color: Colors.white),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (val) =>
                          (val == null || val.isEmpty) ? 'Champ requis' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _priceController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Prix unitaire (€)',
                        labelStyle: TextStyle(color: Colors.white70),
                        floatingLabelStyle: TextStyle(color: Colors.white),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (val) =>
                          (val == null || val.isEmpty) ? 'Champ requis' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _feesController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Frais de courtage (€)',
                        labelStyle: TextStyle(color: Colors.white70),
                        floatingLabelStyle: TextStyle(color: Colors.white),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color.fromARGB(255, 48, 48, 48),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      onPressed: _isSubmitting ? null : _submitTransaction,
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Enregistrer la transaction',
                              style: TextStyle(fontSize: 16),
                            ),
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
        const SnackBar(
          content: Text('Compte créé avec succès !'),
          backgroundColor: Colors.green,
        ),
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Nouveau Compte'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nom du compte (ex: PEA, CTO...)',
                  labelStyle: TextStyle(color: Colors.white70),
                  floatingLabelStyle: TextStyle(color: Colors.white),
                  border: OutlineInputBorder(),
                ),
                validator: (val) =>
                    (val == null || val.isEmpty) ? 'Champ requis' : null,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color.fromARGB(255, 48, 48, 48),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                ),
                onPressed: _isSubmitting ? null : _submitAccount,
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Créer le compte'),
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
  final bool isWatchlist;
  const AddInstrumentScreen({super.key, this.isWatchlist = false});

  @override
  State<AddInstrumentScreen> createState() => _AddInstrumentScreenState();
}

class _AddInstrumentScreenState extends State<AddInstrumentScreen> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _tickerController = TextEditingController();
  final _commentController = TextEditingController();
  String? _selectedCategory;
  bool _isSubmitting = false;

  Future<void> _submitInstrument() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    try {
      await supabase.from('instruments').insert({
        'name': _nameController.text.trim(),
        'ticker_isin': _tickerController.text.trim().toUpperCase(),
        'comment': _commentController.text.trim(),
        'category': _selectedCategory,
        'is_watchlist': widget.isWatchlist,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Instrument ajouté avec succès !'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.isWatchlist
              ? 'Nouvel Instrument (Watchlist)'
              : 'Nouvel Instrument',
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Nom (ex: LVMH, S&P 500)',
                  labelStyle: TextStyle(color: Colors.white70),
                  floatingLabelStyle: TextStyle(color: Colors.white),
                  border: OutlineInputBorder(),
                ),
                validator: (val) =>
                    (val == null || val.isEmpty) ? 'Champ requis' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _tickerController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Ticker ou ISIN (ex: MC.PA)',
                  labelStyle: TextStyle(color: Colors.white70),
                  floatingLabelStyle: TextStyle(color: Colors.white),
                  border: OutlineInputBorder(),
                ),
                validator: (val) =>
                    (val == null || val.isEmpty) ? 'Champ requis' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Catégorie',
                  labelStyle: TextStyle(color: Colors.white70),
                  floatingLabelStyle: TextStyle(color: Colors.white),
                  border: OutlineInputBorder(),
                ),
                items: kCategories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (value) => setState(() => _selectedCategory = value),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _commentController,
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Commentaire (thèse d\'investissement, notes...)',
                  labelStyle: TextStyle(color: Colors.white70),
                  floatingLabelStyle: TextStyle(color: Colors.white),
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 48, 48, 48),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                ),
                onPressed: _isSubmitting ? null : _submitInstrument,
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Ajouter l\'instrument'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
