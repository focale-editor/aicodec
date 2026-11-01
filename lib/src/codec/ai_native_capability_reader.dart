part of '../model/ai_native_capabilities.dart';

/// Collects source-local findings without invoking edits or rendering code.
final class _NativeCapabilityReader {
  /// Original program and all its shared container owners.
  final AiNativeSource source;

  /// Bounded syntax and hierarchy policy.
  final AiNativeLimits limits;

  /// Maximum retained findings, including an overflow diagnostic.
  final int maxFindings;

  /// Findings accumulated before publishing an immutable snapshot.
  final List<AiNativeCapability> findings = [];

  /// Whether an inspection failed or ran out of its explicit budget.
  bool complete = true;

  /// Whether output truncation has already been reported.
  bool truncated = false;

  /// Creates a private bounded inspection context.
  _NativeCapabilityReader({required this.source, required this.limits, required this.maxFindings});

  /// Adds one finding, reserving the last output slot for explicit truncation.
  void add(AiNativeFeature feature, int start, int end, AiNativeDataSupport support, String message, {String? selector, List<AiNativeEditCapability> edits = const []}) {
    if (truncated) {
      return;
    }
    if (findings.length == maxFindings) {
      findings.removeLast();
      complete = false;
      truncated = true;
      findings.add(
        AiNativeCapability._(
          source: source,
          feature: .program,
          selector: 'inspection-limit',
          start: 0,
          end: source.bytes.length,
          support: .uninspected,
          message: 'Capability findings exceed maxFindings.',
        ),
      );
      return;
    }
    findings.add(AiNativeCapability._(source: source, feature: feature, selector: selector ?? '${feature.name}:$start', start: start, end: end, support: support, message: message, edits: edits));
  }

  /// Contains expected data failures while keeping budget and syntax distinct.
  String? inspect(AiNativeFeature feature, int start, int end, void Function() action) {
    if (truncated) {
      return 'Inspection stopped at maxFindings.';
    }
    final AiNativeDataSupport support;
    final String message;
    try {
      action();
      return null;
    } on AiLimitException catch (error) {
      support = .uninspected;
      message = error.message;
    } on PsFormatException catch (error) {
      support = .uninspected;
      message = 'Text engine inspection failed: ${error.message}';
    } on AiNativeAmbiguousFieldError catch (error) {
      complete = false;
      add(feature, error.start, error.end, .unsupported, error.message);
      return error.message;
    } on UnsupportedError catch (error) {
      support = .unsupported;
      message = error.message ?? 'Unsupported native structure.';
    } on FormatException catch (error) {
      support = .malformed;
      message = error.message;
    }
    complete = false;
    add(feature, start, end, support, message);
    return message;
  }

  /// Reports that an existing API still has to qualify a proposed native edit.
  List<AiNativeEditCapability> conditional(List<AiNativeEditOperation> operations, {String? issue}) => [
    for (final AiNativeEditOperation operation in operations)
      AiNativeEditCapability._(
        operation: operation,
        support: issue == null ? .requiresValidation : .unsupported,
        reason: issue ?? 'The native editor must validate selected dependencies and supplied values.',
      ),
  ];

  /// Reads each native model independently, preserving diagnostics from siblings.
  AiNativeCapabilityReport read() {
    inspect(.program, 0, source.bytes.length, () {
      final AiProgram program = AiProgram.decode(bytes: source.bytes, limits: limits);
      add(.program, 0, source.bytes.length, .preserved, 'Original program retained; findings do not imply complete semantic coverage.');
      for (final AiLayer layer in program.layers) {
        add(
          .layer,
          layer.begin.start,
          layer.naming?.end ?? layer.begin.end,
          .typed,
          'Layer header only; child objects have independent capabilities.',
          edits: [
            for (final AiNativeEditOperation operation in [AiNativeEditOperation.layerName, AiNativeEditOperation.layerFlags])
              AiNativeEditCapability._(operation: operation, support: .available, reason: 'Source-backed header edit; supplied names and flags remain validated.'),
            ...conditional([
              AiNativeEditOperation.layerInsertion,
              AiNativeEditOperation.layerReordering,
              AiNativeEditOperation.layerReparenting,
              AiNativeEditOperation.layerDuplication,
              AiNativeEditOperation.layerRemoval,
            ]),
          ],
        );
      }
      final bool counted = program.instructions.any((instruction) => instruction.operator == 'As');
      for (final AiPath path in program.paths) {
        final bool qualified = !path.hasDependentAppearance && !program.hasPrivateExtensions && !program.hasUnhandledBodyOperators;
        add(
          .path,
          path.geometry.first.start,
          path.paint.end,
          .typed,
          'Explicit path geometry; private or printing ownership is not inferred.',
          edits: [
            AiNativeEditCapability._(
              operation: .pathGeometry,
              support: !qualified ? .unsupported : (counted ? .requiresValidation : .available),
              reason: !qualified
                  ? 'Dependent appearance, private extensions or unhandled body operators prevent plain-path editing.'
                  : (counted ? 'Native point-count ownership and closed endpoints require validation.' : 'Plain source geometry is isolated under the current editor contract.'),
            ),
            for (final AiNativeEditOperation operation in [
              AiNativeEditOperation.pathTopology,
              AiNativeEditOperation.pathInsertion,
              AiNativeEditOperation.pathDuplication,
              AiNativeEditOperation.pathRemoval,
              AiNativeEditOperation.pathReordering,
              AiNativeEditOperation.pathReparenting,
              AiNativeEditOperation.groupCreation,
              AiNativeEditOperation.compoundCreation,
              AiNativeEditOperation.clippingCreation,
            ])
              AiNativeEditCapability._(
                operation: operation,
                support: .requiresValidation,
                reason: 'Path lifecycle edits require independent native ownership, resolved surrounding metadata and source point-count validation.',
              ),
          ],
        );
      }
      for (final AiInstruction instruction in program.instructions) {
        if (program.unhandledOperators.contains(instruction.operator)) {
          add(
            .instruction,
            instruction.start,
            instruction.end,
            .preserved,
            'Operator ${instruction.operator} has no plain-path structural interpretation; a feature-specific finding may describe it.',
          );
        }
      }
      inspect(.record, 0, source.bytes.length, () => records(AiNativeRecords.decode(program: program)));
    });
    return AiNativeCapabilityReport._(source: source, findings: findings, complete: complete);
  }

  /// Inspects typed families while retaining opaque hierarchical records.
  void records(AiNativeRecords records) {
    for (final AiNativeContainer record in records.containers) {
      add(.record, record.start, record.end, .preserved, 'Native ${record.type} record retained; structural decoding does not qualify its complete semantics.');
      if (record.type == 'AI11TextDocument') {
        inspect(.text, record.start, record.end, () {
          final AiNativeTextDocument text = AiNativeTextDocument.decode(records: records, container: record);
          add(
            .text,
            record.start,
            record.end,
            .typed,
            '${text.stories.length} stories, ${text.frames.length} frames and ${text.fonts.length} fonts.',
            edits: conditional([.textContent, .textFeatures, .textLayout]),
          );
          for (final String issue in text.referenceIssues) {
            add(.text, record.start, record.end, .unsupported, issue, selector: 'text-reference:${record.start}:${findings.length}');
          }
        });
      }
    }
    inspect(.artboard, 0, source.bytes.length, () {
      for (final AiNativeArtboard artboard in records.artboards) {
        add(.artboard, artboard.record.start, artboard.record.end, .typed, 'Native artboard; no PDF page mapping is inferred.');
      }
    });
    inspect(.group, records.program.bodyStart, records.program.bodyEnd, () => drawing(AiNativeDrawing.decode(records: records)));
    inspect(.gradientResource, 0, source.bytes.length, () {
      for (final AiNativeGradientDefinition definition in AiNativeGradientResources.decode(records: records).definitions) {
        add(.gradientResource, definition.start, definition.end, .typed, 'Native gradient stops and printing intervals.', edits: conditional([.gradientStops, if (definition.radial) .gradientFocus]));
      }
    });
    inspect(.mesh, 0, source.bytes.length, () {
      for (final AiNativeMesh mesh in AiNativeMeshes.decode(records: records).meshes) {
        add(.mesh, mesh.start, mesh.end, .typed, 'Native mesh fields; geometry is not interpolated.', edits: conditional([.meshPaint]));
      }
    });
    inspect(.raster, 0, source.bytes.length, () {
      for (final AiNativeRaster raster in AiNativeRasters.decode(records: records).images) {
        final String? issue = inspect(.raster, raster.start, raster.end, raster.validateProcessLayout);
        add(.raster, raster.start, raster.end, .typed, 'Native image geometry and sample planes.', edits: conditional([.rasterPixels, .imagePlacement], issue: issue));
      }
    });
    inspect(.placement, 0, source.bytes.length, () {
      for (final AiNativePlacedObject object in AiNativePlacements.decode(records: records).objects) {
        final String? issue = inspect(.placement, object.start, object.end, object.validateRasterLayout);
        add(
          .placement,
          object.start,
          object.end,
          .typed,
          'Native link geometry and retained preview; no file resolution is performed.',
          edits: conditional([.relink, .embed, .imagePlacement], issue: issue),
        );
      }
    });
  }

  /// Reports topology and association issues without making parent-wide claims.
  void drawing(AiNativeDrawing drawing) {
    inspect(.record, drawing.records.program.bodyStart, drawing.records.program.bodyEnd, () {
      for (final AiNativeObject object in AiNativeObjects.decode(drawing: drawing).objects) {
        if (object.dictionary != null || object.expansion != null || object.styleApplication != null) {
          add(
            .record,
            object.start,
            object.end,
            object.bindingIssue == null ? .typed : .preserved,
            object.bindingIssue ?? 'Direct object metadata, panel flags and group-style association; geometry, appearance and lifecycle require independent validation.',
            selector: 'object-metadata:${object.start}',
          );
        }
      }
    });
    for (final AiNativeGroup group in drawing.groups) {
      add(
        .group,
        group.start,
        group.end,
        .typed,
        group.compound ? 'Native compound topology; children retain independent ownership.' : 'Native group topology; children retain independent ownership.',
        edits: [
          ...conditional(
            [.groupDissolution, .groupDuplication, .groupRemoval, .groupReordering, .groupReparenting],
            issue: group.opening.operator != 'u' || group.opening.isPrivate ? 'Group lifecycle requires non-private ordinary topology.' : null,
          ),
          ...conditional([if (group.compound) .compoundDissolution else .compoundCreation], issue: group.opening.isPrivate ? 'Compound lifecycle requires ordinary native ownership.' : null),
          ...conditional([
            if (group.opening.operator == 'q') .clippingDissolution else .clippingCreation,
          ], issue: group.opening.isPrivate ? 'Clipping lifecycle requires ordinary native ownership.' : null),
        ],
      );
    }
    for (final AiLiveShape shape in drawing.liveShapes) {
      add(
        .liveShape,
        shape.start,
        shape.end,
        .typed,
        'Native ${shape.handler} parameters and source associations.',
        edits: [
          ...conditional([.liveShapeTranslation, .liveShapeRotation, .liveShapeScaling], issue: shape.bindingIssue),
          ...conditional([
            .liveShapeDuplication,
            .liveShapeRemoval,
            .liveShapeReordering,
            .liveShapeReparenting,
            .printingContours,
            .printingGroups,
          ], issue: shape.bindingIssue ?? (shape.appearanceGroup == null || shape.path?.isPrivate != true ? 'No separate native printing expansion is bound.' : null)),
        ],
      );
      if (shape.bindingIssue case final String issue) {
        add(.liveShape, shape.start, shape.end, .unsupported, issue, selector: 'binding:${shape.start}');
      }
    }
    for (final AiNativeGradient gradient in drawing.gradients) {
      add(.gradient, gradient.start, gradient.end, .typed, 'Native gradient instance and its printing geometry.');
    }
  }
}
