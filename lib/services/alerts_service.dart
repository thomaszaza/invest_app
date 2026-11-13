import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_service.dart';

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
    } catch (e) {}
  }

  static Future<void> createAlert(
    dynamic instrumentId,
    double threshold,
    String direction,
  ) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      await supabase.from('alerts').insert({
        'user_id': user.id,
        'instrument_id': instrumentId,
        'threshold_price': threshold,
        'direction': direction,
        'active': true,
        'triggered': false,
      });
    } catch (e) {}
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
                  borderSide: BorderSide(color: Colors.white),
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
            style: TextButton.styleFrom(foregroundColor: Colors.blueAccent),
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
