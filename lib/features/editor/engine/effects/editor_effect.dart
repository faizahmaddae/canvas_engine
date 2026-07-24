/// Effect stack scaffolding for Phase 2.
///
/// This file ships the *empty* shape of the effect system: the sealed
/// [EditorEffect] base, an immutable [EffectStack] container, and the
/// JSON registry. Concrete effects (brightness, contrast, saturation,
/// curves, blur, …) are introduced in subsequent steps as `part of`
/// this library so the `sealed` switch stays exhaustive across files.
///
/// ## Why a stack on the layer (not on the document)
///
/// Effects are non-destructive *modifiers of a single layer*. A blur
/// on layer A and a curve on layer B are independent — there is no
/// document-level effect graph. Putting the stack on the layer also
/// means group / duplicate / clipboard / undo all carry effects for
/// free: every `EditorLayer.copyAll` already threads every field.
///
/// ## Order
///
/// `effects[0]` applies first, `effects[last]` applies last (top of
/// stack). For pixel layers this matches Photoshop's adjustment-stack
/// convention. The renderer is responsible for honouring the order;
/// the model just stores it.
///
/// ## Wire format
///
/// An *empty* stack omits the `effects` key entirely. This is what
/// keeps the v2 fixture corpus byte-identical after the v3 schema
/// bump — every legacy layer rehydrates with `EffectStack.empty`,
/// re-encodes with no `effects` key, and the bytes match.
library;

import 'dart:math' as math;
import 'dart:ui' as ui show Gradient, Offset;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../core/layer_mask.dart';
import 'color_matrix_ops.dart';

part 'color_adjustment_effects.dart';
part 'vignette_effect.dart';

/// One non-destructive modifier on a single layer. Concrete effects
/// extend this in part files; the sealed base keeps the switch
/// exhaustive when the renderer dispatches by runtime type.
///
/// Every effect carries:
///   * an [enabled] toggle (eyeball icon in the UI),
///   * an optional [mask] that scopes where the effect applies
///     (composed via [LayerMask.composedAlpha] with any layer-wide
///     mask the renderer also honours),
///   * a stable [type] string used as the JSON discriminator.
///
/// Concrete effects must be `final` (or `sealed` themselves) and live
/// in this library via `part of editor_effect`.
///
/// ## Render dispatch — two flavours, one stack
///
/// Effects come in two render flavours. Both live on the same
/// [EffectStack] in user-visible order, but the renderer handles
/// them on **separate, non-entangled paths**:
///
/// 1. **Colour-matrix effects** ([EffectKind.colorMatrix]). Their
///    contribution is a single 4×5 matrix. The whole stack of them
///    composes into one matrix via [EffectStack.composedColorMatrix]
///    and the renderer pays one [ColorFiltered] cost no matter how
///    many are stacked. Brightness/contrast/saturation/exposure/
///    warmth all live here.
///
/// 2. **Custom-paint effects** ([EffectKind.customPaint]). Each
///    effect provides its own [paint] method that draws on top of
///    the already-colour-adjusted, masked, cropped pixels. Vignette,
///    grain, and any future spatial / non-chromatic effect lives
///    here. Custom-paint effects iterate via
///    [EffectStack.customPaintEffects] and are painted in stack
///    order; a stack with no contributing custom-paint effects pays
///    *zero* extra widget cost (the renderer omits the overlay
///    entirely so byte-identity holds against pre-effect documents).
///
/// The two paths are deliberately not collapsed into a single
/// dispatch — colour-matrix composition is O(stack) of cheap matrix
/// multiplies on the CPU, custom-paint is O(visible-effects) of
/// `Canvas` calls in a `CustomPainter`. Mixing them would force the
/// matrix path to give up its single-pass optimisation.
@immutable
sealed class EditorEffect {
  const EditorEffect({this.enabled = true, this.mask});

  final bool enabled;
  final LayerMask? mask;

  /// JSON discriminator. Must be unique across all effect concretes.
  String get type;

  /// Which renderer path this effect uses. Concretes must override —
  /// see [EffectKind] for the contract.
  EffectKind get kind;

  /// True when this effect would actually change pixels at its
  /// current parameters. The renderer uses this to skip both the
  /// colour-matrix composition gate AND the custom-paint overlay
  /// when the stack is full of identity-valued effects, preserving
  /// byte-identity with a stack containing none of them.
  ///
  /// Default `true`. Concretes with a meaningful identity (e.g.
  /// vignette intensity 0, brightness amount 0) override.
  bool get contributes => true;

  /// Paint contract for [EffectKind.customPaint] effects. Receives
  /// a `Canvas` already translated to layer-local space and the
  /// layer's local `bounds` rect (origin `Offset.zero`, size of the
  /// layer's visible silhouette). The renderer takes care of
  /// clipping to the layer's mask before calling — implementations
  /// can paint freely against `bounds` without re-clipping.
  ///
  /// Default no-op so [EffectKind.colorMatrix] concretes don't need
  /// to override this.
  void paint(Canvas canvas, Rect bounds) {}

  /// Functional copy with [enabled] toggled. Concrete effects must
  /// override; the effect-list panel uses this to flip an effect's
  /// eyeball without knowing its concrete subtype.
  EditorEffect withEnabled(bool value);

  /// Serialize to a JSON-friendly map. Concrete effects spread
  /// [baseJson] then add their own keys; default values must be
  /// omitted so legacy documents stay byte-identical.
  Map<String, dynamic> toJson();

  /// Common base JSON shared by every concrete: type discriminator,
  /// enabled flag (omitted when the default `true`), and mask.
  @protected
  Map<String, dynamic> baseJson() => <String, dynamic>{
    'type': type,
    if (!enabled) 'enabled': false,
    if (mask != null) 'mask': mask!.toJson(),
  };

  /// Decoder for a single effect. Looks up the concrete factory in
  /// [_effectFactories] by the `type` discriminator. Throws on an
  /// unknown type — silently dropping unknown effects would silently
  /// corrupt a document edited by a newer version of the app.
  static EditorEffect fromJson(Map<String, dynamic> json) {
    // Touch every part-file registration sentinel so lazy top-level
    // finals in part files are forced to initialise before the
    // registry is read. Without this, a Dart program that only ever
    // touches `EditorEffect.fromJson` (and never the concrete
    // classes directly) would observe an empty registry.
    _kColorAdjustmentEffectsRegistered;
    _kVignetteEffectRegistered;
    final type = json['type'] as String?;
    if (type == null) {
      throw FormatException('Effect missing required `type` key: $json');
    }
    final factory = _effectFactories[type];
    if (factory == null) {
      // Forward-compat: a document written by a newer build may
      // contain effect types this binary doesn't understand. Rather
      // than fail-load (which would lock the user out of every
      // project edited on a newer device) we preserve the unknown
      // entry as an opaque carrier. The renderer ignores it
      // (contributes = false, no paint, no matrix contribution),
      // but [toJson] returns the original map verbatim so resaving
      // does not silently drop the data the newer build wrote.
      return UnknownEffect._(Map<String, dynamic>.unmodifiable(json));
    }
    return factory(json);
  }
}

/// Forward-compat carrier for an effect whose `type` discriminator
/// isn't in the local [_effectFactories] registry. Created by
/// [EditorEffect.fromJson] when an older binary opens a document
/// written by a newer build. Renders as a no-op; round-trips its
/// original JSON byte-for-byte on resave so the newer build's data
/// is preserved if the document is ever opened on that build again.
final class UnknownEffect extends EditorEffect {
  const UnknownEffect._(this._raw) : super(enabled: false, mask: null);

  final Map<String, dynamic> _raw;

  @override
  String get type => (_raw['type'] as String?) ?? 'unknown';

  @override
  EffectKind get kind => EffectKind.colorMatrix;

  /// Always `false`: the renderer must not allocate a matrix or
  /// overlay for a type it cannot interpret.
  @override
  bool get contributes => false;

  @override
  EditorEffect withEnabled(bool value) => this;

  @override
  Map<String, dynamic> toJson() => Map<String, dynamic>.from(_raw);
}

/// Which rendering pipeline an [EditorEffect] feeds into. Stored
/// on the effect (not the renderer) so a concrete declares its own
/// flavour and the dispatch never needs a `runtimeType` switch.
///
/// See the doc comment on [EditorEffect] for the architectural
/// rationale — TL;DR: keeping the two paths separate lets the
/// colour-matrix path stay a single-pass `ColorFiltered` no matter
/// how many adjustments stack up.
enum EffectKind {
  /// Composes into the layer's single 4×5 colour matrix via
  /// [EffectStack.composedColorMatrix]. `paint` is a no-op for
  /// these effects.
  colorMatrix,

  /// Implements its own [EditorEffect.paint] callback, drawn over
  /// the colour-adjusted pixels in stack order.
  customPaint,
}

/// Registry of concrete effect decoders, populated by `part` files
/// via [registerEffect].
final Map<String, EditorEffect Function(Map<String, dynamic>)>
_effectFactories = <String, EditorEffect Function(Map<String, dynamic>)>{};

/// Internal hook so part-file effects can register their decoder
/// without needing to mutate this file. Call from a top-level `final
/// _registered = (() { registerEffect(...); return true; })();` in
/// each effect part.
@visibleForTesting
void registerEffect(
  String type,
  EditorEffect Function(Map<String, dynamic>) factory,
) {
  _effectFactories[type] = factory;
}

/// Per-instance memo cache for [EffectStack.composedColorMatrix].
/// Identity-keyed so it never holds a strong reference to a stack
/// after the document moves on; entries die with the stack.
final Expando<List<double>> _composedColorMatrixCache = Expando<List<double>>(
  'EffectStack.composedColorMatrix',
);

/// Sentinel placed in the cache when the stack composes to a `null`
/// matrix. Without it, "no contributing effects" stacks would miss
/// the cache on every call — they're the common case (effect added
/// then zeroed out by the user) and recomputing the loop every
/// frame is exactly the cost the cache exists to avoid.
final List<double> _kNullMatrixSentinel = List<double>.unmodifiable(<double>[]);

/// Immutable, ordered list of effects on a layer, plus an optional
/// [stackMask] that clips the composed output of the whole stack.
/// Empty by default — an empty stack costs nothing in JSON (the
/// layer omits the `effects` key entirely).
@immutable
final class EffectStack {
  /// Construct an effect stack. The constructor stores [effects] as
  /// given — production callers must pass an unmodifiable list
  /// (commands wrap with `List.unmodifiable`; const list literals
  /// are already immutable). The const form keeps test fixtures and
  /// the [empty] singleton cheap.
  const EffectStack(this.effects, {this.stackMask});

  /// The shared empty instance. Constructors default to this so
  /// callers never have to pass it explicitly and `identical(stack,
  /// EffectStack.empty)` is a fast emptiness check.
  static const EffectStack empty = EffectStack(<EditorEffect>[]);

  final List<EditorEffect> effects;

  /// Clips the composed output of the whole stack (docs/effects.md
  /// §5: `composite(I_prev over I0 through stackMask)`). `null` means
  /// no clip. Composes with per-effect masks via `min(α)` at sample
  /// time — see [LayerMask.composedAlpha].
  final LayerMask? stackMask;

  /// Emptiness of the *effects list only*. Deliberately does NOT
  /// consider [stackMask]: this getter gates the `effects` JSON key
  /// (a stackMask-only stack must still omit `effects`, or every
  /// legacy document's bytes change) and the renderer's "any effects
  /// to compose?" checks, both of which care about the list alone.
  bool get isEmpty => effects.isEmpty;
  bool get isNotEmpty => effects.isNotEmpty;
  int get length => effects.length;

  /// Encodes to a list of effect JSON maps. Callers (typically
  /// [EditorLayer.baseJson]) should *omit* the `effects` key
  /// entirely when [isEmpty] — encoding `[]` would change the bytes
  /// of every legacy document on disk.
  List<Map<String, dynamic>> toJson() =>
      effects.map((e) => e.toJson()).toList(growable: false);

  /// Decode a stack from the raw JSON value found under the
  /// `effects` key. Returns [empty] when the value is `null` or an
  /// empty list. Accepts only `List<dynamic>` shapes — anything else
  /// throws so a malformed document fails loud rather than silently
  /// dropping data.
  static EffectStack fromJson(Object? raw) {
    if (raw == null) return empty;
    if (raw is! List) {
      throw FormatException(
        'EffectStack expected a JSON list, got ${raw.runtimeType}: $raw',
      );
    }
    if (raw.isEmpty) return empty;
    final list = <EditorEffect>[];
    for (final entry in raw) {
      if (entry is! Map<String, dynamic>) {
        throw FormatException(
          'Effect entries must be JSON objects, got ${entry.runtimeType}',
        );
      }
      list.add(EditorEffect.fromJson(entry));
    }
    return EffectStack(List<EditorEffect>.unmodifiable(list));
  }

  /// Compose every enabled, unmasked colour-adjustment effect into a
  /// single 4×5 colour matrix, in stack order (`effects[0]` first,
  /// `effects[last]` last). Returns `null` when the stack contains
  /// no contributing effects — the renderer can then skip the
  /// `ColorFiltered` wrapper entirely.
  ///
  /// Disabled effects and effects with a non-null [LayerMask] are
  /// skipped here: the matrix form can't represent a per-pixel mask,
  /// and the renderer will need a separate code path (Step 6+) to
  /// honour them. For Step 5 the dual-write only ever produces
  /// unmasked entries, so this gate has no observable effect today.
  ///
  /// **Memoised by stack identity.** [EffectStack] is immutable, so
  /// the composition is a pure function of `this`. We cache the
  /// result in a process-wide [Expando] keyed by stack identity —
  /// the cache entry dies with the stack instance (no manual
  /// eviction, no leaks). Two stacks with equal `effects` lists but
  /// different identities each compute the matrix once; that's
  /// acceptable because in practice the document controller hands
  /// the same stack instance to every render frame between edits.
  /// Without this cache a five-effect stack on an image layer pays
  /// 5 matrix-multiplies × every paint() during a slider drag.
  List<double>? get composedColorMatrix {
    final cached = _composedColorMatrixCache[this];
    if (cached != null) {
      // Sentinel preserves the "no contributing effects" answer
      // (genuine null) through the cache — without it we'd
      // recompute every time the stack composes to null.
      return identical(cached, _kNullMatrixSentinel) ? null : cached;
    }
    final computed = _composeColorMatrix();
    _composedColorMatrixCache[this] = computed ?? _kNullMatrixSentinel;
    return computed;
  }

  List<double>? _composeColorMatrix() {
    List<double>? acc;
    for (final eff in effects) {
      if (!eff.enabled || eff.mask != null) continue;
      final m = _matrixOf(eff);
      if (m == null) continue;
      acc = acc == null ? m : composeColorMatrices(m, acc);
    }
    return acc;
  }

  /// The 4×5 matrix a single colour-adjustment effect contributes,
  /// or null for identity values and non-matrix kinds. Shared by the
  /// legacy single-matrix composition above and the Step 6 segmented
  /// renderer below so the two paths can never disagree about an
  /// effect's math.
  static List<double>? _matrixOf(EditorEffect eff) => switch (eff) {
    BrightnessEffect(:final amount) when amount != 0 => _brightnessMatrix(
      amount,
    ),
    ContrastEffect(:final amount)
        when amount != ContrastEffect.identityAmount =>
      _contrastMatrix(amount),
    SaturationEffect(:final amount)
        when amount != SaturationEffect.identityAmount =>
      _saturationMatrix(amount),
    ExposureEffect(:final amount) when amount != 0 => _exposureMatrix(amount),
    WarmthEffect(:final amount) when amount != 0 => _warmthMatrix(amount),
    _ => null,
  };

  /// True when any enabled, contributing effect carries a per-effect
  /// mask — the signal that the renderer must take the segmented
  /// Step 6 path ([renderSegments]) instead of the single composed
  /// matrix. False for every pre-Step-6 document, which keeps the
  /// fast path (and its widget tree) untouched.
  bool get hasEnabledMaskedEffect =>
      effects.any((e) => e.enabled && e.mask != null && e.contributes);

  /// Custom-paint effects with a per-effect mask, in stack order.
  /// Rendered as individually mask-clipped overlays (the overlay
  /// draws on top, so masking the overlay alone implements §5's
  /// composite for this kind).
  Iterable<EditorEffect> get maskedCustomPaintEffects => effects.where(
    (e) =>
        e.enabled &&
        e.mask != null &&
        e.kind == EffectKind.customPaint &&
        e.contributes,
  );

  /// Step 6/3.3 render plan: every enabled, contributing effect
  /// folded into segments, in stack order (docs/effects-step6-per-
  /// effect-masks-2026-07.md §3 + the reorder-honesty extension).
  ///
  ///   * Maximal runs of *unmasked* colour-matrix effects compose
  ///     into one [MatrixSegment] — exact, because matrix
  ///     composition is associative within a run.
  ///   * Each masked matrix effect is its own [MaskedEffectSegment]
  ///     boundary, because composing across a per-pixel blend is not.
  ///   * Maximal runs of *unmasked* custom-paint effects become one
  ///     [CustomPaintSegment] (one overlay painter for the run);
  ///     masked ones become [MaskedCustomPaintSegment] boundaries.
  ///
  /// Including custom paint in the fold is what makes reordering a
  /// vignette against matrix effects a *real* render change — a
  /// matrix effect above the vignette now recolours the vignette's
  /// pixels too, exactly as the stack order promises.
  List<EffectRenderSegment> get renderSegments {
    final out = <EffectRenderSegment>[];
    List<double>? matrixAcc;
    List<EditorEffect>? paintAcc;
    void flushMatrix() {
      final m = matrixAcc;
      if (m != null) {
        out.add(MatrixSegment(m));
        matrixAcc = null;
      }
    }

    void flushPaint() {
      final p = paintAcc;
      if (p != null) {
        out.add(CustomPaintSegment(List<EditorEffect>.unmodifiable(p)));
        paintAcc = null;
      }
    }

    for (final eff in effects) {
      if (!eff.enabled || !eff.contributes) continue;
      switch (eff.kind) {
        case EffectKind.colorMatrix:
          final m = _matrixOf(eff);
          if (m == null) continue; // identity — invisible either way
          if (eff.mask != null) {
            flushMatrix();
            flushPaint();
            out.add(MaskedEffectSegment(eff, m));
          } else {
            flushPaint();
            final prev = matrixAcc;
            matrixAcc = prev == null ? m : composeColorMatrices(m, prev);
          }
        case EffectKind.customPaint:
          if (eff.mask != null) {
            flushMatrix();
            flushPaint();
            out.add(MaskedCustomPaintSegment(eff));
          } else {
            flushMatrix();
            (paintAcc ??= <EditorEffect>[]).add(eff);
          }
      }
    }
    flushMatrix();
    flushPaint();
    return out;
  }

  /// True when the stack renders identically under the legacy
  /// "one matrix, then every custom-paint on top" fast path — i.e.
  /// no enabled masked effect, and no contributing custom-paint
  /// effect sitting *below* a contributing matrix effect. Every
  /// document our writers produce is canonical (the Adjust panel
  /// keeps derived matrices below and vignette appended last); only
  /// an explicit reorder in the Effects panel makes this false.
  bool get rendersOnFastPath {
    if (hasEnabledMaskedEffect) return false;
    var seenCustomPaint = false;
    for (final eff in effects) {
      if (!eff.enabled || !eff.contributes) continue;
      switch (eff.kind) {
        case EffectKind.customPaint:
          seenCustomPaint = true;
        case EffectKind.colorMatrix:
          if (seenCustomPaint && _matrixOf(eff) != null) return false;
      }
    }
    return true;
  }

  /// Custom-paint effects that actually contribute to the final
  /// image, in stack order. The renderer iterates this list to
  /// build its overlay pass; an empty result means **no overlay
  /// widget is created at all**, which is what preserves
  /// byte-identity against documents that have no custom-paint
  /// effects (vignette intensity 0, etc.).
  ///
  /// Disabled effects and effects with a per-effect mask are
  /// skipped — per-effect mask compositing on custom-paint is a
  /// future feature; for now the contract matches the colour-matrix
  /// path exactly (skip if `!enabled || mask != null`).
  Iterable<EditorEffect> get customPaintEffects => effects.where(
    (e) =>
        e.enabled &&
        e.mask == null &&
        e.kind == EffectKind.customPaint &&
        e.contributes,
  );

  /// True when at least one [EffectKind.customPaint] effect would
  /// draw at the current parameters. Cheap pre-check the renderer
  /// uses to decide whether to wrap the image in the overlay
  /// `Stack` at all.
  bool get hasContributingCustomPaint => customPaintEffects.isNotEmpty;

  /// Clone with a new effects list, preserving [stackMask] by
  /// construction. Every command that rebuilds an existing layer's
  /// effects list MUST go through this instead of `EffectStack(next)`
  /// — the bare constructor defaults `stackMask` to null and silently
  /// drops a set mask. Only [effects] is exposed: mask writes go
  /// through [withStackMask], so no sentinel machinery is needed
  /// here.
  ///
  /// A fully empty result (no effects, no mask) canonicalises to the
  /// [empty] singleton so `identical(stack, EffectStack.empty)` stays
  /// a valid fast emptiness check after command rebuilds.
  EffectStack copyWith({List<EditorEffect>? effects}) {
    final nextEffects = effects ?? this.effects;
    if (nextEffects.isEmpty && stackMask == null) return empty;
    return EffectStack(nextEffects, stackMask: stackMask);
  }

  /// Clone with the stack mask replaced (`null` clears). THE
  /// sanctioned mask-write path — `SetStackMaskCommand` and the
  /// mask-edit mode's live-overlay staging both go through here so
  /// canonicalisation cannot drift between them: a fully-empty
  /// result (no effects, no mask) collapses to the [empty] singleton,
  /// keeping `identical(stack, EffectStack.empty)` a valid fast
  /// emptiness check.
  EffectStack withStackMask(LayerMask? mask) {
    if (mask == stackMask) return this;
    if (effects.isEmpty && mask == null) return empty;
    return EffectStack(effects, stackMask: mask);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EffectStack &&
          listEquals(other.effects, effects) &&
          other.stackMask == stackMask);

  @override
  int get hashCode => Object.hash(Object.hashAll(effects), stackMask);
}

/// One step of the Step 6 segmented render plan ([EffectStack
/// .renderSegments]). Sealed so the renderer's fold is an exhaustive
/// switch — adding a segment kind is a compile error at every
/// consumer.
sealed class EffectRenderSegment {
  const EffectRenderSegment();
}

/// A maximal run of enabled, unmasked colour-matrix effects composed
/// into one 4×5 matrix — applied with a single `ColorFiltered`, same
/// cost as the pre-Step-6 renderer paid for the whole stack.
final class MatrixSegment extends EffectRenderSegment {
  const MatrixSegment(this.matrix);

  final List<double> matrix;
}

/// A single enabled colour-matrix effect carrying a per-effect mask.
/// The renderer composites `ColorFiltered(matrix)` over the running
/// state through `effect.mask`'s alpha (the A3 mechanism).
final class MaskedEffectSegment extends EffectRenderSegment {
  const MaskedEffectSegment(this.effect, this.matrix);

  final EditorEffect effect;
  final List<double> matrix;
}

/// A maximal run of enabled, unmasked custom-paint effects — one
/// overlay painter draws the whole run on top of the running state,
/// at the run's position in the stack so effects above it (matrix or
/// otherwise) apply to its pixels too.
final class CustomPaintSegment extends EffectRenderSegment {
  const CustomPaintSegment(this.effects);

  final List<EditorEffect> effects;
}

/// A single enabled custom-paint effect carrying a per-effect mask.
/// The overlay draws on top, so the renderer clips just the overlay
/// through the mask's alpha (nothing shows until the raster lands).
final class MaskedCustomPaintSegment extends EffectRenderSegment {
  const MaskedCustomPaintSegment(this.effect);

  final EditorEffect effect;
}
