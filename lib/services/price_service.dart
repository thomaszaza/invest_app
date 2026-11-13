import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

typedef JsonMap = Map<String, dynamic>;
typedef DoubleMap = Map<String, double>;
typedef PriceEntry = MapEntry<DateTime, double>;
typedef PriceEntryList = List<PriceEntry>;
typedef FutureVoid = Future<void>;
typedef DynamicList = List<dynamic>;

const String supabaseUrl = 'https://pfzsgikdqpnbyhaokdwn.supabase.co';
const String supabaseAnonKey = 'sb_publishable_owIZox6AqByWrqOiE_bbhQ_opZNPqaG';
const List<String> kCategories = ['Croissance', 'Rendement', 'Opportunité'];

class PriceCache {
  static final Map<String, double> _prices = {};
  static final Map<String, DateTime> _timestamps = {};
  static final Map<String, DoubleMap> _histories = {};
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

  static void setHistory(String cacheKey, DoubleMap history) {
    _histories[cacheKey] = history;
    _historyTimestamps[cacheKey] = DateTime.now();
  }

  static DoubleMap? getHistory(String cacheKey) {
    if (_historyTimestamps.containsKey(cacheKey) &&
        DateTime.now().difference(_historyTimestamps[cacheKey]!).inHours < 6) {
      return _histories[cacheKey];
    }
    return null;
  }
}

class PriceService {
  static final supabase = Supabase.instance.client;

  static Future<JsonMap?> fetchYahooFundamentals(
    String instrumentName, {
    String? isin,
  }) async {
    String? symbol;

    if (instrumentName.startsWith('EPA:')) {
      symbol = '${instrumentName.replaceAll('EPA:', '')}.PA';
    } else if (isin != null && isin.isNotEmpty && isin != 'CASH') {
      if (isin.contains('.') || isin.length != 12) {
        symbol = isin;
      } else {
        try {
          final searchUrl = Uri.parse(
            '$supabaseUrl/functions/v1/fetch-price?url=${Uri.encodeComponent('https://query2.finance.yahoo.com/v1/finance/search?q=$isin')}',
          );
          final res = await http.get(
            searchUrl,
            headers: {'Authorization': 'Bearer $supabaseAnonKey'},
          );
          if (res.statusCode == 200) {
            final data = json.decode(res.body);
            if (data['quotes'] != null && data['quotes'].isNotEmpty) {
              symbol = data['quotes'][0]['symbol'];
            }
          }
        } catch (e) {
          print("Erreur résolution ticker : $e");
        }
      }
    }

    if (symbol == null || symbol.isEmpty) {
      print("Impossible de déterminer le symbole pour $instrumentName ($isin)");
      return null;
    }

    final targetUrl =
        'https://query1.finance.yahoo.com/v10/finance/quoteSummary/$symbol?modules=summaryDetail,price';
    final proxyUrl = Uri.parse(
      '$supabaseUrl/functions/v1/fetch-price?url=${Uri.encodeComponent(targetUrl)}',
    );

    try {
      final response = await http.get(
        proxyUrl,
        headers: {'Authorization': 'Bearer $supabaseAnonKey'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final result = data['quoteSummary']?['result']?[0];
        if (result == null) return null;

        final summary = result['summaryDetail'] ?? {};
        final price = result['price'] ?? {};

        double? getRaw(dynamic field) => field != null && field['raw'] != null
            ? (field['raw'] as num).toDouble()
            : null;

        return {
          'dividendYield': getRaw(summary['dividendYield']) != null
              ? getRaw(summary['dividendYield'])! * 100
              : null,
          'trailingPE': getRaw(summary['trailingPE']),
          'forwardPE': getRaw(summary['forwardPE']),
          'marketCap': getRaw(price['marketCap']),
          'currency': price['currencySymbol'] ?? '€',
        };
      }
    } catch (e) {
      print("Erreur fetchYahooFundamentals : $e");
    }

    return null;
  }

  static Future<double?> fetchLivePrice(
    String instrumentName,
    String isin,
    dynamic instrumentId,
  ) async {
    double? cached = PriceCache.get(instrumentId.toString());
    if (cached != null) return cached;

    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final manualList = await supabase
          .from('daily_prices')
          .select('price')
          .eq('instrument_id', instrumentId)
          .eq('date', today)
          .order('id', ascending: false)
          .limit(1);
      if (manualList.isNotEmpty) {
        final p = (manualList.first['price'] as num).toDouble();
        if (!p.isNaN) {
          PriceCache.set(instrumentId.toString(), p);
          return p;
        }
      }
    } catch (e) {}

    double? finalPrice;

    try {
      String symbol = "";
      if (instrumentName.startsWith('EPA:')) {
        symbol = '${instrumentName.replaceAll('EPA:', '')}.PA';
      } else if (isin.isNotEmpty && isin != 'CASH') {
        final targetSearchUrl =
            'https://query2.finance.yahoo.com/v1/finance/search?q=$isin';
        final searchUrl = Uri.parse(
          '$supabaseUrl/functions/v1/fetch-price?url=${Uri.encodeComponent(targetSearchUrl)}',
        );
        final searchResponse = await http.get(
          searchUrl,
          headers: {'Authorization': 'Bearer $supabaseAnonKey'},
        );
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
          '$supabaseUrl/functions/v1/fetch-price?url=${Uri.encodeComponent(targetChartUrl)}',
        );
        final response = await http.get(
          chartUrl,
          headers: {'Authorization': 'Bearer $supabaseAnonKey'},
        );
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final price =
              data['chart']['result'][0]['meta']['regularMarketPrice'];
          finalPrice = (price as num).toDouble();
        }
      }
    } catch (e) {}

    if (finalPrice != null && !finalPrice.isNaN) {
      PriceCache.set(instrumentId.toString(), finalPrice);
      return finalPrice;
    }

    return null;
  }

  static Future<DoubleMap> fetchYahooHistory(
    String instrumentName, {
    String? isin,
    String range = 'max',
  }) async {
    final cacheKey = '$instrumentName|${isin ?? ''}|$range';

    final cachedHistory = PriceCache.getHistory(cacheKey);
    if (cachedHistory != null && cachedHistory.isNotEmpty) {
      return cachedHistory;
    }

    DoubleMap history = {};
    String? symbol;

    if (instrumentName.startsWith('EPA:')) {
      symbol = '${instrumentName.replaceAll('EPA:', '')}.PA';
    } else if (isin != null && isin.isNotEmpty && isin != 'CASH') {
      try {
        final searchUrl = Uri.parse(
          '$supabaseUrl/functions/v1/fetch-price?url=${Uri.encodeComponent('https://query2.finance.yahoo.com/v1/finance/search?q=$isin')}',
        );
        final res = await http.get(
          searchUrl,
          headers: {'Authorization': 'Bearer $supabaseAnonKey'},
        );
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
      '$supabaseUrl/functions/v1/fetch-price?url=${Uri.encodeComponent(targetUrl)}',
    );

    try {
      final response = await http.get(
        proxyUrl,
        headers: {'Authorization': 'Bearer $supabaseAnonKey'},
      );
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
    } catch (e) {}

    if (history.isNotEmpty) {
      PriceCache.setHistory(cacheKey, history);
    }

    return history;
  }

  static Future<DoubleMap> fetchYahooIntraday(
    String instrumentName, {
    String? isin,
    String range = '5d',
    String interval = '15m',
  }) async {
    final cacheKey = '$instrumentName|${isin ?? ''}|$range|$interval';

    final cachedHistory = PriceCache.getHistory(cacheKey);
    if (cachedHistory != null && cachedHistory.isNotEmpty) {
      return cachedHistory;
    }

    DoubleMap history = {};
    String? symbol;

    if (instrumentName.startsWith('EPA:')) {
      symbol = '${instrumentName.replaceAll('EPA:', '')}.PA';
    } else if (isin != null && isin.isNotEmpty && isin != 'CASH') {
      try {
        final searchUrl = Uri.parse(
          '$supabaseUrl/functions/v1/fetch-price?url=${Uri.encodeComponent('https://query2.finance.yahoo.com/v1/finance/search?q=$isin')}',
        );
        final res = await http.get(
          searchUrl,
          headers: {'Authorization': 'Bearer $supabaseAnonKey'},
        );
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
        'https://query1.finance.yahoo.com/v8/finance/chart/$symbol?range=$range&interval=$interval';
    final proxyUrl = Uri.parse(
      '$supabaseUrl/functions/v1/fetch-price?url=${Uri.encodeComponent(targetUrl)}',
    );

    try {
      final response = await http.get(
        proxyUrl,
        headers: {'Authorization': 'Bearer $supabaseAnonKey'},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final result = data['chart']['result'][0];
        List<dynamic> timestamps = result['timestamp'];
        List<dynamic> closePrices = result['indicators']['quote'][0]['close'];

        for (int i = 0; i < timestamps.length; i++) {
          if (closePrices[i] != null) {
            DateTime dt = DateTime.fromMillisecondsSinceEpoch(
              timestamps[i] * 1000,
            );
            history[dt.toIso8601String()] = (closePrices[i] as num).toDouble();
          }
        }
      }
    } catch (e) {}

    if (history.isNotEmpty) {
      PriceCache.setHistory(cacheKey, history);
    }

    return history;
  }
}