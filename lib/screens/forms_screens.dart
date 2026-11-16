import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/price_service.dart';

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

  List<JsonMap> _instrumentsList = [];
  dynamic _selectedInstrumentId;

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

      if (!mounted) return;

      setState(() {
        _instrumentsList = List<JsonMap>.from(instrumentsData);
        if (_instrumentsList.isNotEmpty && _selectedInstrumentId == null) {
          _selectedInstrumentId = _instrumentsList.first['id'];
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

    if (_selectedInstrumentId == null ||
        _selectedInstrumentId == 'ADD_NEW_INSTRUMENT') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner un instrument'),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur BDD: ${error.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
                      trailing: const Icon(
                        Icons.calendar_today,
                        color: Colors.white70,
                      ),
                      onTap: () => _selectDate(context),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _selectedType,
                      dropdownColor: Colors.grey[900],
                      decoration: const InputDecoration(
                        labelText: 'Type de transaction',
                        labelStyle: TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(),
                      ),
                      items: _types.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(
                            type,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) =>
                          setState(() => _selectedType = value!),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<dynamic>(
                      value: _selectedInstrumentId,
                      dropdownColor: Colors.grey[900],
                      decoration: const InputDecoration(
                        labelText: 'Action / ETF / Crypto',
                        labelStyle: TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<dynamic>(
                          value: 'ADD_NEW_INSTRUMENT',
                          child: Text(
                            '+ Ajouter une action / ETF / Crypto',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        ..._instrumentsList.map((inst) {
                          return DropdownMenuItem(
                            value: inst['id'],
                            child: Text(
                              "${inst['name']}",
                              style: const TextStyle(color: Colors.white70),
                            ),
                          );
                        }),
                      ],
                      onChanged: (value) async {
                        if (value == 'ADD_NEW_INSTRUMENT') {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const AddInstrumentScreen(),
                            ),
                          );

                          await _loadData();

                          if (_selectedInstrumentId == 'ADD_NEW_INSTRUMENT' ||
                              _selectedInstrumentId == null) {
                            setState(() {
                              _selectedInstrumentId =
                                  _instrumentsList.isNotEmpty
                                  ? _instrumentsList.first['id']
                                  : null;
                            });
                          }
                        } else {
                          setState(() => _selectedInstrumentId = value);
                        }
                      },
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
                        backgroundColor: const Color.fromARGB(255, 48, 48, 48),
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
                style: const TextStyle(color: Colors.white),
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
                  backgroundColor: const Color.fromARGB(255, 48, 48, 48),
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
  late TextEditingController _commentController;

  final _searchController = TextEditingController();
  Timer? _debounce;
  List _searchResults = [];
  bool _isSearching = false;

  String? _selectedCategory;
  String? _selectedAccountId;
  List<JsonMap> _accountsList = [];
  bool _isSubmitting = false;
  bool _isLoadingData = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final formattedDate =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    _commentController = TextEditingController(text: formattedDate);
    _loadData();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _searchResults = []);
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _searchYahoo(q.trim()),
    );
  }

  Future<void> _searchYahoo(String q) async {
    setState(() => _isSearching = true);
    try {
      final target =
          'https://query2.finance.yahoo.com/v1/finance/search?q=${Uri.encodeComponent(q)}&quotesCount=10&newsCount=0';
      final url = Uri.parse(
        'https://pfzsgikdqpnbyhaokdwn.supabase.co/functions/v1/fetch-price?url=${Uri.encodeComponent(target)}',
      );
      final res = await http.get(
        url,
        headers: {'Authorization': 'Bearer $supabaseAnonKey'},
      );
      if (res.statusCode == 200) {
        const okTypes = {
          'EQUITY',
          'ETF',
          'CRYPTOCURRENCY',
          'MUTUALFUND',
          'INDEX',
        };
        final quotes = (json.decode(res.body)['quotes'] as List? ?? [])
            .where(
              (x) => x['symbol'] != null && okTypes.contains(x['quoteType']),
            )
            .map(
              (x) => {
                'symbol': x['symbol'].toString(),
                'name': (x['shortname'] ?? x['longname'] ?? x['symbol'])
                    .toString(),
                'exchange': (x['exchDisp'] ?? '').toString(),
                'type': (x['quoteType'] ?? '').toString(),
              },
            )
            .toList();
        if (mounted) setState(() => _searchResults = quotes);
      }
    } catch (e) {
      // on ignore : l'utilisateur peut toujours saisir à la main
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _loadData() async {
    try {
      final accountsData = await supabase
          .from('accounts')
          .select('id, name')
          .order('name');

      if (!mounted) return;

      setState(() {
        _accountsList = List<JsonMap>.from(accountsData);
        if (_accountsList.isNotEmpty && _selectedAccountId == null) {
          _selectedAccountId = _accountsList.first['id'];
        }
        _isLoadingData = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingData = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Erreur de chargement des comptes : $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _submitInstrument() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedAccountId == null || _selectedAccountId == 'ADD_NEW_ACCOUNT') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner un compte valide'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await supabase.from('instruments').insert({
        'name': _nameController.text.trim(),
        'ticker_isin': _tickerController.text.trim().toUpperCase(),
        'comment': _commentController.text.trim(),
        'category': _selectedCategory,
        'is_watchlist': widget.isWatchlist,
        'account_id': _selectedAccountId,
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
              ? 'Nouvelle action / ETF / Crypto (Watchlist)'
              : 'Nouvelle action / ETF / Crypto',
        ),
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
                    TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText:
                            'Rechercher une entreprise (ex: LVMH, Apple...)',
                        hintStyle: const TextStyle(color: Colors.white54),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.white54,
                        ),
                        suffixIcon: _isSearching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.grey[900],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    if (_searchResults.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: _searchResults.map((r) {
                            return ListTile(
                              dense: true,
                              title: Text(
                                r['name']!,
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                '${r['symbol']} • ${r['exchange']} • ${r['type']}',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                              onTap: () {
                                setState(() {
                                  _nameController.text = r['name']!;
                                  _tickerController.text = r['symbol']!;
                                  _searchResults = [];
                                  _searchController.clear();
                                });
                                FocusScope.of(context).unfocus();
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    const SizedBox(height: 24),
                    const Divider(color: Colors.white12),
                    const SizedBox(height: 8),
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
                        labelText: 'Ticker ou ISIN (facultatif)',
                        labelStyle: TextStyle(color: Colors.white70),
                        floatingLabelStyle: TextStyle(color: Colors.white),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<dynamic>(
                      value: _selectedAccountId,
                      dropdownColor: Colors.grey[900],
                      decoration: const InputDecoration(
                        labelText: 'Compte',
                        labelStyle: TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<dynamic>(
                          value: 'ADD_NEW_ACCOUNT',
                          child: Text(
                            '+ Ajouter un compte',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        ..._accountsList.map((acc) {
                          return DropdownMenuItem(
                            value: acc['id'],
                            child: Text(
                              acc['name'],
                              style: const TextStyle(color: Colors.white70),
                            ),
                          );
                        }),
                      ],
                      onChanged: (value) async {
                        if (value == 'ADD_NEW_ACCOUNT') {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const AddAccountScreen(),
                            ),
                          );

                          await _loadData();

                          if (_selectedAccountId == 'ADD_NEW_ACCOUNT' ||
                              _selectedAccountId == null) {
                            setState(() {
                              _selectedAccountId = _accountsList.isNotEmpty
                                  ? _accountsList.first['id']
                                  : null;
                            });
                          }
                        } else {
                          setState(() => _selectedAccountId = value);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _selectedCategory,
                      style: const TextStyle(color: Colors.white70),
                      dropdownColor: Colors.grey[900],
                      decoration: const InputDecoration(
                        labelText: 'Catégorie',
                        labelStyle: TextStyle(color: Colors.white70),
                        floatingLabelStyle: TextStyle(color: Colors.white),
                        border: OutlineInputBorder(),
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
                          setState(() => _selectedCategory = value),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _commentController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText:
                            'Commentaire (thèse d\'investissement, notes...)',
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
                          : const Text('Ajouter l\'action / ETF / Crypto'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
