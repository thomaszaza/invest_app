import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:csv/csv.dart' as my_csv;
import 'package:intl/intl.dart';

import '../main.dart';

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isImporting = false;
  List<JsonMap> _instruments = [];
  List<JsonMap> _history = [];
  DoubleMap _livePrices = {};
  DoubleMap _ownedQuantities = {};
  List<JsonMap> _accountsList = [];

  @override
  void initState() {
    super.initState();
    _loadPortfolioData();
  }

  Future<void> _showEditTransactionDialog(JsonMap tx) async {
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
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    "Date : ${selectedDate.toLocal().toString().split(' ')[0]}",
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: const Icon(
                    Icons.calendar_today,
                    color: Colors.white,
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
                  style: const TextStyle(color: Colors.white70),
                  decoration: const InputDecoration(
                    labelText: "Quantité",
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: priceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(color: Colors.white70),
                  decoration: const InputDecoration(
                    labelText: "Prix unitaire (€)",
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
                double? newPrice = double.tryParse(
                  priceController.text.replaceAll(',', '.'),
                );
                if (newPrice == null) return;

                try {
                  final today = DateTime.now().toIso8601String().split('T')[0];
                  await supabase.from('daily_prices').upsert({
                    'instrument_id': tx['instrument_id'],
                    'date': today,
                    'price': newPrice,
                  }, onConflict: 'instrument_id,date');

                  PriceCache.set(tx['instrument_id'].toString(), newPrice);

                  if (context.mounted) {
                    Navigator.pop(context);
                    _loadPortfolioData();
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
      ),
    );
  }

  Future<void> _confirmDeleteTransaction(JsonMap tx) async {
    bool confirm =
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1C1C1E),
            title: const Text(
              "Supprimer la transaction",
              style: TextStyle(color: Colors.white),
            ),
            content: Text(
              "Supprimer définitivement cette transaction "
              "(${tx['instruments']?['name'] ?? 'Inconnu'} • "
              "${tx['transaction_type']} • "
              "${tx['date'].toString().split('T')[0]}) ? "
              "Cette action est irréversible.",
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(foregroundColor: Colors.blueAccent),
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
      await supabase.from('transactions').delete().eq('id', tx['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Transaction supprimée."),
            backgroundColor: Colors.green,
          ),
        );
      }
      _loadPortfolioData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur lors de la suppression : $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showManualPriceDialog(JsonMap inst) async {
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
              double? newPrice = double.tryParse(
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
                  _loadPortfolioData();
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

  Future<void> _loadPortfolioData() async {
    setState(() => _isLoading = true);

    try {
      final historyData = await supabase
          .from('transactions')
          .select(
            '*, instruments(name, ticker_isin, account_id, accounts(name))',
          )
          .order('date', ascending: false);

      final instrumentsData = await supabase
          .from('instruments')
          .select('id, name, ticker_isin, category, comment')
          .order('name');

      final accountsData = await supabase
          .from('accounts')
          .select('id, name')
          .order('name');

      DoubleMap qtys = {};
      for (var tx in historyData) {
        if (tx['instruments'] == null) continue;
        String instName = tx['instruments']['name'];
        double qty = (tx['quantity'] ?? 0).toDouble();
        String type = tx['transaction_type'];

        if (!qtys.containsKey(instName)) qtys[instName] = 0.0;

        if (type == 'Buy' || type == 'Deposit') {
          qtys[instName] = qtys[instName]! + qty;
        } else if (type == 'Sell') {
          qtys[instName] = qtys[instName]! - qty;
        }
      }

      if (mounted) {
        setState(() {
          _history = List<JsonMap>.from(historyData);
          _instruments = List<JsonMap>.from(instrumentsData);
          _accountsList = List<JsonMap>.from(accountsData);
          _ownedQuantities = qtys;
          _isLoading = false;
        });
      }

      List<FutureVoid> priceFutures = _instruments.map((inst) async {
        try {
          double? livePrice = await PriceService.fetchLivePrice(
            inst['name'],
            inst['ticker_isin'] ?? '',
            inst['id'],
          );

          if (livePrice != null && mounted) {
            setState(() {
              _livePrices[inst['name']] = livePrice;
            });
          }
        } catch (e) {}
      }).toList();

      await Future.wait(priceFutures);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showEditAccountDialog(JsonMap account) async {
    final TextEditingController nameController = TextEditingController(
      text: account['name'],
    );

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text(
          "Modifier le compte",
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: "Nom du compte",
            labelStyle: TextStyle(color: Colors.white54),
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
              final newName = nameController.text.trim();
              if (newName.isEmpty) return;
              try {
                await supabase
                    .from('accounts')
                    .update({'name': newName})
                    .eq('id', account['id']);

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Compte mis à jour !"),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
                _loadPortfolioData();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Erreur : $e"),
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

  void _showCsvInstructionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Format du fichier CSV'),
          content: const SingleChildScrollView(
            child: ListBody(
              children: [
                Text(
                  'Votre fichier CSV doit contenir 8 colonnes dans cet ordre exact :',
                ),
                SizedBox(height: 12),
                Text('1. Date (jj/mm/aaaa)'),
                Text('2. Nom de l\'instrument'),
                Text('3. Ticker ou ISIN'),
                Text(
                  '4. Type de transaction (Buy, Sell, Deposit, Dividend, Withdrawal)',
                ),
                Text('5. Quantité'),
                Text('6. Prix unitaire'),
                Text('7. Frais de courtage'),
                Text('8. Compte (PEA, CTO, etc.)'),
                SizedBox(height: 12),
                Text(
                  '⚠️ Les colonnes doivent être séparées par des virgules (,) et les décimales avec des points (ex: 30.50). Si l\'instrument ou le compte n\'existe pas encore, ils seront créés automatiquement.',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Annuler'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              child: const Text('J\'ai compris, importer'),
              onPressed: () {
                Navigator.of(context).pop();
                _importCSV();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _importCSV() async {
    setState(() {
      _isImporting = true;
    });

    try {
      fp.FilePickerResult? result = await fp.FilePicker.platform.pickFiles(
        type: fp.FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result != null && result.files.first.bytes != null) {
        final csvString = utf8.decode(result.files.first.bytes!);

        String delimiter = csvString.contains(';') ? ';' : ',';

        List<DynamicList> rowsAsListOfValues = my_csv.CsvToListConverter(
          fieldDelimiter: delimiter,
          eol: '\n',
        ).convert(csvString);

        if (rowsAsListOfValues.isEmpty) return;

        if (rowsAsListOfValues.first[0].toString().toLowerCase().contains(
          'date',
        )) {
          rowsAsListOfValues.removeAt(0);
        }

        final dateFormat = DateFormat('dd/MM/yyyy');
        const validTypes = ['Buy', 'Sell', 'Deposit', 'Dividend', 'Withdrawal'];

        JsonMap accountCache = {
          for (var acc in _accountsList)
            (acc['name'] as String).toLowerCase(): acc['id'],
        };

        JsonMap instrumentCache = {
          for (var inst in _instruments)
            "${inst['account_id']}_${(inst['name'] as String).toLowerCase()}":
                inst['id'],
        };

        int importedCount = 0;
        int skippedCount = 0;

        for (var i = 0; i < rowsAsListOfValues.length; i++) {
          var row = rowsAsListOfValues[i];

          if (row.length < 8) {
            print('Ligne $i ignorée : pas assez de colonnes (${row.length})');
            skippedCount++;
            continue;
          }

          try {
            String dateStr = row[0].toString().trim().split(' ').first;
            DateTime parsedDate = dateFormat.parse(dateStr);

            String name = row[1].toString().trim();
            String tickerIsin = row[2].toString().trim();
            String txType = row[3].toString().trim();
            double quantity =
                double.tryParse(
                  row[4].toString().trim().replaceAll(',', '.'),
                ) ??
                0;
            double unitPrice =
                double.tryParse(
                  row[5].toString().trim().replaceAll(',', '.'),
                ) ??
                0;
            double fees =
                double.tryParse(
                  row[6].toString().trim().replaceAll(',', '.'),
                ) ??
                0;
            String accountName = row[7].toString().trim();

            if (name.isEmpty || accountName.isEmpty) {
              print('Ligne $i ignorée : Nom ou Compte vide');
              skippedCount++;
              continue;
            }

            String normalizedType = validTypes.firstWhere(
              (t) => t.toLowerCase() == txType.toLowerCase(),
              orElse: () => 'Buy',
            );

            dynamic accountId = accountCache[accountName.toLowerCase()];
            if (accountId == null) {
              final newAccount = await supabase
                  .from('accounts')
                  .insert({'name': accountName})
                  .select()
                  .single();
              accountId = newAccount['id'];
              accountCache[accountName.toLowerCase()] = accountId;
            }

            String instrumentCacheKey = "${accountId}_${name.toLowerCase()}";
            dynamic instrumentId = instrumentCache[instrumentCacheKey];

            if (instrumentId == null) {
              final newInstrument = await supabase
                  .from('instruments')
                  .insert({
                    'name': name,
                    'ticker_isin': tickerIsin.toUpperCase(),
                    'account_id': accountId,
                    'is_watchlist': false,
                  })
                  .select()
                  .single();
              instrumentId = newInstrument['id'];
              instrumentCache[instrumentCacheKey] = instrumentId;
            }

            await supabase.from('transactions').insert({
              'instrument_id': instrumentId,
              'transaction_type': normalizedType,
              'quantity': quantity,
              'unit_price': unitPrice,
              'fees': fees,
              'date': parsedDate.toIso8601String(),
            });

            importedCount++;
          } catch (e) {
            print('Erreur ligne $i: $e');
            print('Contenu de la ligne : $row');
            skippedCount++;
            continue;
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$importedCount transaction(s) importée(s)'
                '${skippedCount > 0 ? ', $skippedCount ligne(s) ignorée(s)' : ''} !',
              ),
            ),
          );
        }

        _loadPortfolioData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur globale : $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  Future<void> _confirmDeleteAccount(JsonMap account) async {
    bool confirm =
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1C1C1E),
            title: const Text(
              "Supprimer le compte",
              style: TextStyle(color: Colors.white),
            ),
            content: Text(
              "Voulez-vous vraiment supprimer \"${account['name']}\" ? "
              "Cette action est irréversible. Si des transactions sont "
              "liées à ce compte, la suppression peut échouer.",
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(foregroundColor: Colors.blueAccent),
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
      await supabase.from('accounts').delete().eq('id', account['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Compte supprimé."),
            backgroundColor: Colors.green,
          ),
        );
      }
      _loadPortfolioData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Impossible de supprimer : des transactions utilisent "
              "peut-être encore ce compte.",
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
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
              Tab(text: 'Comptes'),
              Tab(text: 'Historique'),
            ],
          ),
          actions: [
            _isImporting
                ? const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.upload_file),
                    tooltip: 'Importer un fichier CSV',
                    onPressed: () => _showCsvInstructionsDialog(context),
                  ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Se déconnecter',
              onPressed: () async {
                await Supabase.instance.client.auth.signOut();
              },
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  ListView.builder(
                    itemCount: _instruments.length,
                    itemBuilder: (context, index) {
                      final inst = _instruments[index];
                      final ownedQty = _ownedQuantities[inst['name']] ?? 0.0;
                      if (ownedQty <= 0) return const SizedBox.shrink();

                      final currentPrice = _livePrices[inst['name']];

                      return Card(
                        color: const Color(0xFF1C1C1E),
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 0,
                          ),
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
                  _accountsList.isEmpty
                      ? const Center(
                          child: Text(
                            "Aucun compte pour l'instant",
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _accountsList.length,
                          itemBuilder: (context, index) {
                            final acc = _accountsList[index];
                            return Card(
                              color: const Color(0xFF1C1C1E),
                              margin: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 0,
                                ),
                                title: Text(
                                  acc['name'],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit,
                                        color: Colors.white54,
                                      ),
                                      onPressed: () =>
                                          _showEditAccountDialog(acc),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.white,
                                      ),
                                      onPressed: () =>
                                          _confirmDeleteAccount(acc),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                  ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                      final tx = _history[index];

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
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 0,
                          ),
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
                            style: TextStyle(color: typeColor),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "${tx['quantity']} x ${tx['unit_price']} €",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.redAccent,
                                  size: 20,
                                ),
                                onPressed: () => _confirmDeleteTransaction(tx),
                              ),
                            ],
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
