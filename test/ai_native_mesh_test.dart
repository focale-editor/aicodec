import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:illustratorkit/illustratorkit.dart';
import 'package:test/test.dart';

/// Independent version-two fixture with mixed spaces and extra boundary nodes.
const String _mesh = '''/Mesh X!
%_2 /Version X#
%_/Cartesian /Type X#
%_[1 1] /Size X#
%_/Data X#
%_[0 0] /P X#
%_[-1] /R X#
%_[0 5 0 4 0 6 1] /S X#
%_[0.25 0.5 0 0 3 0 1 0 3 1] /N X#
%_/DeviceRGB /CS X#
%_[1 0 0 1 10 0 10 3 1 7 0 1] /N X#
%_[10 5 10 4 10 6 1] /A X#
%_[[0 0 0 1 /DeviceCMYK (Black) /Separation] 1 /NChannel] /CS X#
%_[0.6 1 10 10 7 10 1 10 7 1] /N X#
%_/DeviceCMYK /CS X#
%_[0 0.5 1 0 1 0 10 0 7 1 3 10 1] /N X#
%_[(unchanged) << /unknown 3 >>] /Future X#
%_/E X#
/End X!''';

/// Wraps an independently authored packet with explicit body boundaries.
AiNativeMeshes _decode(String body, {String setup = '', String trailer = '', bool bodyOnly = false, AiNativeLimits limits = const AiNativeLimits()}) => AiNativeMeshes.decode(
  records: AiNativeRecords.decode(
    program: AiProgram.decode(
      bytes: latin1.encode('%!PS-Adobe-3.0\n%%Creator: Adobe Illustrator\n%%BeginSetup\n$setup\n%%EndSetup\n$body\n%%Trailer\n$trailer\n%%EOF\n'),
      limits: limits,
    ),
  ),
  bodyOnly: bodyOnly,
);

/// Exercises topology, source preservation, malformed packets and bounded reads.
void main() {
  test('retains mixed corner colors, cyclic intermediate nodes and unknown fields', () {
    final AiNativeMeshes decoded = _decode(_mesh);
    final AiNativeMesh mesh = decoded.meshes.single;
    final AiNativeMeshPatch patch = mesh.patches.single;
    check(mesh.version).equals(2);
    check(mesh.size).equals((first: 1, second: 1));
    check(mesh.isPrivate).isFalse();
    check(patch.firstIndex).equals(0);
    check(patch.secondIndex).equals(0);
    check(patch.nodes.map((node) => node.kind)).deepEquals(<AiNativeMeshNodeKind>[.subdivision, .corner, .corner, .anchor, .corner, .corner]);
    final AiNativeMeshNode first = patch.nodes[1];
    check(first.color).deepEquals([0.25]);
    check(first.opacity).equals(0.5);
    check(first.colorSpace!.field).isNull();
    check(first.colorSpace!.deviceName).equals('DeviceGray');
    check(first.position).equals((x: 0.0, y: 0.0));
    check(first.firstHandle).equals((x: 3.0, y: 0.0));
    check(first.secondHandle).equals((x: 0.0, y: 3.0));
    check(first.weights).deepEquals([1.0, 1.0]);
    check(patch.nodes[0].color).isEmpty();
    check(patch.nodes[0].opacity).isNull();
    check(patch.nodes[0].secondHandle).equals((x: 0.0, y: 6.0));
    check(patch.nodes[2].colorSpace!.componentCount).equals(3);
    check(patch.nodes[4].colorSpace!.deviceName).isNull();
    check(patch.nodes[4].colorSpace!.field!.values.map((token) => token.lexeme).join(' ')).equals('[ [ 0 0 0 1 /DeviceCMYK (Black) /Separation ] 1 /NChannel ]');
    check(patch.nodes[5].color).deepEquals([0.0, 0.5, 1.0, 0.0]);
    check(latin1.decode(decoded.records.program.bytes.sublist(mesh.start, mesh.end))).equals(_mesh);
    check(patch.fields.any((field) => field.key == 'Future')).isTrue();
    check(mesh.patches.clear).throws<UnsupportedError>();
    check(patch.nodes.clear).throws<UnsupportedError>();
    check(first.color.clear).throws<UnsupportedError>();
    check(first.field.values.clear).throws<UnsupportedError>();
  });

  test('does not treat procedures, literal objects, strings or embedded art as meshes', () {
    const String body =
        '''{ $_mesh } pop
[$_mesh] pop
<< /Ignored [$_mesh] >> pop
(/Mesh X! /End X!) pop
%%BeginDocument: child.ai
$_mesh
%%EndDocument
$_mesh''';
    final AiNativeMeshes result = _decode(body);
    check(result.meshes.length).equals(1);
    check(_decode('/Other $_mesh').meshes).isEmpty();
    check(_decode('[$_mesh] pop').meshes).isEmpty();
  });

  test('handles private packets, CRLF, resources and inherited color space', () {
    final String private = _mesh.replaceFirst('/Mesh X!', '%_/Mesh X!').replaceFirst('/End X!', '%_/End X!').replaceAll('\n', '\r\n');
    check(_decode(private).meshes.single.isPrivate).isTrue();
    check(_decode(_mesh, setup: _mesh, trailer: _mesh).meshes.length).equals(3);
    check(_decode(_mesh, setup: _mesh, trailer: _mesh, bodyOnly: true).meshes.length).equals(1);
    final String second = _mesh.substring(_mesh.indexOf('%_[0 0] /P')).replaceFirst('[0 0] /P', '[1 0] /P').replaceFirst('%_[-1] /R', '%_/DeviceGray /CS X#\n%_[-1] /R');
    final String pair = _mesh.replaceFirst('[1 1] /Size', '[2 1] /Size').replaceFirst('/End X!', second);
    check(_decode(pair).meshes.single.patches.length).equals(2);
    final String changed = _mesh.replaceFirst('%_/Data X#', '%_/DeviceGray /CS X#\n%_/Data X#');
    check(_decode(changed).meshes.single.patches.single.nodes[1].colorSpace!.field!.key).equals('CS');
  });

  test('rejects truncated, duplicate, inconsistent or unbounded mesh declarations', () {
    final List<String> invalid = [
      _mesh.replaceFirst('/End X!', ''),
      _mesh.replaceFirst('%_/E X#', ''),
      _mesh.replaceFirst('%_[1 1] /Size X#', ''),
      _mesh.replaceFirst('%_/Data X#', '%_3 /Version X#\n%_/Data X#'),
      _mesh.replaceFirst('[1 1] /Size', '[1 2] /Size'),
      _mesh.replaceFirst('[1 1] /Size', '[9007199254740991 9007199254740991] /Size'),
      _mesh.replaceFirst('[1 1] /Size', '[0 1] /Size'),
      _mesh.replaceFirst('[0 0] /P', '[1 0] /P'),
      _mesh.replaceFirst('[0 0] /P', '[0.5 0] /P'),
      _mesh.replaceFirst('%_[0 0] /P X#', '%_[0 0] /P X#\n%_[0 0] /P X#'),
      _mesh.replaceFirst('%_[0 0] /P X#', ''),
      _mesh.replaceFirst('%_/Data X#', '%_[0 0] /P X#\n%_/Data X#'),
      _mesh.replaceFirst('%_/E X#', '%_1 /E X#'),
      _mesh.replaceFirst('/End X!', '%_/End X!'),
      _mesh.replaceFirst('%_[0 0] /P X#', '%%BeginDocument: nested.ai\n%_[0 0] /P X#'),
      _mesh.replaceFirst('%_/E X#', '%_/Mesh X!'),
    ];
    for (final String body in invalid) {
      check(() => _decode(body)).throws<FormatException>();
    }
    check(() => _decode(_mesh, limits: const AiNativeLimits(maxTokens: 12))).throws<FormatException>();
  });

  test('rejects unsupported schemas and malformed node arrays without losing source', () {
    check(() => _decode(_mesh.replaceFirst('2 /Version', '1 /Version'))).throws<UnsupportedError>();
    check(() => _decode(_mesh.replaceFirst('/Cartesian /Type', '/Future /Type'))).throws<UnsupportedError>();
    final List<String> invalid = [
      _mesh.replaceFirst('0.25 0.5', '0.25 1.5'),
      _mesh.replaceFirst('0.25 0.5', '1.25 0.5'),
      _mesh.replaceFirst('0.25 0.5', '0.25'),
      _mesh.replaceFirst('0.25 0.5', '0.25 0.5 0.5'),
      _mesh.replaceFirst('0 5 0 4 0 6 1', '0 5 0 4 0 6'),
      _mesh.replaceFirst('0.25 0.5', 'NaN 0.5'),
      _mesh.replaceFirst('/DeviceRGB /CS', '/DeviceCMYK /CS'),
      _mesh.replaceFirst('/DeviceRGB /CS', '/CS'),
      _mesh.replaceFirst(' /N X#', ' /Future X#'),
    ];
    for (final String body in invalid) {
      check(() => _decode(body)).throws<FormatException>();
    }
  });
}
