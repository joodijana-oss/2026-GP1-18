import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/opportunity.dart';

/// Reads learning opportunities (Tuwaiq Academy, Doroob, Coursera) from the
/// Firestore `opportunities` collection.
///
/// Only English documents (`language == 'en'`) are read; the old Arabic
/// documents have no `language` field, so the query skips them.
/// If Firestore cannot be reached (offline, rules, timeout, nothing found),
/// it falls back to the JSON bundled with the app, so the feature still works.
class OpportunityService {
  static const String _collection = 'opportunities';
  static const String _assetPath = 'lib/assets/data/Masra_Opportunities.json';
  static const Duration _timeout = Duration(seconds: 15);

  // Shared across instances so the list is fetched once per app session.
  static List<Opportunity>? _cache;

  final FirebaseFirestore? _injectedDb;

  OpportunityService({FirebaseFirestore? db}) : _injectedDb = db;

  // Read only when needed, so the asset fallback still works when
  // Firebase is not set up (for example in widget tests).
  FirebaseFirestore get _db => _injectedDb ?? FirebaseFirestore.instance;

  // ---------------------------------------------------------
  // ALL OPPORTUNITIES
  // ---------------------------------------------------------

  Future<List<Opportunity>> getAll({
    bool forceRefresh = false,
  }) async {
    final cached = _cache;
    if (!forceRefresh && cached != null) {
      return cached;
    }

    List<Opportunity> result;
    try {
      final snapshot = await _db
          .collection(_collection)
          .where('language', isEqualTo: 'en')
          .get()
          .timeout(_timeout);
      result = snapshot.docs
          // Documents switched off with isActive: false are not shown.
          .where((doc) => doc.data()['isActive'] != false)
          .map((doc) => Opportunity.fromMap(doc.id, doc.data()))
          .where((o) => o.id.isNotEmpty && o.title.isNotEmpty)
          .toList();
      if (result.isEmpty) {
        result = await _loadFromAsset();
      }
    } catch (e) {
      debugPrint('OpportunityService: Firestore failed, using JSON ($e)');
      result = await _loadFromAsset();
    }

    _cache = result;
    return result;
  }

  // ---------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------

  Future<List<Opportunity>> _loadFromAsset() async {
    return parseJson(await rootBundle.loadString(_assetPath));
  }

  /// Parses the opportunities JSON text, a list of records (public so it
  /// can be unit-tested). Records without an id or title are skipped.
  static List<Opportunity> parseJson(String text) {
    if (text.startsWith('﻿')) {
      text = text.substring(1); // saved with a BOM by some editors
    }

    final decoded = jsonDecode(text);
    if (decoded is! List) return [];

    final result = <Opportunity>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final opportunity =
          Opportunity.fromMap('', Map<String, dynamic>.from(item));
      if (opportunity.id.isNotEmpty && opportunity.title.isNotEmpty) {
        result.add(opportunity);
      }
    }
    return result;
  }
}
