import QtQuick

Item {
    id: exporter
    // Keep the temporary scene in the window for rendering, outside its viewport.
    x: parent ? parent.width + 1 : 0
    enabled: false
    readonly property bool busy: scene !== null
    property var scene: null
    property url targetUrl
    signal finished(url file, var result)

    Component {
        id: sceneComponent
        InfiniteCanvas {
            showGrid: false
            focus: false
            restoring: true
        }
    }

    function finish(result) {
        timeout.stop()
        if (scene) scene.destroy()
        scene = null
        finished(targetUrl, result)
    }

    function exportTo(canvas, file) {
        if (busy) return false
        targetUrl = file
        const state = canvas.captureState()
        scene = sceneComponent.createObject(exporter, {backgroundColor: canvas.backgroundColor})
        if (!scene) {
            finish({ok: false, error: "Could not prepare the PNG export"})
            return false
        }
        for (const shape of state.shapes) scene.shapesModel.append(shape)
        scene.arrows = state.arrows
        scene.rebuildArrowGeometry()
        timeout.start()
        Qt.callLater(render)
        return true
    }

    function render() {
        if (!scene) return
        const bounds = scene.diagramBounds()
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
        const outputSize = Qt.size(scene.width, scene.height)
        // grabToImage multiplies its target size by the screen's pixel ratio.
        const ratio = imageScene.Screen.devicePixelRatio
        const started = imageScene.grabToImage(function(grab) {
            if (exporter.scene !== imageScene) return
            exporter.finish(boardFiles.writePng(exporter.targetUrl, grab.image, outputSize))
        }, Qt.size(Math.ceil(scene.width / ratio), Math.ceil(scene.height / ratio)))
        if (!started) finish({ok: false, error: "Could not capture the diagram. Keep the window open and try again."})
    }

    Timer {
        id: timeout
        interval: 15000
        onTriggered: exporter.finish({ok: false, error: "PNG export timed out. Restore the window and try again."})
    }
}
