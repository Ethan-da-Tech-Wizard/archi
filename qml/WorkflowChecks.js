.pragma library

// How it fits: ProjectWorkspace.qml imports this file as a stateless library
// (`.pragma library` above means one shared instance with no access to QML
// ids or properties), calls analyze() with a plain snapshot of the canvas and
// shows the returned string in its "Check workflow" panel. Nothing in this
// file draws or mutates the diagram; it only reads the snapshot.
//
// Inputs/outputs: see the JSDoc on analyze(). Output is human-readable text,
// not a structured result, because the only consumer is a text panel.
//
// Known limits: every finding is structural (shape wiring), never semantic.
// The result always ends by saying so, so nobody mistakes "no issues" for
// "the process is correct". Diamonds/decisions are the only shape kinds with
// special rules; everything else is treated as a plain step.
//
// How to test: LogicTest.qml builds small graphs and calls analyze() directly.
// ==============================================================================
// Program: WorkflowChecks.js
// Programmer: Ethan-da-Tech-Wizard
// Last Modified: November 18, 2026
// Purpose: Directed graph topological analysis library for Archi diagram validation.
//          Validates workflow graphs by detecting broken arrow connections, identifying
//          unreachable nodes via BFS reachability analysis, checking decision branch
//          completeness, and executing Kahn's topological sort algorithm to detect cycles.
// ==============================================================================
/**
 * Runs every structural check on one diagram view and returns a report.
 *
 * Checks, in order: dangling arrows, duplicate ids, unnamed nodes, decision
 * branch rules, reachability from the entry node (graph search), and cycle /
 * terminal-path detection (Kahn's algorithm). Findings are prefixed ERROR
 * (data is corrupt) or REVIEW (legal but suspicious).
 *
 * @param {{shapes: Array<{shapeId:number, shapeKind:string, text:string, nodeKey?:string}>,
 *          arrows: Array<{fromId:number, toId:number, label?:string}>,
 *          entryId?: number}} view  Snapshot of the canvas. `entryId` picks the
 *          start node for reachability; when absent the first shape is used.
 * @returns {string} Multi-line report: a summary line, one line per finding
 *          (or "No structural issues found."), and a closing disclaimer.
 *          Returns just "Empty view." when there are no shapes.
 */
function analyze(view) {
    // `nodes` is the single declaration of the shape list for this function;
    // everything below indexes into it. (A second declaration of `nodes` once broke the
    // macOS CI build, so do not add another.)
    const nodes = view.shapes
    // Set of valid ids: lets edge validation test an endpoint in O(1) and, by
    // comparing its size to nodes.length, reveals duplicate ids.
    const ids = new Set(nodes.map(n => n.shapeId))
    // Adjacency list: shapeId -> arrows leaving that shape. Every node gets an
    // entry up front so later lookups never return undefined.
    const outgoing = new Map(nodes.map(n => [n.shapeId, []]))
    const messages = []
    // Short display name for messages, preferring the stable user key (nodeKey)
    // and falling back to the numeric id; newlines in the text are flattened so
    // each finding stays on one report line.
    const label = n => (n.nodeKey || "#" + n.shapeId) + " " + n.text.replace(/\n/g, " ")
    // Arrows whose endpoint no longer exists (shape deleted) cannot be followed,
    // so they are reported and skipped rather than added to the adjacency list.
    for (const edge of view.arrows) {
        if (!ids.has(edge.fromId) || !ids.has(edge.toId)) {
            messages.push("ERROR: Connection has a missing endpoint")
            continue
        }
        outgoing.get(edge.fromId).push(edge)
    }
    // Two shapes sharing an id would make the adjacency map ambiguous; the
    // Set built earlier collapses them, so a size mismatch exposes it.
    if (ids.size !== nodes.length) messages.push("ERROR: Duplicate node IDs")
    // Early exit: with no shapes there is nothing to analyze, and nodes[0]
    // below would be undefined.
    if (!nodes.length) return "Empty view."
    // Per-node rules that only need the node and its outgoing arrows.
    for (const node of nodes) {
        const edges = outgoing.get(node.shapeId)
        if (!node.text.trim()) messages.push("REVIEW: Unnamed node " + label(node))
        // A decision must fork (>= 2 exits) and each exit needs a distinct,
        // non-empty label (compared case-insensitively) or the reader cannot tell
        // the branches apart.
        if (node.shapeKind === "decision" || node.shapeKind === "diamond") {
            if (edges.length < 2) messages.push("REVIEW: Decision needs branches: " + label(node))
            const labels = edges.map(e => (e.label || "").trim().toLowerCase())
            if (labels.some(text => !text)) messages.push("REVIEW: Unlabeled decision branch: " + label(node))
            if (new Set(labels).size !== labels.length) messages.push("REVIEW: Duplicate branch labels: " + label(node))
        }
    }
    // Reachability: depth-first walk (stack via pop) from the entry. The entry
    // is the user-chosen start if set, else the first shape in draw order.
    const entry = view.entryId || nodes[0].shapeId
    const reached = new Set()
    const queue = [entry]
    while (queue.length) {
        const id = queue.pop()
        if (reached.has(id)) continue
        reached.add(id)
        for (const edge of outgoing.get(id) || []) queue.push(edge.toId)
    }
    // Anything the walk never touched is disconnected from the main flow.
    for (const node of nodes)
        if (!reached.has(node.shapeId)) messages.push("REVIEW: Unreachable from entry: " + label(node))
    // Kahn's algorithm: count incoming arrows per node, then repeatedly remove
    // nodes with none. If some nodes can never be removed they sit on a cycle.
    // An iterative loop is used so deep graphs cannot overflow the call stack.
    const indegree = new Map(nodes.map(n => [n.shapeId, 0]))
    for (const edges of outgoing.values())
        for (const edge of edges) indegree.set(edge.toId, indegree.get(edge.toId) + 1)
    // Roots are the nodes with no incoming arrows; they seed the removal queue.
    const roots = nodes.filter(n => indegree.get(n.shapeId) === 0).map(n => n.shapeId)
    let removed = 0
    while (roots.length) {
        const id = roots.pop()
        removed++
        for (const edge of outgoing.get(id)) {
            indegree.set(edge.toId, indegree.get(edge.toId) - 1)
            if (indegree.get(edge.toId) === 0) roots.push(edge.toId)
        }
    }
    // Cycles are only flagged for review because loops (retry, polling) are
    // legitimate as long as they have an exit condition.
    if (removed < nodes.length) messages.push("REVIEW: Cycle present; verify its exit condition and work budget")
    // A flow with no node lacking outgoing arrows never ends.
    if (!nodes.some(n => outgoing.get(n.shapeId).length === 0)) messages.push("REVIEW: No terminal path")
    // Summary line + findings + disclaimer; the double newlines are the paragraph
    // breaks the report panel renders.
    return nodes.length + " nodes, " + view.arrows.length + " connections. Entry #" + entry + ".\n\n"
        + (messages.length ? messages.join("\n") : "No structural issues found.")
        + "\n\nSemantic correctness: not established by structural checks."
}
