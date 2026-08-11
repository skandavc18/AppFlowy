import 'package:flutter/material.dart';

/// One insertable piece of LaTeX.
///
/// `$0` marks where the caret should land after insertion, so a fraction
/// arrives ready to type into rather than needing the caret moved by hand.
class MathSymbol {
  const MathSymbol(this.preview, this.latex, {this.label});

  /// What the button shows — rendered as TeX unless [label] is given.
  final String preview;
  final String latex;

  /// Plain words shown instead of a rendered preview, for symbols whose
  /// glyph means nothing on its own.
  final String? label;
}

class MathSymbolGroup {
  const MathSymbolGroup(this.name, this.icon, this.symbols);

  final String name;
  final IconData icon;
  final List<MathSymbol> symbols;
}

/// The palette offered under the LaTeX editor.
///
/// It exists to make the constructs people forget the syntax for reachable —
/// which means it has to cover the whole of what somebody writing maths
/// actually reaches for, not a token sample of it.
const kMathSymbolGroups = <MathSymbolGroup>[
  MathSymbolGroup('Structure', Icons.calculate_rounded, [
    MathSymbol(r'\frac{a}{b}', r'\frac{$0}{}'),
    MathSymbol('x^{2}', r'^{$0}'),
    MathSymbol('x_{i}', r'_{$0}'),
    MathSymbol('x_{i}^{2}', r'_{$0}^{}'),
    MathSymbol(r'\sqrt{x}', r'\sqrt{$0}'),
    MathSymbol(r'\sqrt[n]{x}', r'\sqrt[$0]{}'),
    MathSymbol(r'\left(x\right)', r'\left($0\right)'),
    MathSymbol(r'\left[x\right]', r'\left[$0\right]'),
    MathSymbol(r'\left\{x\right\}', r'\left\{$0\right\}'),
    MathSymbol('|x|', r'\left|$0\right|'),
    MathSymbol(r'\|x\|', r'\left\|$0\right\|'),
    MathSymbol(r'\binom{n}{k}', r'\binom{$0}{}'),
    MathSymbol(r'\vec{v}', r'\vec{$0}'),
    MathSymbol(r'\hat{x}', r'\hat{$0}'),
    MathSymbol(r'\bar{x}', r'\bar{$0}'),
    MathSymbol(r'\dot{x}', r'\dot{$0}'),
    MathSymbol(r'\tilde{x}', r'\tilde{$0}'),
    MathSymbol(r'\text{abc}', r'\text{$0}'),
  ]),
  MathSymbolGroup('Calculus', Icons.show_chart_rounded, [
    MathSymbol(r'\frac{dy}{dx}', r'\frac{d$0}{dx}'),
    MathSymbol(r'\frac{d^{2}y}{dx^{2}}', r'\frac{d^{2}$0}{dx^{2}}'),
    MathSymbol("f'(x)", r"f'($0)"),
    MathSymbol(r'\partial', r'\partial'),
    MathSymbol(
      r'\frac{\partial f}{\partial x}',
      r'\frac{\partial $0}{\partial x}',
    ),
    MathSymbol(r'\nabla', r'\nabla'),
    MathSymbol(r'\int', r'\int $0 \,dx'),
    MathSymbol(r'\int_{a}^{b}', r'\int_{$0}^{} \,dx'),
    // The renderer draws every multiple integral as a single sign, so these
    // three are labelled with their own glyph to stay tellable apart.
    MathSymbol(r'\iint', r'\iint_{D} $0 \,dA', label: '∬'),
    MathSymbol(r'\iiint', r'\iiint_{V} $0 \,dV', label: '∭'),
    MathSymbol(r'\oint', r'\oint_{C} $0', label: '∮'),
    MathSymbol(r'\lim_{x \to 0}', r'\lim_{$0 \to 0} '),
    MathSymbol(r'\to', r'\to'),
    MathSymbol(r'\infty', r'\infty'),
    MathSymbol(r'\mathrm{d}x', r'\,\mathrm{d}$0'),
  ]),
  MathSymbolGroup('Operators', Icons.functions_rounded, [
    MathSymbol(r'\sum', r'\sum_{i=1}^{n} $0'),
    MathSymbol(r'\prod', r'\prod_{i=1}^{n} $0'),
    MathSymbol(r'\coprod', r'\coprod_{i=1}^{n} $0'),
    MathSymbol(r'\bigcup', r'\bigcup_{i=1}^{n} $0'),
    MathSymbol(r'\bigcap', r'\bigcap_{i=1}^{n} $0'),
    MathSymbol(r'\pm', r'\pm'),
    MathSymbol(r'\mp', r'\mp'),
    MathSymbol(r'\times', r'\times'),
    MathSymbol(r'\div', r'\div'),
    MathSymbol(r'\cdot', r'\cdot'),
    MathSymbol(r'\ast', r'\ast'),
    MathSymbol(r'\circ', r'\circ'),
    MathSymbol(r'\oplus', r'\oplus'),
    MathSymbol(r'\otimes', r'\otimes'),
    MathSymbol(r'\sin', r'\sin($0)'),
    MathSymbol(r'\cos', r'\cos($0)'),
    MathSymbol(r'\tan', r'\tan($0)'),
    MathSymbol(r'\log', r'\log($0)'),
    MathSymbol(r'\ln', r'\ln($0)'),
    MathSymbol(r'\exp', r'\exp($0)'),
  ]),
  MathSymbolGroup('Relations', Icons.compare_arrows_rounded, [
    MathSymbol('=', '='),
    MathSymbol(r'\neq', r'\neq'),
    MathSymbol(r'\leq', r'\leq'),
    MathSymbol(r'\geq', r'\geq'),
    MathSymbol(r'\ll', r'\ll'),
    MathSymbol(r'\gg', r'\gg'),
    MathSymbol(r'\approx', r'\approx'),
    MathSymbol(r'\sim', r'\sim'),
    MathSymbol(r'\simeq', r'\simeq'),
    MathSymbol(r'\cong', r'\cong'),
    MathSymbol(r'\equiv', r'\equiv'),
    MathSymbol(r'\propto', r'\propto'),
    MathSymbol(r'\rightarrow', r'\rightarrow'),
    MathSymbol(r'\leftarrow', r'\leftarrow'),
    MathSymbol(r'\Rightarrow', r'\Rightarrow'),
    MathSymbol(r'\Leftrightarrow', r'\Leftrightarrow'),
    MathSymbol(r'\mapsto', r'\mapsto'),
    MathSymbol(r'\therefore', r'\therefore'),
    MathSymbol(r'\because', r'\because'),
  ]),
  MathSymbolGroup('Sets & logic', Icons.join_inner_rounded, [
    MathSymbol(r'\in', r'\in'),
    MathSymbol(r'\notin', r'\notin'),
    MathSymbol(r'\ni', r'\ni'),
    MathSymbol(r'\subset', r'\subset'),
    MathSymbol(r'\subseteq', r'\subseteq'),
    MathSymbol(r'\supset', r'\supset'),
    MathSymbol(r'\supseteq', r'\supseteq'),
    MathSymbol(r'\cup', r'\cup'),
    MathSymbol(r'\cap', r'\cap'),
    MathSymbol(r'\setminus', r'\setminus'),
    MathSymbol(r'\emptyset', r'\emptyset'),
    MathSymbol(r'\mathbb{N}', r'\mathbb{N}'),
    MathSymbol(r'\mathbb{Z}', r'\mathbb{Z}'),
    MathSymbol(r'\mathbb{Q}', r'\mathbb{Q}'),
    MathSymbol(r'\mathbb{R}', r'\mathbb{R}'),
    MathSymbol(r'\mathbb{C}', r'\mathbb{C}'),
    MathSymbol(r'\forall', r'\forall'),
    MathSymbol(r'\exists', r'\exists'),
    MathSymbol(r'\nexists', r'\nexists'),
    MathSymbol(r'\neg', r'\neg'),
    MathSymbol(r'\land', r'\land'),
    MathSymbol(r'\lor', r'\lor'),
  ]),
  MathSymbolGroup('Greek', Icons.text_fields_rounded, [
    MathSymbol(r'\alpha', r'\alpha'),
    MathSymbol(r'\beta', r'\beta'),
    MathSymbol(r'\gamma', r'\gamma'),
    MathSymbol(r'\delta', r'\delta'),
    MathSymbol(r'\epsilon', r'\epsilon'),
    MathSymbol(r'\varepsilon', r'\varepsilon'),
    MathSymbol(r'\zeta', r'\zeta'),
    MathSymbol(r'\eta', r'\eta'),
    MathSymbol(r'\theta', r'\theta'),
    MathSymbol(r'\kappa', r'\kappa'),
    MathSymbol(r'\lambda', r'\lambda'),
    MathSymbol(r'\mu', r'\mu'),
    MathSymbol(r'\nu', r'\nu'),
    MathSymbol(r'\xi', r'\xi'),
    MathSymbol(r'\pi', r'\pi'),
    MathSymbol(r'\rho', r'\rho'),
    MathSymbol(r'\sigma', r'\sigma'),
    MathSymbol(r'\tau', r'\tau'),
    MathSymbol(r'\phi', r'\phi'),
    MathSymbol(r'\varphi', r'\varphi'),
    MathSymbol(r'\chi', r'\chi'),
    MathSymbol(r'\psi', r'\psi'),
    MathSymbol(r'\omega', r'\omega'),
    MathSymbol(r'\Gamma', r'\Gamma'),
    MathSymbol(r'\Delta', r'\Delta'),
    MathSymbol(r'\Theta', r'\Theta'),
    MathSymbol(r'\Lambda', r'\Lambda'),
    MathSymbol(r'\Sigma', r'\Sigma'),
    MathSymbol(r'\Phi', r'\Phi'),
    MathSymbol(r'\Psi', r'\Psi'),
    MathSymbol(r'\Omega', r'\Omega'),
  ]),
  MathSymbolGroup('Matrices', Icons.grid_on_rounded, [
    MathSymbol(
      r'\begin{pmatrix}a&b\\c&d\end{pmatrix}',
      '\\begin{pmatrix}\n  \$0 & \\\\\n   & \n\\end{pmatrix}',
    ),
    MathSymbol(
      r'\begin{bmatrix}a&b\\c&d\end{bmatrix}',
      '\\begin{bmatrix}\n  \$0 & \\\\\n   & \n\\end{bmatrix}',
    ),
    MathSymbol(
      r'\begin{vmatrix}a&b\\c&d\end{vmatrix}',
      '\\begin{vmatrix}\n  \$0 & \\\\\n   & \n\\end{vmatrix}',
    ),
    MathSymbol(
      r'\begin{Bmatrix}a&b\\c&d\end{Bmatrix}',
      '\\begin{Bmatrix}\n  \$0 & \\\\\n   & \n\\end{Bmatrix}',
    ),
    MathSymbol(
      r'\begin{cases}a\\b\end{cases}',
      '\\begin{cases}\n  \$0 & \\text{if } \\\\\n   & \\text{otherwise}\n\\end{cases}',
    ),
    MathSymbol(
      r'\begin{aligned}a&=b\end{aligned}',
      '\\begin{aligned}\n  \$0 &= \\\\\n   &= \n\\end{aligned}',
    ),
    MathSymbol(r'\cdots', r'\cdots'),
    MathSymbol(r'\vdots', r'\vdots'),
    MathSymbol(r'\ddots', r'\ddots'),
    MathSymbol(r'\\', r'\\ ', label: 'Row'),
    MathSymbol('&', ' & ', label: 'Cell'),
  ]),
];

/// Splices a snippet into [source] at [selection], answering the new text and
/// where the caret should land.
({String text, int caret}) insertMathSymbol(
  String source,
  TextSelection selection,
  String snippet,
) {
  final valid = selection.isValid &&
      selection.start >= 0 &&
      selection.end <= source.length;
  final start = valid ? selection.start : source.length;
  final end = valid ? selection.end : source.length;
  final selected = source.substring(start, end);

  final placeholder = snippet.indexOf(r'$0');
  final body =
      placeholder < 0 ? snippet : snippet.replaceFirst(r'$0', selected);
  final text = source.replaceRange(start, end, body);
  final caret = placeholder < 0
      ? start + body.length
      : start + placeholder + selected.length;
  return (text: text, caret: caret);
}
