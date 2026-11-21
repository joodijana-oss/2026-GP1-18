import 'package:flutter_test/flutter_test.dart';
import 'package:masra/features/opportunities/opportunities_screen.dart';

// The Opportunity Radar note "No opportunity in our catalog covers X and Y
// yet." joins the skill names with "and", not with commas only.

void main() {
  test('one name is used as it is', () {
    expect(joinWithAnd(['Splunk']), 'Splunk');
  });

  test('two names are joined with "and"', () {
    expect(joinWithAnd(['Splunk', 'NoSQL']), 'Splunk and NoSQL');
  });

  test('three or more names get commas and ", and" before the last', () {
    expect(joinWithAnd(['Splunk', 'NoSQL', 'C++']), 'Splunk, NoSQL, and C++');
    expect(joinWithAnd(['A', 'B', 'C', 'D']), 'A, B, C, and D');
  });

  test('no names give an empty text', () {
    expect(joinWithAnd([]), '');
  });
}
