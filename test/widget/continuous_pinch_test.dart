import 'package:canvas_engine/core/constants/engine_constants.dart';
import 'package:canvas_engine/features/editor/application/document_controller.dart';
import 'package:canvas_engine/features/editor/application/interaction_controller.dart';
import 'package:canvas_engine/features/editor/engine/commands/transform_commands.dart';
import 'package:canvas_engine/features/editor/engine/core/layer_transform.dart';
import 'package:canvas_engine/features/editor/engine/modules/shape/shape_layer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Continuous-pinch regression: the user must be able to keep
/// pinching smoothly while two fingers stay down. The interaction
/// engine clamps each per-frame gesture scale to the static window
/// `[EngineConstants.minGestureScale, EngineConstants.maxGestureScale]`
/// (currently 0.2 … 8.0). The clamp is applied **relative to the
/// session's reference transform** — it is a hard envelope on what
/// any single recogniser frame can do, deliberately preventing
/// runaway growth from a noisy / huge scale value. The session
/// itself does NOT silently rebase mid-gesture on cumulative-scale
/// thresholds; the only mid-gesture rebase happens on pointer-count
/// transitions (1 ↔ ≥2).
///
/// These tests pin that contract: per-frame clamp is honoured
/// exactly, the session asymptotes at the clamp boundary on long
/// continuous pinches, and direction reverses follow the cumulative
/// scale back inside the window.
///
/// Single-layer assertions read `liveTransform` directly: the
/// motion smoother is bypassed for multi-touch frames so pinch
/// behaves as direct manipulation (1:1 finger tracking).
/// Group tests read `groupLive` directly — the group path does
/// not smooth either.

ProviderContainer _makeContainer() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  c.read(documentControllerProvider.notifier).newDocument(
        width: 800,
        height: 800,
      );
  return c;
}

void _addRect(
  ProviderContainer c, {
  required String id,
  required Offset position,
  Size size = const Size(60, 60),
}) {
  c.read(documentControllerProvider.notifier).execute(
        AddLayerCommand(
          ShapeLayer(
            id: id,
            transform: LayerTransform(position: position, size: size),
            kind: ShapeKind.rectangle,
          ),
        ),
      );
}

void main() {
  group('continuous pinch \u2014 single layer', () {
    test(
      'long continuous pinch-out asymptotes at the per-frame '
      'maxGestureScale clamp',
      () {
        final c = _makeContainer();
        _addRect(c, id: 'r', position: const Offset(370, 370));
        final layer = c.read(documentControllerProvider).layerById('r')!;
        final ctl = c.read(interactionControllerProvider.notifier);

        ctl.startGesture(
          layer: layer,
          focalPoint: const Offset(400, 400),
        );

        // Walk cumulative scale from 1.0 \u2192 32.0 in small steps,
        // the way a real recogniser would emit during a continuous
        // pinch. The engine's per-frame clamp
        // (`EngineConstants.maxGestureScale`) limits how much any
        // single frame can grow the layer relative to the session's
        // reference transform, so the live size saturates at
        // `initialWidth * maxGestureScale` once the cumulative
        // scale crosses the cap and stays clamped for the rest of
        // the gesture (no automatic rebase).
        for (final s in <double>[
          1.1, 1.4, 1.8, 2.2, 2.8, 3.6, 4.5, 5.5, 6.8, 8.0,
          9.0, 10.5, 12.0, 14.0, 17.0, 20.0, 24.0, 28.0, 32.0,
        ]) {
          ctl.updateGesture(
            focalPoint: const Offset(400, 400),
            scale: s,
            rotation: 0,
            pointerCount: 2,
          );
        }

        // `liveTransform` is the raw engine output for multi-touch
        // (smoother bypassed for direct-manipulation pinch).
        final live = c
            .read(interactionControllerProvider)
            .liveTransform!;
        expect(
          live.size.width,
          closeTo(60 * EngineConstants.maxGestureScale, 0.01),
          reason: 'continuous pinch must saturate at exactly '
              '`initialWidth * maxGestureScale` \u2014 the engine clamps '
              'each per-frame scale and does not auto-rebase past '
              'the cap.',
        );
      },
    );

    test(
      'long continuous pinch-in asymptotes at the per-frame '
      'minGestureScale floor',
      () {
        final c = _makeContainer();
        _addRect(
          c,
          id: 'r',
          position: const Offset(200, 200),
          size: const Size(800, 800),
        );
        final layer = c.read(documentControllerProvider).layerById('r')!;
        final ctl = c.read(interactionControllerProvider.notifier);

        ctl.startGesture(
          layer: layer,
          focalPoint: const Offset(600, 600),
        );

        for (final s in <double>[
          0.9, 0.7, 0.5, 0.35, 0.25, 0.2,
          0.15, 0.10, 0.07, 0.04, 0.025,
        ]) {
          ctl.updateGesture(
            focalPoint: const Offset(600, 600),
            scale: s,
            rotation: 0,
            pointerCount: 2,
          );
        }

        final live = c
            .read(interactionControllerProvider)
            .liveTransform!;
        expect(
          live.size.width,
          closeTo(800 * EngineConstants.minGestureScale, 0.01),
          reason: 'continuous pinch-in must saturate at exactly '
              '`initialWidth * minGestureScale` \u2014 the engine clamps '
              'each per-frame scale to the lower bound and does '
              'not auto-rebase below the floor.',
        );
      },
    );

    test(
      'pinch-out then pinch-in within a single gesture follows the '
      'cumulative scale back inside the clamp window',
      () {
        final c = _makeContainer();
        _addRect(c, id: 'r', position: const Offset(370, 370));
        final layer = c.read(documentControllerProvider).layerById('r')!;
        final ctl = c.read(interactionControllerProvider.notifier);

        ctl.startGesture(
          layer: layer,
          focalPoint: const Offset(400, 400),
        );

        for (final s in <double>[1.5, 3, 6, 10, 16]) {
          ctl.updateGesture(
            focalPoint: const Offset(400, 400),
            scale: s,
            rotation: 0,
            pointerCount: 2,
          );
        }
        final big = c
            .read(interactionControllerProvider)
            .liveTransform!;
        // After scales \u2265 maxGestureScale the live size has hit the
        // upper clamp and stays there (no auto-rebase).
        expect(
          big.size.width,
          closeTo(60 * EngineConstants.maxGestureScale, 0.01),
          reason: 'pinch-out past the cap saturates at '
              '`initialWidth * maxGestureScale`',
        );

        for (final s in <double>[8, 4, 2, 1, 0.5]) {
          ctl.updateGesture(
            focalPoint: const Offset(400, 400),
            scale: s,
            rotation: 0,
            pointerCount: 2,
          );
        }

        final small = c
            .read(interactionControllerProvider)
            .liveTransform!;
        // Final cumulative scale 0.5 is well inside the clamp
        // window, so the engine produces an exact result against
        // the session reference (60 \u00d7 0.5 = 30).
        expect(
          small.size.width,
          closeTo(60 * 0.5, 0.01),
          reason: 'pinch-in within the same gesture must follow '
              'the cumulative scale back down once it re-enters '
              'the clamp window',
        );
      },
    );

    test(
      'stray pointerCount=1 frame mid-pinch rebases the session and '
      'a subsequent pointerCount=2 frame rebases it back \u2014 net '
      'effect on the cumulative pinch-out is a documented translate '
      'jump, not a frozen layer',
      () {
        // The single-layer session rebases on every pointer-count
        // transition (1 \u2194 \u22652) and processes pc<2 frames as a pure
        // translate. A stray glitch frame therefore does change the
        // live transform; it is NOT silently ignored. (The group
        // path uses different bookkeeping and DOES ignore stray
        // 1-pointer frames \u2014 see the group test below.) This
        // assertion pins the current behaviour so any future change
        // to either path stays intentional.
        final c = _makeContainer();
        _addRect(c, id: 'r', position: const Offset(370, 370));
        final layer = c.read(documentControllerProvider).layerById('r')!;
        final ctl = c.read(interactionControllerProvider.notifier);

        ctl.startGesture(
          layer: layer,
          focalPoint: const Offset(400, 400),
        );

        // Genuine 2-finger pinch grows the layer.
        for (final s in <double>[1.3, 1.8, 2.4]) {
          ctl.updateGesture(
            focalPoint: const Offset(400, 400),
            scale: s,
            rotation: 0,
            pointerCount: 2,
          );
        }
        final beforeGlitch = c
            .read(interactionControllerProvider)
            .liveTransform!;
        // 60 \u00d7 2.4 is inside the clamp window, so the live size
        // tracks the cumulative scale exactly.
        expect(
          beforeGlitch.size.width,
          closeTo(60 * 2.4, 0.01),
          reason: 'pinch must have grown the layer before the glitch',
        );

        // Glitch frame: pointer count drops to 1. The session
        // rebases (initialTransform = current live) then degrades to
        // translate using `focalPoint - pointerStart` against the
        // freshly rebased pointerStart. Because the rebase resets
        // pointerStart to the glitch focal, the in-frame translate
        // delta is zero \u2014 size stays put, position stays put.
        ctl.updateGesture(
          focalPoint: const Offset(600, 600),
          scale: 2.4,
          rotation: 0,
          pointerCount: 1,
        );
        final afterGlitch = c
            .read(interactionControllerProvider)
            .liveTransform!;
        expect(
          afterGlitch.size.width,
          closeTo(beforeGlitch.size.width, 0.01),
          reason: 'rebase-on-transition snapshots the size; the '
              'pc=1 frame itself only translates, never resizes',
        );

        // Continue pinching with 2 pointers \u2014 another rebase fires
        // (1 \u2192 2 transition), then the engine's per-frame clamp is
        // applied to the recogniser's cumulative `scale` (which has
        // since climbed past `maxGestureScale`). Live size therefore
        // ends saturated at the clamp boundary against the post-
        // rebase reference.
        for (final s in <double>[3.2, 4.5, 6.0, 8.0, 12.0, 16.0]) {
          ctl.updateGesture(
            focalPoint: const Offset(400, 400),
            scale: s,
            rotation: 0,
            pointerCount: 2,
          );
        }
        final afterResume = c
            .read(interactionControllerProvider)
            .liveTransform!;
        expect(
          afterResume.size.width,
          closeTo(
            afterGlitch.size.width * EngineConstants.maxGestureScale,
            0.01,
          ),
          reason: 'after the glitch + rebase, the per-frame clamp '
              'caps growth at `currentSize * maxGestureScale`; the '
              'session is alive throughout (no forced release)',
        );
      },
    );

    test(
      'multi-touch is direct-manipulation: liveTransform exactly '
      'tracks engine output (no smoother lag)',
      () {
        // Root cause of the "scales a little, then gets stuck" UX:
        // the motion smoother (calibrated for snap eases on
        // single-finger drag) was applied to multi-touch frames,
        // dragging the displayed size ~40% per frame behind the
        // user's finger separation. Bypassing the smoother for
        // multi-touch makes pinch direct: every frame, what the
        // user sees equals what the engine produced.
        final c = _makeContainer();
        _addRect(c, id: 'r', position: const Offset(370, 370));
        final layer = c.read(documentControllerProvider).layerById('r')!;
        final ctl = c.read(interactionControllerProvider.notifier);

        ctl.startGesture(
          layer: layer,
          focalPoint: const Offset(400, 400),
        );

        // Single multi-touch frame at 1.5x: live size must be
        // exactly 1.5x the original (60 -> 90), not lagged.
        ctl.updateGesture(
          focalPoint: const Offset(400, 400),
          scale: 1.5,
          rotation: 0,
          pointerCount: 2,
        );
        final live1 = c.read(interactionControllerProvider).liveTransform!;
        expect(live1.size.width, closeTo(60 * 1.5, 0.01),
            reason: 'multi-touch must not be smoothed: live size '
                'must equal raw engine output exactly');

        // Another frame at 2.5x: still direct.
        ctl.updateGesture(
          focalPoint: const Offset(400, 400),
          scale: 2.5,
          rotation: 0,
          pointerCount: 2,
        );
        final live2 = c.read(interactionControllerProvider).liveTransform!;
        expect(live2.size.width, closeTo(60 * 2.5, 0.01));
      },
    );

    test(
      'transient pointer drop+re-add mid-pinch does NOT lose scale '
      'progress (mirrors recogniser silent rebase)',
      () {
        // Real-world bug: capacitive touch panels routinely drop and
        // re-add a pointer for 1-2 frames mid-pinch. The recogniser
        // re-computes its `_baseDistance` on lift and again on
        // re-add, so its emitted cumulative `scale` RESTARTS from
        // 1.0. If the controller ignored the dip in pointerCount
        // (old behavior: lock-skip without recording it),
        // `_lastPointerCount` stayed at 2, no controller rebase
        // fired on the next 2-pointer frame, and `relScale = 1.0 /
        // _gestureScaleBase` shrank the layer back \u2014 the user
        // observed "scales a little, gets stuck, must re-pull".
        // The fix: record pointerCount in the lock-skip path so the
        // next 2-pointer frame triggers a controller rebase that
        // re-anchors `_gestureScaleBase` to 1.0 against the current
        // live transform. Pinch resumes seamlessly.
        final c = _makeContainer();
        _addRect(c, id: 'r', position: const Offset(370, 370));
        final layer = c.read(documentControllerProvider).layerById('r')!;
        final ctl = c.read(interactionControllerProvider.notifier);

        ctl.startGesture(
          layer: layer,
          focalPoint: const Offset(400, 400),
        );
        // Pinch out to 2.5x.
        for (final s in <double>[1.3, 1.8, 2.5]) {
          ctl.updateGesture(
            focalPoint: const Offset(400, 400),
            scale: s,
            rotation: 0,
            pointerCount: 2,
          );
        }
        final beforeGlitch =
            c.read(interactionControllerProvider).liveTransform!;
        expect(beforeGlitch.size.width, closeTo(60 * 2.5, 0.01));

        // Glitch frame: pointer drops for one frame.
        ctl.updateGesture(
          focalPoint: const Offset(400, 400),
          scale: 1.0,
          rotation: 0,
          pointerCount: 1,
        );

        // Recogniser re-bases on re-add and emits scale=1.0 with
        // 2 pointers. Pre-fix: this collapsed the layer back to
        // ~original size. Post-fix: controller rebases its own
        // reference to current live, so live size stays where it was.
        ctl.updateGesture(
          focalPoint: const Offset(400, 400),
          scale: 1.0,
          rotation: 0,
          pointerCount: 2,
        );
        final afterReadd =
            c.read(interactionControllerProvider).liveTransform!;
        expect(afterReadd.size.width, closeTo(beforeGlitch.size.width, 0.5),
            reason: 'pinch must NOT lose progress on a transient '
                'pointer-drop-re-add cycle. Pre-fix this collapsed '
                'the layer back toward its pre-pinch size, producing '
                'the chunked "scale a bit, get stuck" UX.');

        // Continue pinching: must keep growing from the post-glitch
        // size, not start over.
        for (final s in <double>[1.3, 1.8, 2.5]) {
          ctl.updateGesture(
            focalPoint: const Offset(400, 400),
            scale: s,
            rotation: 0,
            pointerCount: 2,
          );
        }
        final afterResume =
            c.read(interactionControllerProvider).liveTransform!;
        // 2.5x of the size right after the glitch.
        expect(afterResume.size.width,
            closeTo(beforeGlitch.size.width * 2.5, 1.0),
            reason: 'after the glitch, further finger spread must '
                'multiply against the current live size, not the '
                'original pre-pinch size');
      },
    );

    test(
      'fast pinch with relScale > maxGestureScale is clamped per-frame '
      '\u2014 the engine deliberately caps each frame against the '
      'session reference and does not auto-rebase past the cap',
      () {
        // Hardening contract: a single recogniser frame with a huge
        // `scale` (e.g. fingers jumping apart on a tablet, or a
        // synthesised test event) must not produce an unbounded
        // size change. The engine clamps each per-frame relative
        // scale to `EngineConstants.maxGestureScale` and the
        // session does not silently rebase to chase the recogniser
        // \u2014 that bound is intentional, it stops noisy events from
        // shooting layers off-screen.
        final c = _makeContainer();
        _addRect(c, id: 'r', position: const Offset(370, 370));
        final layer = c.read(documentControllerProvider).layerById('r')!;
        final ctl = c.read(interactionControllerProvider.notifier);

        ctl.startGesture(
          layer: layer,
          focalPoint: const Offset(400, 400),
        );
        // Single very fast frame: scale jumps to 20x. The engine
        // clamps it to maxGestureScale relative to the session's
        // reference, so the live size lands at the cap.
        ctl.updateGesture(
          focalPoint: const Offset(400, 400),
          scale: 20.0,
          rotation: 0,
          pointerCount: 2,
        );
        final afterFast = c
            .read(interactionControllerProvider)
            .liveTransform!;
        expect(
          afterFast.size.width,
          closeTo(60 * EngineConstants.maxGestureScale, 0.01),
          reason: 'a single fast pinch frame must be clamped to '
              '`initialWidth * maxGestureScale` \u2014 the engine\'s '
              'envelope guard.',
        );

        // Continued fast frames stay clamped against the same
        // (un-rebased) session reference.
        ctl.updateGesture(
          focalPoint: const Offset(400, 400),
          scale: 25.0,
          rotation: 0,
          pointerCount: 2,
        );
        final afterMore = c
            .read(interactionControllerProvider)
            .liveTransform!;
        expect(
          afterMore.size.width,
          closeTo(60 * EngineConstants.maxGestureScale, 0.01),
          reason: 'subsequent fast frames stay clamped against the '
              'same reference \u2014 no unbounded growth, no auto-rebase',
        );
      },
    );
  });

  group('continuous pinch — multi-select / group', () {
    test(
      'long continuous group pinch-out keeps scaling the whole '
      'group past the per-frame clamp',
      () {
        final c = _makeContainer();
        _addRect(c, id: 'a', position: const Offset(0, 0),
            size: const Size(100, 100));
        _addRect(c, id: 'b', position: const Offset(200, 0),
            size: const Size(100, 100));
        final doc = c.read(documentControllerProvider);
        final a = doc.layerById('a')!;
        final b = doc.layerById('b')!;
        final ctl = c.read(interactionControllerProvider.notifier);

        ctl.startGroupGesture(
          layers: [a, b],
          focalPoint: const Offset(150, 50),
        );

        for (final s in <double>[
          1.2, 1.6, 2.2, 3, 4, 5, 6, 7, 8,
          10, 13, 17, 22, 28,
        ]) {
          ctl.updateGroupGesture(
            focalPoint: const Offset(150, 50),
            scale: s,
            rotation: 0,
            pointerCount: 2,
          );
        }

        final live = c.read(interactionControllerProvider).groupLive;
        expect(live['a']!.size.width, greaterThan(100 * 10),
            reason: 'group pinch must keep growing each member past '
                'the per-frame clamp');
        expect(live['b']!.size.width, greaterThan(100 * 10));

        ctl.end();
        final aAfter =
            c.read(documentControllerProvider).layerById('a')!.transform;
        expect(aAfter.size.width, greaterThan(100 * 10),
            reason: 'end() must commit the scaled group');
      },
    );

    test(
      'long continuous group pinch-in keeps shrinking each member '
      'past the per-frame minGestureScale',
      () {
        final c = _makeContainer();
        _addRect(c, id: 'a', position: const Offset(0, 0),
            size: const Size(400, 400));
        _addRect(c, id: 'b', position: const Offset(500, 0),
            size: const Size(400, 400));
        final doc = c.read(documentControllerProvider);
        final a = doc.layerById('a')!;
        final b = doc.layerById('b')!;
        final ctl = c.read(interactionControllerProvider.notifier);

        ctl.startGroupGesture(
          layers: [a, b],
          focalPoint: const Offset(450, 200),
        );

        for (final s in <double>[
          0.9, 0.7, 0.5, 0.35, 0.25, 0.2,
          0.15, 0.10, 0.07, 0.05,
        ]) {
          ctl.updateGroupGesture(
            focalPoint: const Offset(450, 200),
            scale: s,
            rotation: 0,
            pointerCount: 2,
          );
        }

        final live = c.read(interactionControllerProvider).groupLive;
        expect(live['a']!.size.width, lessThan(60),
            reason: 'group pinch-in must keep shrinking past the '
                'per-frame clamp; lower bound is the 24 px engine '
                'minimum');
        expect(live['b']!.size.width, lessThan(60));
      },
    );

    test(
      'stray pointerCount=1 frame mid-group-pinch does NOT collapse '
      'the group into single-finger translate',
      () {
        final c = _makeContainer();
        _addRect(c, id: 'a', position: const Offset(0, 0),
            size: const Size(100, 100));
        _addRect(c, id: 'b', position: const Offset(200, 0),
            size: const Size(100, 100));
        final doc = c.read(documentControllerProvider);
        final a = doc.layerById('a')!;
        final b = doc.layerById('b')!;
        final ctl = c.read(interactionControllerProvider.notifier);

        ctl.startGroupGesture(
          layers: [a, b],
          focalPoint: const Offset(150, 50),
        );

        for (final s in <double>[1.3, 1.8, 2.4]) {
          ctl.updateGroupGesture(
            focalPoint: const Offset(150, 50),
            scale: s,
            rotation: 0,
            pointerCount: 2,
          );
        }
        final beforeA = c.read(interactionControllerProvider).groupLive['a']!;
        final beforeB = c.read(interactionControllerProvider).groupLive['b']!;
        expect(beforeA.size.width, greaterThan(100));

        // Glitched 1-pointer frame with a jumped focal.
        ctl.updateGroupGesture(
          focalPoint: const Offset(600, 600),
          scale: 2.4,
          rotation: 0,
          pointerCount: 1,
        );
        final duringA = c.read(interactionControllerProvider).groupLive['a']!;
        final duringB = c.read(interactionControllerProvider).groupLive['b']!;
        expect(duringA, beforeA,
            reason: 'stray 1-pointer frame must be ignored by the '
                'group session');
        expect(duringB, beforeB);

        // Resume pinching.
        for (final s in <double>[3.2, 4.5, 6.0, 8.0, 12.0]) {
          ctl.updateGroupGesture(
            focalPoint: const Offset(150, 50),
            scale: s,
            rotation: 0,
            pointerCount: 2,
          );
        }
        final afterA = c.read(interactionControllerProvider).groupLive['a']!;
        expect(afterA.size.width, greaterThan(beforeA.size.width * 2),
            reason: 'group pinch must resume growing after the glitch');
      },
    );

    test(
      'genuine one-finger drag on a freshly started session still '
      'enters move mode (transform-mode lock is NOT set until we '
      "see \u22652 pointers)",
      () {
        // Regression guard for the inverse failure: the lock must
        // only engage once we've actually observed a multi-touch
        // frame. A single-finger drag that never goes multi-touch
        // must translate the layer as before.
        final c = _makeContainer();
        _addRect(c, id: 'r', position: const Offset(100, 100));
        final layer = c.read(documentControllerProvider).layerById('r')!;
        final ctl = c.read(interactionControllerProvider.notifier);

        ctl.startGesture(
          layer: layer,
          focalPoint: const Offset(130, 130),
        );
        for (final f in <Offset>[
          Offset(140, 140),
          Offset(160, 150),
          Offset(200, 170),
        ]) {
          ctl.updateGesture(
            focalPoint: f,
            scale: 1.0,
            rotation: 0,
            pointerCount: 1,
          );
        }
        final live =
            c.read(interactionControllerProvider).liveTransform!;
        expect(live.position, isNot(const Offset(100, 100)),
            reason: 'pure one-finger drag must still translate');
      },
    );
  });
}
