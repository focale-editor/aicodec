/// Creates straight-sided cells with an independently specified linear field.
String meshGrid({Set<int> compoundAxes = const {}, bool zeroHandles = false, bool collapsedInterior = false, double weight = 1, double opacity = 1, double Function(int, int)? color}) {
  final StringBuffer source = StringBuffer('/Mesh X!\n%_2 /Version X#\n%_/Cartesian /Type X#\n%_[2 2] /Size X#\n%_/Data X#\n');
  for (int first = 0; first < 2; first++) {
    for (int second = 0; second < 2; second++) {
      source.writeln('%_[$first $second] /P X#\n%_[-1] /R X#');
      final List<(int, int)> corners = [(first, second), (first + 1, second), (first + 1, second + 1), (first, second + 1)];
      final List<({double x, double y, int edge, bool corner, double color})> nodes = [];
      for (int edge = 0; edge < 4; edge++) {
        final (int, int) current = corners[edge];
        final (int, int) next = corners[(edge + 1) % 4];
        nodes.add((x: 3.0 * current.$1, y: 3.0 * current.$2, edge: edge, corner: true, color: color?.call(current.$1, current.$2) ?? (current.$1 + current.$2) / 4));
        if (compoundAxes.contains(edge % 2)) {
          final int across = edge.isEven ? current.$2 : current.$1;
          final double fraction = across == 0 ? 0.25 : 0.75;
          final double direction = edge < 2 ? fraction : 1 - fraction;
          nodes.add((x: 3 * (current.$1 + direction * (next.$1 - current.$1)), y: 3 * (current.$2 + direction * (next.$2 - current.$2)), edge: edge, corner: false, color: 0));
        }
      }
      for (int index = 0; index < nodes.length; index++) {
        final ({double color, bool corner, int edge, double x, double y}) node = nodes[index];
        final ({double color, bool corner, int edge, double x, double y}) previous = nodes[(index + nodes.length - 1) % nodes.length];
        final ({double color, bool corner, int edge, double x, double y}) next = nodes[(index + 1) % nodes.length];
        final bool reverse = !node.corner && node.edge < 2;
        final before = reverse ? next : previous;
        final after = reverse ? previous : next;
        final double outgoingX = zeroHandles || collapsedInterior && node.x == 3 ? node.x : (2 * node.x + after.x) / 3;
        final double outgoingY = zeroHandles ? node.y : (2 * node.y + after.y) / 3;
        final double incomingX = zeroHandles || collapsedInterior && node.x == 3 ? node.x : (2 * node.x + before.x) / 3;
        final double incomingY = zeroHandles ? node.y : (2 * node.y + before.y) / 3;
        final List<double> values = node.corner
            ? [node.color, opacity, node.x, node.y, outgoingX, outgoingY, weight, incomingX, incomingY, weight]
            : [node.x, node.y, outgoingX, outgoingY, incomingX, incomingY, weight];
        final String operator = node.corner
            ? 'N'
            : node.edge.isEven
            ? 'A'
            : 'S';
        source.writeln('%_[${values.map(_number).join(' ')}] /$operator X#');
      }
      source.writeln('%_/E X#');
    }
  }
  source.write('/End X!');
  return source.toString();
}

/// Keeps fixture lexemes identical on the VM and JavaScript runtimes.
String _number(double value) => value == value.truncateToDouble() ? value.toStringAsFixed(1) : value.toString();
