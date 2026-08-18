import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ⚠️ REMPLACE PAR TES VRAIES CLÉS SUPABASE ICI :
  await Supabase.initialize(
    url: 'https://pfzsgikdqpnbyhaokdwn.supabase.co',
    anonKey: 'sb_publishable_owIZox6AqByWrqOiE_bbhQ_opZNPqaG',
  );

  runApp(const InvestApp());
}

class InvestApp extends StatelessWidget {
  const InvestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zaza Invest',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: const MainNavigationScreen(), // L'écran de démarrage est maintenant le menu
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
  // L'index 0 correspond au premier onglet (Positions)
  int _currentIndex = 0;

  // La liste de nos 3 pages
  final List<Widget> _screens = [
    const PositionsScreen(),
    const PerformanceScreen(),
    const PortfolioScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Affiche l'écran correspondant à l'index sélectionné
      body: _screens[_currentIndex], 
      
      // La barre de navigation en bas
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index; // Change la page quand on clique
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
// 2. LA PAGE "POSITIONS" (Étape 2 accomplie !)
// ==========================================
class PositionsScreen extends StatefulWidget {
  const PositionsScreen({super.key});

  @override
  State<PositionsScreen> createState() => _PositionsScreenState();
}

class _PositionsScreenState extends State<PositionsScreen> {
  final supabase = Supabase.instance.client;
  
  String totalValue = "0.00 €";
  bool isLoading = true; // Petite nouveauté : un indicateur de chargement
  
  // On crée une liste pour stocker chaque ligne de notre portefeuille
  List<Map<String, dynamic>> _activePositions = []; 

  @override
  void initState() {
    super.initState();
    fetchPortfolioData();
  }

// Fonction pour afficher le menu d'ajout
  void _showAddMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min, // Le menu prend juste la taille nécessaire
              children: [
                const Text(
                  "Que voulez-vous ajouter ?",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 15),
                ListTile(
                  leading: const CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.swap_horiz, color: Colors.white)),
                  title: const Text('Une Transaction (Achat, Vente...)'),
                  onTap: () async {
                    Navigator.pop(context); // 1. On ferme le petit menu du bas
                    
                    // 2. On ouvre la grande page formulaire qu'on vient de créer !
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AddTransactionScreen()),
                    );
                    
                    // 3. Si la page a renvoyé "true" (succès), on relance le calcul pour actualiser l'accueil !
                    if (result == true) {
                      fetchPortfolioData();
                    }
                  },
                ),
                ListTile(
                  leading: CircleAvatar(backgroundColor: Colors.orange[400], child: const Icon(Icons.business_center, color: Colors.white)),
                  title: const Text('Un Instrument (Action, ETF)'),
                  onTap: () {
                    Navigator.pop(context); // Ferme le menu
                    print("Go to Instrument");
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.account_balance, color: Colors.white)),
                  title: const Text('Un Compte (PEA, CTO...)'),
                  onTap: () {
                    Navigator.pop(context); // Ferme le menu
                    print("Go to Compte");
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> fetchPortfolioData() async {
    setState(() {
      isLoading = true; // On affiche la roue de chargement
    });

    try {
      final data = await supabase.from('transactions').select('*, instruments(ticker_isin, name)');
      Map<String, Map<String, dynamic>> holdings = {};

      for (var tx in data) {
        if (tx['instruments'] == null) continue;
        String ticker = tx['instruments']['ticker_isin'];
        String name = tx['instruments']['name'];
        double qty = (tx['quantity'] ?? 0).toDouble();
        double unitPrice = (tx['unit_price'] ?? 0).toDouble();
        String type = tx['transaction_type'];

        if (!holdings.containsKey(ticker)) {
          // On ajoute le ticker dans les données pour l'affichage plus tard
          holdings[ticker] = {"ticker": ticker, "name": name, "quantity": 0.0, "investi_total": 0.0};
        }

        if (type == 'Buy') {
          holdings[ticker]!['quantity'] += qty;
          holdings[ticker]!['investi_total'] += (qty * unitPrice);
        } else if (type == 'Sell') {
          double currentQty = holdings[ticker]!['quantity'];
          double currentInvesti = holdings[ticker]!['investi_total'];
          double pru = currentQty > 0 ? (currentInvesti / currentQty) : 0.0;

          holdings[ticker]!['quantity'] -= qty;
          holdings[ticker]!['investi_total'] -= (qty * pru);
        }
      }

      double totalInvested = 0.0;
      List<Map<String, dynamic>> tempPositions = []; // Liste temporaire

      holdings.forEach((ticker, position) {
        if (position['quantity'] > 0) {
          totalInvested += position['investi_total'];
          
          // On calcule le PRU ici pour l'afficher sur chaque carte
          double pru = position['investi_total'] / position['quantity'];
          position['pru'] = pru; 
          
          // On ajoute cette action à notre liste à afficher
          tempPositions.add(position);
        }
      });

      // On met à jour l'écran avec les nouvelles données
      setState(() {
        totalValue = "${totalInvested.toStringAsFixed(2)} €";
        _activePositions = tempPositions;
        isLoading = false; // On cache la roue de chargement
      });
    } catch (e) {
      setState(() {
        totalValue = "Erreur";
        isLoading = false;
      });
      print("Erreur: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Positions', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
       actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              // On appelle notre nouvelle fonction !
              _showAddMenu(context); 
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchPortfolioData,
          ),
        ],
      ),
      // Si isLoading est vrai, on affiche un rond qui tourne, sinon on affiche la page
      body: isLoading 
          ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
          : Column(
              children: [
                // 1. Le bloc du haut avec le total (sur fond blanc pour ressortir)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 25),
                  color: Colors.white,
                  child: Column(
                    children: [
                      const Text('Montant Investi', style: TextStyle(fontSize: 16, color: Colors.grey)),
                      const SizedBox(height: 5),
                      Text(totalValue, style: const TextStyle(fontSize: 38, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                
                const SizedBox(height: 10),
                
                // 2. La liste des actions/ETF
                Expanded(
                  child: _activePositions.isEmpty
                    ? const Center(child: Text("Aucun actif possédé", style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        itemCount: _activePositions.length,
                        itemBuilder: (context, index) {
                          final pos = _activePositions[index];
                          
                          // On crée une jolie "Carte" pour chaque ligne
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            elevation: 0, // Enlève l'ombre pour un design plus plat/moderne
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              // Nom de l'actif
                              title: Text(
                                pos['name'], 
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              // Quantité et PRU en dessous
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(
                                  "Qté: ${pos['quantity'].toStringAsFixed(2)}  •  PRU: ${pos['pru'].toStringAsFixed(2)} €",
                                  style: TextStyle(color: Colors.grey[700]),
                                ),
                              ),
                              // Total investi tout à droite
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    "${pos['investi_total'].toStringAsFixed(2)} €", 
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
    );
  }
}
// ==========================================
// 3. LA PAGE "PERFORMANCE" (En construction)
// ==========================================
class PerformanceScreen extends StatelessWidget {
  const PerformanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Performance'), backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
      body: const Center(child: Text("Le graphique arrivera ici ! (Étape 4)", style: TextStyle(fontSize: 18))),
    );
  }
}

// ==========================================
// 4. LA PAGE "PORTFOLIO" (En construction)
// ==========================================
class PortfolioScreen extends StatelessWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Portfolio'), backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
      body: const Center(child: Text("La répartition arrivera ici ! (Étape 5)", style: TextStyle(fontSize: 18))),
    );
  }
}


// ==========================================
// 5. LA PAGE D'AJOUT DE TRANSACTION (Complète)
// ==========================================
class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  // Types de transactions
  String _selectedType = 'Buy';
  final List<String> _types = ['Buy', 'Sell', 'Dividend', 'Deposit', 'Withdrawal'];

  // Gestion des instruments
  List<Map<String, dynamic>> _instrumentsList = [];
  dynamic _selectedInstrumentId;
  bool _isLoadingInstruments = true;

  // Contrôleurs pour les champs numériques
  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadInstruments();
  }

  // 1. On charge la liste de tes instruments depuis Supabase
  Future<void> _loadInstruments() async {
    try {
      final data = await supabase
          .from('instruments')
          .select('id, name, ticker_isin')
          .order('name');

      if (!mounted) return;
      setState(() {
        _instrumentsList = List<Map<String, dynamic>>.from(data);
        if (_instrumentsList.isNotEmpty) {
          _selectedInstrumentId = _instrumentsList.first['id'];
        }
        _isLoadingInstruments = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingInstruments = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur instruments: $e"), backgroundColor: Colors.red),
      );
    }
  }

  // 2. Envoi de la transaction
  Future<void> _submitTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedInstrumentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner un instrument'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Insertion directe dans la table Supabase
      await supabase.from('transactions').insert({
        'transaction_type': _selectedType,
        'instrument_id': _selectedInstrumentId,
        'quantity': double.parse(_quantityController.text.replaceAll(',', '.')),
        'unit_price': double.parse(_priceController.text.replaceAll(',', '.')),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaction enregistrée !'), backgroundColor: Colors.green),
      );

      // Ferme la page et ordonne à l'écran précédent de rafraîchir le portefeuille
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
      appBar: AppBar(
        title: const Text('Nouvelle Transaction'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: _isLoadingInstruments
          ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    // Choix de l'ordre (Buy, Sell, etc.)
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

                    // Choix de l'Instrument (Action / ETF)
                    DropdownButtonFormField<dynamic>(
                      value: _selectedInstrumentId,
                      decoration: const InputDecoration(
                        labelText: 'Instrument',
                        border: OutlineInputBorder(),
                      ),
                      items: _instrumentsList.map((inst) {
                        return DropdownMenuItem(
                          value: inst['id'],
                          child: Text("${inst['name']} (${inst['ticker_isin']})"),
                        );
                      }).toList(),
                      onChanged: (value) => setState(() => _selectedInstrumentId = value),
                    ),
                    const SizedBox(height: 16),

                    // Quantité
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

                    // Prix unitaire
                    TextFormField(
                      controller: _priceController,
                      decoration: const InputDecoration(
                        labelText: 'Prix unitaire (€)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (val) => (val == null || val.isEmpty) ? 'Champ requis' : null,
                    ),
                    const SizedBox(height: 24),

                    // Bouton Enregistrer
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
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