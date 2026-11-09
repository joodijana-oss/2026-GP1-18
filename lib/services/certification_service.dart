import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/certification.dart';

/// Reads IT certifications from the Firestore `certifications` collection.
///
/// If Firestore cannot be reached (offline, rules, empty collection), it
/// falls back to the CSV bundled with the app, so the feature still works.
class CertificationService {
  static const String _collection = 'certifications';
  static const String _assetPath =
      'lib/assets/data/Masra_IT_Certifications.csv';

  // Shared across instances so the list is fetched once per app session.
  static List<Certification>? _cache;

  final FirebaseFirestore _db;

  CertificationService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  // ---------------------------------------------------------
  // ALL CERTIFICATIONS
  // ---------------------------------------------------------

  Future<List<Certification>> getAll({
    bool forceRefresh = false,
  }) async {
    final cached = _cache;
    if (!forceRefresh && cached != null) {
      return cached;
    }

    List<Certification> result;
    try {
      final snapshot = await _db.collection(_collection).get();
      result = snapshot.docs
          .map((doc) => Certification.fromFirestore(doc.id, doc.data()))
          .toList();
      if (result.isEmpty) {
        result = await _loadFromAsset();
      }
    } catch (e) {
      debugPrint('CertificationService: Firestore failed, using CSV ($e)');
      result = await _loadFromAsset();
    }

    result.sort(_byLevelThenName);
    _cache = result;
    return result;
  }

  // ---------------------------------------------------------
  // FILTERS
  // ---------------------------------------------------------

  /// Certifications that fit a career goal (ids from careerPaths.json),
  /// optionally limited to one level (Beginner / Intermediate / Advanced).
  Future<List<Certification>> getForCareerPath(
    String careerGoalId, {
    String? level,
  }) async {
    final all = await getAll();
    return all
        .where((c) => c.careerPaths.contains(careerGoalId))
        .where((c) => level == null || c.level == level)
        .toList();
  }

  Future<List<Certification>> getByCategory(String category) async {
    final all = await getAll();
    return all.where((c) => c.category == category).toList();
  }

  Future<Certification?> getById(String id) async {
    final all = await getAll();
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }

  // ---------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------

  Future<List<Certification>> _loadFromAsset() async {
    return parseCsv(await rootBundle.loadString(_assetPath));
  }

  /// Parses the certifications CSV text (public so it can be unit-tested).
  static List<Certification> parseCsv(String text) {
    if (text.startsWith('﻿')) {
      text = text.substring(1); // the CSV is saved with a BOM for Excel
    }

    // autoDetect off: some fields contain ';' which could confuse detection.
    final rows = Csv(autoDetect: false).decode(text);
    if (rows.isEmpty) return [];

    final header = rows.first.map((v) => v.toString().trim()).toList();
    final result = <Certification>[];
    for (final row in rows.skip(1)) {
      if (row.length != header.length) continue;
      final map = <String, String>{
        for (var i = 0; i < header.length; i++)
          header[i]: row[i].toString().trim(),
      };
      if ((map['id'] ?? '').isNotEmpty) {
        result.add(Certification.fromCsvRow(map));
      }
    }
    return result;
  }

  static int _byLevelThenName(Certification a, Certification b) {
    final byLevel = a.levelRank.compareTo(b.levelRank);
    if (byLevel != 0) return byLevel;
    final byVerified = (b.verified ? 1 : 0).compareTo(a.verified ? 1 : 0);
    if (byVerified != 0) return byVerified;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }
}
