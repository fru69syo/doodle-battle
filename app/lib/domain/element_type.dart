/// Element type (ぞくせい) derived from the dominant colour of a drawing.
enum ElementType {
  fire('ほのお'),
  water('みず'),
  leaf('くさ'),
  thunder('かみなり'),
  shadow('かげ'),
  rainbow('にじ');

  const ElementType(this.label);

  /// Hiragana label shown to children.
  final String label;

  static ElementType fromName(String name) =>
      ElementType.values.firstWhere((e) => e.name == name);
}
