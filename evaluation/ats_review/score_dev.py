# Development numbers of the ATS review (reported only, never decided).
# The sets below are the planted problems (P1..P12) and listed weaknesses
# (W1..W9) that each development output credited, copied from
# grades/grades_clean_dev.md and grades/grades_flawed.md.
# Usage: python evaluation/ats_review/score_dev.py
from fractions import Fraction as F
from itertools import combinations
P = lambda s: set(s.split())
fl = {'01': P('P1 P3 P4 P6 P8 P10 P11 P12'), '03': P('P1 P4 P7 P8 P11 P12'), '06': P('P1 P3 P4 P6 P7 P9 P11 P12'),
      '02': P('P1 P2 P3 P4 P6 P7 P8 P9 P10 P12'), '04': P('P1 P2 P3 P4 P6 P7 P8 P9 P10 P11 P12'), '05': P('P1 P2 P3 P4 P5 P6 P7 P8 P9 P10 P11 P12')}
cl = {'01': P('W1 W2 W4 W5 W8 FP'), '04': P('W5 W6 W8 FP PBI'), '05': P('W5 W8 FP'),
      '02': P('W1 W4 W5 W8 FP'), '03': P('W1 W2 W4 W5 W8 FP'), '06': P('W1 W2 W4 W5 W8 FP')}
def j(a, b): return F(1) if not a and not b else F(len(a & b), len(a | b))
def mean(d, labs): pr = list(combinations(labs, 2)); return sum(j(d[a], d[b]) for a, b in pr) / len(pr)
for v, fls, cls in (('old', ['01', '03', '06'], ['01', '04', '05']), ('new', ['02', '04', '05'], ['02', '03', '06'])):
    f, c = mean(fl, fls), mean(cl, cls)
    print(v, 'flawed found', sum(len(fl[l]) for l in fls), '/36', 'clean weaknesses', sum(len([x for x in cl[l] if x.startswith('W')]) for l in cls), '/27',
          'cons flawed', round(float(f), 4), 'clean', round(float(c), 4), 'mean', round(float((f + c) / 2), 4))
