import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../application/canvas_capture.dart';
import '../../application/interaction_controller.dart';
import '../../application/live_overlay_controller.dart';
import '../../application/mask_edit_controller.dart';
import '../../application/selection_controller.dart';
import '../../application/viewport_controller.dart';
import '../../text/application/add_text_composer_state.dart';
import 'canvas/canvas_board.dart';
import 'canvas/canvas_chrome.dart';
import 'canvas/canvas_gesture_router.dart';
import 'canvas/canvas_multi_tap.dart';
import 'canvas/canvas_viewport_host.dart';

/// Root canvas widget.
///
/// Renders the **logical canvas board** (its size comes from the document,
/// NOT from the screen) inside a [Transform] driven by the
/// [ViewportController]. Layer coordinates therefore stay in logical
/// canvas pixels regardless of device size, zoom or pan.
///
/// Pointer mapping: the `_canvasKey` lives on the inner board. A call to
/// `RenderBox.globalToLocal` on that box automatically walks the viewport
/// transform, so the existing interaction engine (which receives logical
/// coordinates) does not have to change.
///
/// This widget is the **host**: it owns the keys, the four collaborators
/// the canvas is split into, and the build skeleton that wires them
/// together. The work itself lives next door in `canvas/`:
///
///   * [CanvasViewportHost] — the fit / refit / restore lifecycle and
///     per-project viewport persistence;
///   * [CanvasGestureRouter] — raw pointer bookkeeping, tap / double-tap
///     / long-press routing, the chrome-quad claim tests, the
///     select-and-move surface and the two-finger viewport path;
///   * [buildCanvasBoard] — the document board (background, layers,
///     guides, paint surface, dim mask + border);
///   * [buildCanvasChrome] — the screen-space overlays.
class EditorCanvas extends ConsumerStatefulWidget {
  const EditorCanvas({super.key});

  @override
  ConsumerState<EditorCanvas> createState() => _EditorCanvasState();
}

class _EditorCanvasState extends ConsumerState<EditorCanvas>
    with WidgetsBindingObserver {
  final GlobalKey _canvasKey = GlobalKey();

  /// Key on the ClipRect the viewport [Transform] is laid out in.
  /// Hands the paint surface the render box whose local space
  /// `viewport.translation` is defined in, so its two-finger rescue
  /// can feed [ViewportController.gestureUpdate] focals in the same
  /// space the background scale handler uses (`localFocalPoint`) —
  /// global focals would drift the zoom anchor by the AppBar /
  /// status-bar offset.
  final GlobalKey _viewportBodyKey = GlobalKey();

  late final CanvasViewportHost _viewportHost;
  late final CanvasGestureRouter _gestureRouter;
  late final CanvasMultiTapRecognizer _multiTap;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _viewportHost = CanvasViewportHost(
      ref: ref,
      isMounted: () => mounted,
      onFirstFit: () => setState(() {}),
    );
    _gestureRouter = CanvasGestureRouter(
      ref: ref,
      boardKey: _canvasKey,
      hostContext: () => context,
    );
    _multiTap = CanvasMultiTapRecognizer(ref);
    _viewportHost.attach();
  }

  @override
  void dispose() {
    _viewportHost.dispose();
    _gestureRouter.dispose();
    WidgetsBinding.instance.removeObserver(this);
    // Note: we deliberately do NOT call `interactionController.cancel()`
    // here — Riverpod's `ref` is unsafe inside dispose because the
    // BuildContext is already deactivated. The other cancel triggers
    // (pointer-cancel listener + app-lifecycle observer + the in-
    // controller document subscription) cover the realistic
    // interruption cases. A widget-unmount mid-gesture without any of
    // those signals is rare enough to accept; the next mount will see
    // a stale session but `cancel()` is safe to call from any later
    // gesture entry point.
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Anything other than `resumed` means the user has lost focus on
    // the editor (incoming call, app switcher, screen lock, control
    // centre, …). Cancel rather than risk committing a half-finished
    // gesture when the app comes back. `cancel()` is idempotent so the
    // common case (no active gesture) costs nothing.
    if (state != AppLifecycleState.resumed) {
      ref.read(interactionControllerProvider.notifier).cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    // The canvas is the ONLY consumer that wants the merged "committed
    // + in-flight overlay" view, so a 60-fps slider drag rebuilds the
    // canvas (correct — it must show the preview) without rebuilding
    // the layers panel, undo rail, or any other widget that watches
    // [documentControllerProvider] directly.
    final doc = ref.watch(renderedDocumentProvider);
    final selection = ref.watch(selectionControllerProvider);
    final viewport = ref.watch(viewportControllerProvider);
    final activeLayerId = ref.watch(
      interactionControllerProvider.select((s) => s.session?.layerId),
    );
    final snapGuides = ref.watch(
      interactionControllerProvider.select((s) => s.snapGuides),
    );
    final spacingGuides = ref.watch(
      interactionControllerProvider.select((s) => s.spacingGuides),
    );
    // While the Add Text composer is up, every piece of selection
    // chrome is suppressed so the user's attention goes to the input
    // only. The staged layer keeps rendering (it shows where the
    // text will land), but handles, HUD, contextual toolbars and the
    // quick-action pill all hide. The modal scrim already dims the
    // canvas; this flag handles the rest.
    final addTextComposerOpen = ref.watch(addTextComposerOpenProvider);
    // Mask-edit mode replaces the selection chrome with its own
    // overlay: handles, HUD, floating toolbars and quick actions all
    // hide while the region editor owns the layer.
    final maskEditActive = ref.watch(
      maskEditControllerProvider.select((s) => s.active),
    );
    final docSize = Size(doc.width, doc.height);
    final boardBoundaryKey = ref.watch(canvasBoardBoundaryKeyProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportHost.syncToLayout(
          screen: constraints.biggest,
          docSize: docSize,
        );

        return Listener(
          // Surface OS-issued pointer cancellations to the interaction
          // controller. Real-world triggers: a system gesture (back-
          // swipe, notification shade), a parent route grabbing the
          // pointer, a touch being interrupted by an incoming call.
          // Without this, an in-flight gesture would silently leak its
          // session and the user could see a "ghost" live transform on
          // resume. `cancel()` is idempotent so off-session events cost
          // nothing.
          onPointerDown: (e) {
            // Raw sequence bookkeeping FIRST (see
            // [CanvasGestureRouter.hasRawPointersDown]).
            // This runs after every deeper recogniser has already seen
            // the down event, so claim predicates observed the set
            // WITHOUT the current pointer — exactly the "is another
            // finger already down?" question they need answered.
            _gestureRouter.trackPointerDown(e);
            _multiTap.onPointerDown(e);
          },
          onPointerMove: _multiTap.onPointerMove,
          onPointerUp: (e) {
            _gestureRouter.trackPointerUp(e);
            _multiTap.onPointerUp(e);
          },
          onPointerCancel: (e) {
            _gestureRouter.trackPointerCancel(e);
            _multiTap.onPointerCancel(e);
            _gestureRouter.handleOsPointerCancel();
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) =>
                _gestureRouter.onBackgroundTapUp(d.globalPosition, doc.layers),
            // Long-press: the dedicated mobile entry to multi-select
            // mode. Fires after the system long-press timeout on any
            // pointer that reaches this detector — taps on empty
            // canvas and on un-selected layers. Long-press over the
            // SELECTED layer never reaches here (its body surface
            // claims the arena on down); the body recogniser's own
            // long-press timer re-injects that intent via
            // [onBodyLongPress] → the same [handleLongPress].
            //
            // NOTE: deliberately NO onDoubleTapDown here. Registering
            // it would put a DoubleTapGestureRecognizer in the arena,
            // which holds every plain tap hostage for the ~300ms
            // double-tap timeout before onTapUp can fire — the audit's
            // "first tap feels laggy" finding. Double-tap detection
            // lives in [handleTap]'s window bookkeeping instead, so
            // single taps resolve instantly.
            onLongPressStart: (d) {
              _gestureRouter.handleLongPress(d.globalPosition, doc.layers);
            },
            // Background pan + pinch-to-zoom for the viewport. Layer body
            // recognisers sit deeper in the tree and win the gesture arena
            // only when the first finger lands on the selection's chrome
            // quad (contract §5 row 4); touches off the quad — including
            // whole sequences while a selection exists — fall through to
            // this handler, which is what makes rows 6 (two-finger always
            // navigates) and 7 (off-layer drag pans) work.
            //
            // Exclusivity backstop (kept deliberately after the tb3 1/7
            // re-routing): skipping start/update while an interaction
            // session is active prevents the viewport from panning or
            // zooming "alongside" an object transform in split-ownership
            // races — e.g. finger A rests off-quad (unclaimed, sub-slop)
            // while finger B starts a body session on the quad; when A
            // finally moves, this recogniser wins A's arena and would
            // otherwise pan under the live transform. During a normal
            // off-quad pinch no session exists (`isActive` is false), so
            // this guard never blocks legitimate viewport navigation.
            onScaleStart: _gestureRouter.onScaleStart,
            onScaleUpdate: _gestureRouter.onScaleUpdate,
            onScaleEnd: _gestureRouter.onScaleEnd,
            // v2 workspace: a step deeper than the chrome's surface
            // (warm in light, deep ink in dark — never pure black)
            // so the bars/panels visibly float above it and the
            // canvas floats on it.
            child: ColoredBox(
              color: AppTokens.of(context).workspace,
              child: ClipRect(
                // Keyed so the paint surface can map global pointer
                // positions into this box's local space — the space
                // `viewport.translation` lives in (see
                // [_viewportBodyKey]).
                key: _viewportBodyKey,
                // Outer Stack: viewport-transformed canvas board (bottom)
                // + screen-space chrome (top). Selection handles + HUD live
                // in the screen-space layer so they stay constant size in
                // dp regardless of document size or zoom.
                //
                // Until the first auto-fit lands the canvas would briefly
                // appear at identity (top-left, 1:1) — a flash that reads
                // as "the canvas is the wrong size." Hiding the contents
                // with Visibility (rather than skipping the subtree) keeps
                // layout/state alive so the post-frame fit has correct
                // constraints to work with.
                child: Visibility(
                  visible: _viewportHost.fittedOnce,
                  maintainState: true,
                  maintainSize: true,
                  maintainAnimation: true,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ...buildCanvasBoard(
                        boardKey: _canvasKey,
                        boardBoundaryKey: boardBoundaryKey,
                        viewportBodyKey: _viewportBodyKey,
                        doc: doc,
                        docSize: docSize,
                        selection: selection,
                        viewport: viewport,
                        activeLayerId: activeLayerId,
                        snapGuides: snapGuides,
                        spacingGuides: spacingGuides,
                      ),
                      ...buildCanvasChrome(
                        router: _gestureRouter,
                        doc: doc,
                        selection: selection,
                        viewport: viewport,
                        addTextComposerOpen: addTextComposerOpen,
                        maskEditActive: maskEditActive,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
