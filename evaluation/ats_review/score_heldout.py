# Applies the ATS decision rule (tools/ats_eval/decision_rule.txt) to the
# blind grades after unblinding.
# Usage: python evaluation/ats_review/score_heldout.py evaluation/ats_review/grades
#
# Correction: the copy used for the decision compared the recall gain with
# 0.300 (10 * gain >= 3 * 78) instead of the rule's 0.100. The gain was
# -8/78 = -0.103, which fails both limits, so the decision (keep OLD) is the
# same. This copy uses the rule's 0.100.
import csv, json, sys
from fractions import Fraction as F
from itertools import combinations
from collections import defaultdict

root = sys.argv[1]
mapping = json.load(open(root + '/grading_mapping.json', encoding='utf-8'))['cvs']
ver = {}
for cv, d in mapping.items():
    for lab, v in d['labels'].items():
        ver[lab] = (v['version'], v['run'], v['answered'])

planted = {'ho_a': 10, 'ho_b': 10, 'ho_d': 6}
GOOD = {'PLANTED', 'NEUTRAL'}
BAD = {'WRONG', 'PADDED', 'FINE_FLAGGED', 'DUPLICATE'}

# Held-out flawed: grades_flawed.csv (one row per issue)
issues = defaultdict(list)
for r in csv.DictReader(open(root + '/grades_flawed.csv', encoding='utf-8')):
    issues[r['label']].append(r)

lab_stats = {}
for lab, rows in issues.items():
    found, points, good, bad, n, inv, mis = set(), set(), 0, 0, 0, 0, 0
    for r in rows:
        v = r['verdict'].strip()
        if v in ('EMPTY', 'ARTIFACT'):
            continue
        n += 1
        if v in GOOD: good += 1
        elif v in BAD: bad += 1
        else: raise SystemExit('unknown verdict ' + v)
        if v == 'PLANTED':
            for c in r['credits'].replace(';', ' ').replace(',', ' ').split():
                found.add(c.strip())
        for p in r['point'].replace(';', ' ').replace(',', ' ').split():
            points.add(p.strip())
        try: inv += int(r['invented_facts'] or 0)
        except ValueError: inv += 1
        try: mis += int(r['misquotes'] or 0)
        except ValueError: mis += 1
    lab_stats[lab] = dict(found=found, points=points, good=good, n=n, inv=inv, mis=mis)

# Held-out clean ho_c: from grades_clean_dev.md section 1 (Real(key)/Real(notkey)/Neutral = good;
# False/Padding = bad, i.e. WRONG/PADDED/FINE_FLAGGED in the rule's terms). Inv-major + Inv-date both count.
hoc = {
 'ho_c_01': dict(points={'ORDER','C1'}, good=2, n=2, inv=0, mis=0),
 'ho_c_02': dict(points={'ORDER','C1','DATEFMT'}, good=2, n=3, inv=1, mis=0),
 'ho_c_03': dict(points={'ORDER','C1'}, good=2, n=2, inv=1, mis=0),
 'ho_c_04': dict(points={'ORDER','C1'}, good=2, n=2, inv=0, mis=0),
 'ho_c_05': dict(points={'ORDER','C1','DATAMODEL','STATSPEC','DATEFMT'}, good=2, n=5, inv=0, mis=0),
 'ho_c_06': dict(points={'ORDER','C1','DATEFMT'}, good=2, n=3, inv=0, mis=0),
}
for k, v in hoc.items():
    v['found'] = set(); lab_stats[k] = v

def jac(a, b):
    if not a and not b: return F(1)
    return F(len(a & b), len(a | b))

res = {}
for version in ('old', 'new'):
    labs = {cv: sorted(l for l in mapping[cv]['labels'] if ver[l][0] == version) for cv in ('ho_a','ho_b','ho_c','ho_d')}
    found = sum(len([p for p in lab_stats[l]['found'] if p[0] == cv[3].upper()]) for cv in planted for l in labs[cv])
    per_cv_found = {cv: [len(lab_stats[l]['found']) for l in labs[cv]] for cv in planted}
    good = sum(lab_stats[l]['good'] for cv in labs for l in labs[cv])
    n = sum(lab_stats[l]['n'] for cv in labs for l in labs[cv])
    inv = sum(lab_stats[l]['inv'] for cv in labs for l in labs[cv])
    mis = sum(lab_stats[l]['mis'] for cv in labs for l in labs[cv])
    hoc_bad = sum(lab_stats[l]['n'] - lab_stats[l]['good'] for l in labs['ho_c'])
    cons_cv = {}
    for cv in labs:
        pairs = list(combinations(labs[cv], 2))
        cons_cv[cv] = sum(jac(lab_stats[a]['points'], lab_stats[b]['points']) for a, b in pairs) / len(pairs)
    cons = sum(cons_cv.values()) / 4
    res[version] = dict(labels=labs, found=found, total=78, per_cv_found=per_cv_found, good=good, n=n,
                        inv=inv, mis=mis, hoc_bad=hoc_bad, cons_cv={k: float(v) for k, v in cons_cv.items()},
                        cons=float(cons), cons_frac=cons)
    print(version.upper(), labs)
    print('  recall', found, '/ 78 =', round(found/78, 4), per_cv_found)
    print('  precision', good, '/', n, '=', round(good/n, 4))
    print('  invented', inv, 'misquotes', mis, 'ho_c bad', hoc_bad)
    print('  consistency per CV', {k: round(float(v), 4) for k, v in cons_cv.items()}, 'mean', round(float(cons), 4), '->', round(float(cons), 2))

o, nw = res['old'], res['new']
# (a) recall gain of at least 0.100: (found_new - found_old) / 78 >= 1/10
a = 10 * (nw['found'] - o['found']) >= 78
# precision: good_n/n_n >= good_o/n_o - 3/100  <=>  100*good_n*n_o >= (100*good_o - 3*n_o)*n_n
b = 100 * nw['good'] * o['n'] >= (100 * o['good'] - 3 * o['n']) * nw['n']
c = nw['inv'] <= o['inv'] and nw['mis'] <= o['mis']
d = nw['hoc_bad'] <= o['hoc_bad']
e = round(nw['cons'], 2) >= round(o['cons'], 2)
print('(a) recall gain', nw['found'] - o['found'], '/ 78 =', round((nw['found'] - o['found'])/78, 4), 'PASS' if a else 'FAIL')
print('(b) precision', 'PASS' if b else 'FAIL')
print('(c) invented/misquotes', 'PASS' if c else 'FAIL')
print('(d) ho_c false/padded', 'PASS' if d else 'FAIL')
print('(e) consistency', 'PASS' if e else 'FAIL')
print('DECISION:', 'ADOPT NEW' if all([a, b, c, d, e]) else 'KEEP OLD')

# sanity: totals across all 18 flawed labels
tf = sum(len(lab_stats[l]['found']) for l in issues); tg = sum(lab_stats[l]['good'] for l in issues); tn = sum(lab_stats[l]['n'] for l in issues)
print('check all 18 flawed: found', tf, 'good', tg, 'issues', tn)
for l in sorted(issues): print(' ', l, ver[l][0], 'found', len(lab_stats[l]['found']), sorted(lab_stats[l]['found']), 'good/n', lab_stats[l]['good'], lab_stats[l]['n'], 'inv', lab_stats[l]['inv'])
