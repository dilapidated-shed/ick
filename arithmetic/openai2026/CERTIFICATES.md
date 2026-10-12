# Precision certificates for the admitted resampling profiles

The component admits p=101..256, 2<=s<t<=64, coprime s,t, integer alpha>=2,
alpha^2<p and (t-s)alpha^4>ps. Preparation is limited to 65,536 coefficient
slots. These are numerical correctness profiles. The checked schoolbook
products and bounded series do not establish the cited asymptotic running time.

Every private interval has directed dyadic endpoints at p+64 bits. Exact
products use checked 32-bit magnitude limbs; division and discarded bits are
rounded separately downward and upward. Intermediate storage is limited to
1,024 bits. Failure to enclose, narrow, represent or store a result is explicit.

Pi is enclosed by Machin's 16 atan(1/5)-4 atan(1/239), using alternating
series and the next-term remainder. Log 2 is enclosed by 2 atanh(1/3), using
the positive series and a 9/8 next-term geometric remainder. Both interval
widths must be below 2^-(p+32). Their independent reference uses Euler's
positive arctangent series and sum 1/(n 2^n) at p+128 bits.

For negative exponentials, j>kp takes the proved small-value branch. Otherwise
an interval for pi*j/k is reduced by tau*log 2 with a checked nonnegative
remainder at most 2 log 2. The alternating exponential series includes a
next-term enclosure, followed by a directed shift. Its final width must be
below 2^-(p+16); truncating the lower endpoint gives error strictly below two
p-grid units. Scaled positive exponentials first enclose sigma*log 2-pi*j/k
and refuse if nonnegativity cannot be certified. This implements the scaled
positive case needed by D' without an untrusted exponential.

Roots use quarter reduction to an angle at most pi/4, bounded sine/cosine
series, and Lemma 2.12's inward exponential exp(-2^-(p+2)). Exact squared
distances to the analytic rectangle must be below 4*2^(-2p), and the returned
grid point must lie in the closed unit disk. The independent reference uses
a smaller angle and four complex doublings; it does not use the candidate's
quarter reduction or series.

Let mA=ceil(sqrt(p))*alpha, mE=ceil(sqrt(p)/(2alpha)), and
n=ceil(ps/(alpha^2(t-s))). A follows Lemma 4.9 term by term: a p-grid beta,
certified Gaussian, grid coefficient product, grid input product, then exact
summation. The Gaussian tail is below one grid unit; the total error is below
14mA+1<16p<p^2. The constructor checks this strict inequality.

E follows Lemma 4.11 with 2mE terms and the certified Gaussian exponent
alpha^2*((th/s+beta_l)^2-beta_(l+h)^2). Its tail is below three grid units,
and its error is below 8mE+3<p/3. C scans ordered coordinates, selecting the
nearest tj/s with ties upward. J' starts with the grid truncation of u/2,
applies E successively, and accumulates the n alternating terms. The exact
E norm is below one half and its n-th-power tail is below one grid unit.
Thus the J' error is below 2np/3+1<3p^2/4. D' adds less than four grid units,
so B0=D' J' C has error below 4+3p^2/4<p^2. Disk membership is checked at
completed outputs, and invalid capacity or aliasing leaves all outputs intact.

The independent line reference directly sums wider Gaussian kernels and
encloses a longer inverse matrix. It checks the row norm below one half and
adds the geometric inverse remainder. The comparison does not call any
candidate routine. Tensor lines compose contractions: A0 then A1 has error
below 2p^2 grid units, and B1 then B0 following A has error below 4p^2.
The padded box preserves every unused zero and all prefix/suffix slots.

The retained permutations are checked in the identity
Ps Fs = 2^(2alpha^2) B0 Pt Ft A. A normalized quadratic DFT is used only by
the verification fixture, not by A/B0 or a claimed fast transform. Its root,
product and averaging errors are below 4t grid units, so the identity gate
allows the explicit amplified bound 2^(2alpha^2)(2p^2+4t)2^-p. Dependent
integer recovery must account for that amplification and cannot reuse the
unamplified line bound.

The source recipes are the pinned author's 45-page manuscript, Lemmas
2.12–2.14 and 4.8–4.12; SHA256
7acbf5bea9dd45a2fca79d8b4673df6b8329ba8ad039831a40b44ae70944f813.
