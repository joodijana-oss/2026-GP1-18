import 'package:flutter/services.dart';

import 'job_postings.dart';

class JobMarketService {
  static const String _jobsPath =
    'lib/assets/data/Masra_Career_Analysis_Jobs_881_Title_Cleaned.csv';
  // =========================================================
  // GET RELEVANT JOBS
  // =========================================================

  Future<List<Map<String, String>>> getRelevantJobs(
    String careerGoalId, {
    int limit = 25,
  }) async {
    final csvText = await rootBundle.loadString(
      _jobsPath,
    );

    return JobPostings.relevant(
      csvText,
      careerGoalId,
      limit: limit,
    );
  }

  // =========================================================
  // BUILD TEXT FOR CLAUDE
  // =========================================================

  Future<String> getRelevantJobMarketText(
    String careerGoalId, {
    int limit = 20,
  }) async {
    final jobs =
        await getRelevantJobs(
      careerGoalId,
      limit: limit,
    );

    if (jobs.isEmpty) {
      return '';
    }

    final buffer =
        StringBuffer();

    for (int i = 0;
        i < jobs.length;
        i++) {
      final job = jobs[i];

      buffer.writeln(
        'JOB ${i + 1}',
      );

      buffer.writeln(
        'Title: ${job['title'] ?? ''}',
      );

      final city =
          job['city'] ?? '';

      if (city.isNotEmpty) {
        buffer.writeln(
          'City: $city',
        );
      }

      buffer.writeln(
        'Description:',
      );

      buffer.writeln(
        job['description'] ?? '',
      );

      buffer.writeln(
        '------------------------------',
      );
    }

    return buffer.toString();
  }

  // =========================================================
  // GET RELEVANT JOB COUNT
  // =========================================================

  Future<int> getRelevantJobCount(
    String careerGoalId,
  ) async {
    final jobs =
        await getRelevantJobs(
      careerGoalId,
      limit: 881,
    );

    return jobs.length;
  }
}
