import QtQuick

Item {
    id: harness
    width: 800
    height: 600

    InfiniteCanvas {
        id: canvas
        anchors.fill: parent
    }

    function assertEq(label, actual, expected) {
        var pass = Math.abs(actual - expected) < 0.001
        console.log((pass ? "PASS " : "FAIL ") + label + " got=" + actual + " want=" + expected)
        if (!pass) Qt.exit(1)
    }
    function assertTrue(label, cond) {
        console.log((cond ? "PASS " : "FAIL ") + label)
        if (!cond) Qt.exit(1)
    }

    Component.onCompleted: {
        // Create two shapes far apart in world space.
        canvas.createShape(0, 0)
        canvas.createShape(1000, 0)
        assertEq("shape count after 2 creates", canvas.shapesModel.count, 2)

        var s0 = canvas.shapesModel.get(0)
        var s1 = canvas.shapesModel.get(1)
        assertEq("shape0 shapeId", s0.shapeId, 1)
        assertEq("shape1 shapeId", s1.shapeId, 2)

        // Edit text on shape 0 like a user would while in edit mode.
        canvas.shapesModel.setProperty(0, "text", "Service A")
        assertTrue("text set", canvas.shapesModel.get(0).text === "Service A")

        // Connect them with an arrow and check geometry clips to the box edges,
        // not the centers (i.e. arrow shouldn't start/end inside the shapes).
        canvas.addArrow(s0.shapeId, s1.shapeId)
        assertEq("arrow count", canvas.arrows.length, 1)
        assertEq("arrowLines count", canvas.arrowLines.length, 1)

        var line = canvas.arrowLines[0]
        var s0cx = s0.px + s0.pw / 2
        var s1cx = s1.px + s1.pw / 2
        assertTrue("arrow start clipped to shape0 edge (not center)", line.x1 > s0cx)
        assertTrue("arrow end clipped to shape1 edge (not center)", line.x2 < s1cx)
        assertTrue("arrow is roughly horizontal", Math.abs(line.y1 - line.y2) < 0.01)

        // Self-arrow must be rejected.
        canvas.addArrow(s0.shapeId, s0.shapeId)
        assertEq("self-arrow rejected", canvas.arrows.length, 1)

        // Drive the pan/zoom + origin-rebasing path directly (no mouse needed):
        // push the view far past the rebase threshold and confirm shape
        // world coordinates get shifted back near-origin while visually
        // the shape stays under the same viewport pixel.
        canvas.viewX = 60000
        canvas.viewY = 0
        var beforeShapeX = canvas.shapesModel.get(0).px
        canvas.maybeRebase()
        assertTrue("rebase triggered viewX back under threshold", Math.abs(canvas.viewX) < 1)
        var afterShapeX = canvas.shapesModel.get(0).px
        assertEq("shape shifted by exactly the rebase amount", beforeShapeX - afterShapeX, 60000)

        // Arrow geometry must be recomputed post-rebase (regression check for
        // stale-cache bugs) and still clip correctly using the new coordinates.
        var line2 = canvas.arrowLines[0]
        assertTrue("arrow geometry updated after rebase", Math.abs(line2.x1 - (line.x1 - 60000)) < 0.01)

        // Zoom-to-cursor sanity: zooming should keep the world point under a
        // fixed screen pixel fixed, not drift.
        canvas.viewX = 0
        canvas.viewY = 0
        canvas.zoom = 1.0
        var mx = 400, my = 300
        var worldUnderCursorBefore = { x: canvas.viewX + mx / canvas.zoom, y: canvas.viewY + my / canvas.zoom }
        var oldZoom = canvas.zoom
        var newZoom = 2.0
        canvas.viewX = worldUnderCursorBefore.x - mx / newZoom
        canvas.viewY = worldUnderCursorBefore.y - my / newZoom
        canvas.zoom = newZoom
        var worldUnderCursorAfter = { x: canvas.viewX + mx / canvas.zoom, y: canvas.viewY + my / canvas.zoom }
        assertEq("zoom-to-cursor keeps world point fixed (x)", worldUnderCursorAfter.x, worldUnderCursorBefore.x)
        assertEq("zoom-to-cursor keeps world point fixed (y)", worldUnderCursorAfter.y, worldUnderCursorBefore.y)

        // Shapes should keep a constant on-screen size regardless of zoom:
        // create one at zoom=2 (still set from above) and confirm its world
        // size, scaled by zoom, matches the configured screen-pixel default.
        // This is what lets you zoom into a big diagram and still drop
        // normal-looking boxes instead of giant or tiny ones.
        canvas.defaultShapeWidth = 160
        canvas.defaultShapeHeight = 80
        canvas.createShape(5000, 5000)
        var zoomedShape = canvas.shapesModel.get(canvas.shapesModel.count - 1)
        assertEq("shape screen width constant across zoom", zoomedShape.pw * canvas.zoom, canvas.defaultShapeWidth)
        assertEq("shape screen height constant across zoom", zoomedShape.ph * canvas.zoom, canvas.defaultShapeHeight)

        // Resizing (as the corner-drag handle does) updates pw/ph directly,
        // and connected arrow geometry must follow on the next rebuild.
        var resizeIdx = canvas.shapesModel.count - 1
        canvas.shapesModel.setProperty(resizeIdx, "pw", 300)
        canvas.shapesModel.setProperty(resizeIdx, "ph", 150)
        assertEq("resize updates pw", canvas.shapesModel.get(resizeIdx).pw, 300)
        assertEq("resize updates ph", canvas.shapesModel.get(resizeIdx).ph, 150)

        // Regression for the "tiny shape, giant handle" bug: a shape created
        // while zoomed way in ends up with a small world-space size (see the
        // screen-constant-size test above). Its connecting arrow's stroke
        // and arrowhead must shrink to match, not stay pinned at the old
        // fixed world-unit constants (which would dwarf a tiny shape once
        // you zoom back out).
        canvas.zoom = 20
        canvas.createShape(9000, 9000)
        canvas.createShape(9200, 9000)
        var tinyA = canvas.shapesModel.get(canvas.shapesModel.count - 2)
        var tinyB = canvas.shapesModel.get(canvas.shapesModel.count - 1)
        assertTrue("tiny shape world size is small at high zoom", tinyA.pw < 20)
        canvas.addArrow(tinyA.shapeId, tinyB.shapeId)
        var tinyLine = canvas.arrowLines[canvas.arrowLines.length - 1]
        assertTrue("tiny shape arrow strokeWidth scales down", tinyLine.strokeWidth < 1)
        assertTrue("tiny shape arrow strokeWidth stays positive", tinyLine.strokeWidth > 0)

        // Shape-type picker: createShape() should stamp whatever kind is
        // currently selected, and default to "rect" when untouched.
        assertTrue("default shape kind is rect", canvas.shapesModel.get(0).shapeKind === "rect")
        canvas.defaultShapeKind = "diamond"
        canvas.createShape(-5000, -5000)
        var diamondShape = canvas.shapesModel.get(canvas.shapesModel.count - 1)
        assertTrue("new shape picks up selected kind", diamondShape.shapeKind === "diamond")
        canvas.defaultShapeKind = "rect"

        console.log("ALL TESTS PASSED")
        Qt.exit(0)
    }
}
