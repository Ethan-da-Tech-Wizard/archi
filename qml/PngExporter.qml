// Program: archi - PngExporter.qml
// Programmer: Ethan-da-Tech-Wizard (written with Claude, an AI assistant)
// Last Modified: 2026-11-18
// Purpose: QML helper that exports a diagram to a PNG file by building a temporary off-screen InfiniteCanvas, sizing it to the diagram (max 4096 pixels per side), grabbing it as an image and asking boardFiles to write it.

import QtQuick

// Invisible helper item; it does not draw anything itself.
Item {
    id: exporter
    // Keep the temporary scene in the window for rendering, outside its viewport.
    x: parent ? parent.width + 1 : 0
    // Disabled so it never takes mouse or keyboard input.
    enabled: false
    // True while an export is in progress (a temporary scene exists).
    readonly property bool busy: scene !== null
    // The temporary canvas used for rendering (null when idle).
    property var scene: null
    // The file the PNG will be written to.
    property url targetUrl
    // Emitted when the export ends, with the file and a result map (ok or error).
    signal finished(url file, var result)

    // A recipe for creating the temporary canvas: no grid, no focus, and in restoring mode.
    Component {
        id: sceneComponent
        InfiniteCanvas {
            showGrid: false
            focus: false
            restoring: true
        }
    }

    // Finish the export: stop the timer, delete the temporary canvas and tell listeners the result.
    function finish(result) {
        timeout.stop()
        if (scene) scene.destroy()
        scene = null
        finished(targetUrl, result)
    }

    // Start an export of the given canvas to the given file; returns false if one is already running.
    function exportTo(canvas, file) {
        if (busy) return false
        targetUrl = file
        // Copy the shapes and arrows from the live canvas.
        const state = canvas.captureState()
        // Create the temporary canvas with the same background color.
        scene = sceneComponent.createObject(exporter, {backgroundColor: canvas.backgroundColor})
        if (!scene) {
            finish({ok: false, error: "Could not prepare the PNG export"})
            return false
        }
        // Fill the temporary canvas with the copied shapes and arrows and recalculate arrow lines.
        for (const shape of state.shapes) scene.shapesModel.append(shape)
        scene.arrows = state.arrows
        scene.rebuildArrowGeometry()
        // Start the safety timeout and render on the next event-loop turn.
        timeout.start()
        Qt.callLater(render)
        return true
    }

    // Size and position the temporary canvas around the diagram, grab it as an image and write the PNG.
    function render() {
        if (!scene) return
        // Get the box that contains the whole diagram.
        const bounds = scene.diagramBounds()
        // Stop if the box is not made of real positive numbers.
        if (![bounds.x, bounds.y, bounds.width, bounds.height].every(Number.isFinite)
                || bounds.width <= 0 || bounds.height <= 0) {
            finish({ok: false, error: "The diagram has invalid dimensions"})
            return
        }
        // Limit the image to 4096 pixels per side, with a 32-pixel margin.
        const scale = Math.min(1, 4032 / bounds.width, 4032 / bounds.height)
        scene.width = Math.min(4096, Math.ceil(bounds.width * scale) + 64)
        scene.height = Math.min(4096, Math.ceil(bounds.height * scale) + 64)
        scene.zoom = scale
        scene.viewX = bounds.x - 32 / scale
        scene.viewY = bounds.y - 32 / scale
        const imageScene = scene
        // Remember the output size in pixels.
        const outputSize = Qt.size(scene.width, scene.height)
        // grabToImage multiplies its target size by the screen's pixel ratio.
        const ratio = imageScene.Screen.devicePixelRatio
        // Grab the image asynchronously; the callback runs when the picture is ready.
        const started = imageScene.grabToImage(function(grab) {
            // Ignore the result if the export was already cancelled or replaced.
            if (exporter.scene !== imageScene) return
            // Write the PNG file and report the result.
            exporter.finish(boardFiles.writePng(exporter.targetUrl, grab.image, outputSize))
        }, Qt.size(Math.ceil(scene.width / ratio), Math.ceil(scene.height / ratio)))
        // Report an error if the grab could not even start.
        if (!started) finish({ok: false, error: "Could not capture the diagram. Keep the window open and try again."})
    }

    // Safety timer: give up after 15 seconds so the export never hangs.
    Timer {
        id: timeout
        interval: 15000
        onTriggered: exporter.finish({ok: false, error: "PNG export timed out. Restore the window and try again."})
    }
}
