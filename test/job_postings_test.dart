import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masra/services/job_postings.dart';

const String csvText = '''
cleaned_title,cleaned_description,normalized_city,normalized_source
Senior Software Engineer,Builds backend services.,Riyadh,linkedin
RF Engineer,Plans radio coverage.,Jeddah,bayt
Surf Instructor,Teaches surfing.,Jeddah,bayt
Software Engineer II,Maintains the mobile API.,,linkedin
Telecom Engineer,,Riyadh,bayt
QA Engineer,Writes test plans.,Dammam,linkedin
Software Engineering Manager,Leads two squads.,Riyadh,bayt
''';

/// A one-row dataset for [title]. Built with the csv encoder, so a title
/// with a comma stays one cell.
String oneRow(String title) => csv.encode([
      [
        'cleaned_title',
        'cleaned_description',
        'normalized_city',
        'normalized_source',
      ],
      [title, 'A made-up posting.', '', 'test'],
    ]);

// Made-up titles: goal, title, whether the title names a job of the goal.
const List<(String, String, bool)> titleCases = [
  // The alias sits only inside a longer word: must not match.
  ('ai_ml_engineer', 'Facilities Manager, Applied AI Engineering', false),
  ('ai_ml_engineer', 'HTML Engineer', false),
  ('mobile_developer', 'BIOS Developer', false),
  ('cybersecurity_analyst', 'Diamond Grading Specialist', false),
  ('database_administrator', 'Customer Feedback Coordinator', false),
  ('it_consultant', 'Internal Audit Consultant', false),
  ('it_project_manager', 'Audit Program Manager', false),
  ('cloud_devops_engineer', 'Office Manager - Platform Engineering', false),
  ('network_engineer', 'Recruiter, Network Engineering', false),
  ('systems_administrator', 'Partner Ecosystem Engineer', false),
  // The shape of the reported title: "&", an en dash and a team name.
  ('ai_ml_engineer', 'Power & Cooling Lead – Edge AI Engineering', false),
  // Whole words, and a plural "s" on the last word: must match.
  ('ai_ml_engineer', 'Lead AI Engineer, Retail Analytics', true),
  ('ai_ml_engineer', 'AI/ML Engineer (Hybrid)', true),
  ('ai_ml_engineer', 'Senior Machine Learning Engineers (2 Openings)', true),
  ('ai_ml_engineer', 'Generative AI Solutions Lead', true),
  ('software_engineer', 'Embedded Software Engineers', true),
  ('data_scientist', 'Data Scientists - Fraud Analytics', true),
  ('solutions_architect', 'Enterprise Architects (Banking)', true),
  ('qa_test_engineer', 'Manual Testers', true),
  ('mobile_developer', 'iOS Developer (Swift)', true),
  ('cybersecurity_analyst', 'IAM Analyst', true),
  // Separators that real titles use: " & ", an en dash and a colon.
  ('ai_ml_engineer', 'Data & AI Engineer – Payments', true),
  ('ai_ml_engineer', 'AI Engineer: Search Ranking', true),
];

void main() {
  for (final (goal, title, isJob) in titleCases) {
    test('$goal ${isJob ? 'matches' : 'does not match'} "$title"', () {
      final jobs = JobPostings.relevant(oneRow(title), goal);
      if (isJob) {
        expect(jobs, hasLength(1));
        expect(jobs.single['title'], title);
      } else {
        expect(jobs, isEmpty);
      }
    });
  }

  test('an alias matches whole words, not inside a longer word', () {
    final jobs = JobPostings.relevant(csvText, 'software_engineer');
    // "Software Engineering Manager" does not match "software engineer":
    // "engineering" is another word.
    expect([for (final job in jobs) job['title']], [
      'Senior Software Engineer',
      'Software Engineer II',
    ]);
    expect(jobs.first, {
      'title': 'Senior Software Engineer',
      'description': 'Builds backend services.',
      'city': 'Riyadh',
      'source': 'linkedin',
    });
  });

  test('a short alias does not match inside another word', () {
    // "rf" must not match "Surf"; the posting without a description is
    // skipped.
    final jobs = JobPostings.relevant(csvText, 'telecom_engineer');
    expect([for (final job in jobs) job['title']], ['RF Engineer']);
  });

  test('aliasMatches reads whole words, in order, with a plural "s"', () {
    expect(JobPostings.aliasMatches('ai engineers', 'ai engineer'), isTrue);
    expect(JobPostings.aliasMatches('ai engineering', 'ai engineer'), isFalse);
    expect(JobPostings.aliasMatches('ai engineered', 'ai engineer'), isFalse);
    // Wrong order.
    expect(JobPostings.aliasMatches('engineer ai', 'ai engineer'), isFalse);
    expect(JobPostings.aliasMatches('surf instructor', 'rf'), isFalse);
    // An empty alias matches nothing, not even a lone "s".
    expect(JobPostings.aliasMatches('senior engineer s', ''), isFalse);
  });

  test('the limit keeps the first postings of the file', () {
    final jobs = JobPostings.relevant(csvText, 'software_engineer', limit: 1);
    expect(jobs, hasLength(1));
    expect(jobs.single['title'], 'Senior Software Engineer');
  });

  test('an unknown career goal is an error, as before', () {
    expect(() => JobPostings.relevant(csvText, 'chef'), throwsException);
  });

  test('missing columns are an error, as before', () {
    expect(
      () => JobPostings.relevant('title,text\nA,B\n', 'software_engineer'),
      throwsException,
    );
  });

  test('the market text lists each posting, and the city when known', () {
    final text = JobPostings.marketText(
        JobPostings.relevant(csvText, 'software_engineer', limit: 2));
    expect(
      text,
      'JOB 1\n'
      'Title: Senior Software Engineer\n'
      'City: Riyadh\n'
      'Description:\n'
      'Builds backend services.\n'
      '------------------------------\n'
      'JOB 2\n'
      'Title: Software Engineer II\n'
      'Description:\n'
      'Maintains the mobile API.\n'
      '------------------------------\n',
    );
  });
}
