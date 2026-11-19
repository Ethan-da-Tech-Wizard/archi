// ==============================================================================
// Program: PngExporter.qml
// Programmer: Ethan-da-Tech-Wizard
// Last Modified: November 18, 2026
// Purpose: High-resolution rasterization component for capturing canvas views to PNG.
//          Calculates tight bounding boxes around all active shapes, manages transparent
//          or solid background fills, and invokes native C++ image writer hooks.
//
// How it fits: ProjectWorkspace.qml owns one PngExporter (id `exporter`),
// calls exportTo(canvas, fileUrl) and listens to `finished(file, result)`.
// It renders a COPY of the diagram in a temporary off-view InfiniteCanvas so
// the user's pan/zoom/selection never affect the picture, then hands the
// image to C++ (`boardFiles.writePng`, DocumentFiles.h) which validates the
// size and writes the file atomically. For `archi --export-png` the same
// path runs without user interaction (see main.cpp, tests/png_export.cpp).
//
// Design decisions: the whole diagram is exported (not the visible part) with
// a 32 px margin; output is capped at 4096 px per side by shrinking `zoom`;
// a 15 s timer guarantees `finished` always fires even if rendering stalls.
//
// Known limits: grabToImage needs a visible, non-minimised window, which is
// why failures say "Keep the window open".
// ==============================================================================
import QtQuick

/**
 * Off-screen PNG renderer. One export at a time; `busy` is true meanwhile.
 * Signal `finished(file, result)`: `result` is the `{ok, error?, width?, height?}`
 * map from DocumentFiles::writePng, or a locally built `{ok:false, error}`.
 */
Item {
    id: exporter
    // Place the scratch canvas just right of the window (x = parent width + 1):
    // still inside the scene so Qt actually renders it, but outside the
    // visible area so the user never sees it. Disabled so it ignores input.
    x: parent ? parent.width + 1 : 0
    enabled: false
    // True from exportTo() until finish(); blocks overlapping exports.
    readonly property bool busy: scene !== null
    // The temporary InfiniteCanvas, or null when idle.
    property var scene: null
    // Destination chosen by the user, echoed back in `finished`.
    property url targetUrl
    // Emitted exactly once per exportTo() call that returned true (and also
    // for early failures), so callers can always re-enable their UI on it.
    signal finished(url file, var result)

    // Scratch canvas template: grid hidden (no editor dots in the picture),
    // no keyboard focus (must not steal it from the real canvas), `restoring`
    // true so loading shapes into it records no undo history.
    Component {
        id: sceneComponent
        InfiniteCanvas {
            showGrid: false
            focus: false
            restoring: true
        }
    }

    /**
     * Ends the export: stops the watchdog, destroys the scratch canvas and
     * reports the outcome. Safe to call when the scene is already gone.
     * @param result `{ok, ...}` object forwarded to listeners.
     */
    function finish(result) {
        timeout.stop()
        if (scene) scene.destroy()
        scene = null
        finished(targetUrl, result)
    }

    /**
     * Starts an export of @p canvas to @p file.
     * @param canvas InfiniteCanvas whose captureState() is rendered.
     * @param file   Destination `file:` URL (validated later by C++).
     * @returns {boolean} false if an export is already running or the scratch
     *          canvas could not be created (finished() is then emitted with an error).
     */
    function exportTo(canvas, file) {
        // Reject re-entrancy: a second export would reuse targetUrl/scene.
        if (busy) return false
        targetUrl = file
        // Copy by value, so edits made while the export runs cannot change the image.
        const state = canvas.captureState()
        // Same background colour as the visible board.
        scene = sceneComponent.createObject(exporter, {backgroundColor: canvas.backgroundColor})
        if (!scene) {
            finish({ok: false, error: "Could not prepare the PNG export"})
            return false
        }
        // Rebuild geometry on the scratch canvas; arrows are derived data.
        for (const shape of state.shapes) scene.shapesModel.append(shape)
        scene.arrows = state.arrows
        scene.rebuildArrowGeometry()
        // Arm the watchdog before queuing work so even a hang is reported.
        timeout.start()
        // Defer one event-loop turn so the scene is laid out (sizes, text metrics)
        // before measuring its bounds.
        Qt.callLater(render)
        return true
    }

    /**
     * Second phase: size the scratch canvas to the diagram and capture it.
     * Runs from Qt.callLater after exportTo(); aborts quietly if cancelled.
     */
    function render() {
        if (!scene) return
        // World-space box of the whole diagram (see InfiniteCanvas.diagramBounds).
        const bounds = scene.diagramBounds()
        // Corrupt or NaN coordinates would produce a zero/huge image; fail clearly.
        if (![bounds.x, bounds.y, bounds.width, bounds.height].every(Number.isFinite)
                || bounds.width <= 0 || bounds.height <= 0) {
            finish({ok: false, error: "The diagram has invalid dimensions"})
            return
        }
        // Fit within 4096 px: 4032 = 4096 - 2 x 32 margin px. scale <= 1 so small
        // diagrams are never enlarged. Scene size = content * scale + 64 px margins.
        // Limit the image to 4096 pixels per side, with a 32-pixel margin.
        const scale = Math.min(1, 4032 / bounds.width, 4032 / bounds.height)
        scene.width = Math.min(4096, Math.ceil(bounds.width * scale) + 64)
        scene.height = Math.min(4096, Math.ceil(bounds.height * scale) + 64)
        // Zoom and origin chosen so the bounds' top-left lands 32 px inside the image.
        scene.zoom = scale
        scene.viewX = bounds.x - 32 / scale
        scene.viewY = bounds.y - 32 / scale
        // Keep a local reference: if the user starts something else the guard in
        // the callback detects that `scene` changed and drops the stale result.
        const imageScene = scene
        const outputSize = Qt.size(scene.width, scene.height)
        // grabToImage multiplies its target size by the screen's pixel ratio, so
        // request size/ratio to get exactly scene.width x scene.height pixels.
        // grabToImage multiplies its target size by the screen's pixel ratio.
        const ratio = imageScene.Screen.devicePixelRatio
        const started = imageScene.grabToImage(function(grab) {
            if (exporter.scene !== imageScene) return
            exporter.finish(boardFiles.writePng(exporter.targetUrl, grab.image, outputSize))
        }, Qt.size(Math.ceil(scene.width / ratio), Math.ceil(scene.height / ratio)))
        // grabToImage returns false when it cannot render (e.g. window hidden).
        if (!started) finish({ok: false, error: "Could not capture the diagram. Keep the window open and try again."})
    }

    // Watchdog: 15 s is far above a normal export (< 1 s) yet short enough that
    // a stuck render does not leave the UI blocked.
    Timer {
        id: timeout
        interval: 15000
        onTriggered: exporter.finish({ok: false, error: "PNG export timed out. Restore the window and try again."})
    }
}
