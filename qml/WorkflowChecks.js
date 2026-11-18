// Program: archi - WorkflowChecks.js
// Programmer: Ethan-da-Tech-Wizard (written with Claude, an AI assistant)
// Last Modified: 2026-11-18
// Purpose: JavaScript library used by the workflow view to run simple structural checks (missing endpoints, unlabeled decisions, unreachable nodes, cycles) on a flowchart and return a text report.

// Mark this file as a shared "library" so QML loads it once and it keeps no per-component state.
.pragma library

/** Check one flowchart view (its shapes and arrows) and return a multi-line text report of any structural problems found. */
function analyze(view) {
    // All boxes (nodes) in the diagram.
    const nodes = view.shapes
    // A set of every node id, used for quick lookups and to spot duplicates.
    const ids = new Set(nodes.map(n => n.shapeId))
    // Map from each node id to the list of arrows leaving it (filled in below).
    const outgoing = new Map(nodes.map(n => [n.shapeId, []]))
    // The warnings and errors collected so far.
    const messages = []
    // Helper that makes a readable name for a node: its key (or its number) plus its text on one line.
    const label = n => (n.nodeKey || "#" + n.shapeId) + " " + n.text.replace(/\n/g, " ")
    // Go through every arrow and file it under the node it starts from.
    for (const edge of view.arrows) {
        // An arrow pointing from or to a node that does not exist is an error.
        if (!ids.has(edge.fromId) || !ids.has(edge.toId)) {
            messages.push("ERROR: Connection has a missing endpoint")
            continue
        }
        outgoing.get(edge.fromId).push(edge)
    }
    // If the set is smaller than the node list, some ids were used twice.
    if (ids.size !== nodes.length) messages.push("ERROR: Duplicate node IDs")
    // Nothing to analyse in an empty view.
    if (!nodes.length) return "Empty view."
    // Per-node checks.
    for (const node of nodes) {
        const edges = outgoing.get(node.shapeId)
        // A node with no text is probably unfinished.
        if (!node.text.trim()) messages.push("REVIEW: Unnamed node " + label(node))
        // Decisions (diamonds) should branch, and every branch should have its own label.
        if (node.shapeKind === "decision" || node.shapeKind === "diamond") {
            if (edges.length < 2) messages.push("REVIEW: Decision needs branches: " + label(node))
            const labels = edges.map(e => (e.label || "").trim().toLowerCase())
            if (labels.some(text => !text)) messages.push("REVIEW: Unlabeled decision branch: " + label(node))
            if (new Set(labels).size !== labels.length) messages.push("REVIEW: Duplicate branch labels: " + label(node))
        }
    }
    // Walk the graph from the entry node to find which nodes can be reached.
    const entry = view.entryId || nodes[0].shapeId
    // Nodes already visited.
    const reached = new Set()
    // Nodes still waiting to be visited (a simple stack, so no recursion is needed).
    const queue = [entry]
    while (queue.length) {
        const id = queue.pop()
        if (reached.has(id)) continue
        reached.add(id)
        for (const edge of outgoing.get(id) || []) queue.push(edge.toId)
    }
    // Anything not visited is unreachable from the start.
    for (const node of nodes)
        if (!reached.has(node.shapeId)) messages.push("REVIEW: Unreachable from entry: " + label(node))
    // Kahn's algorithm detects cycles without recursive stack growth.
    // Count how many arrows point into each node.
    const indegree = new Map(nodes.map(n => [n.shapeId, 0]))
    for (const edges of outgoing.values())
        for (const edge of edges) indegree.set(edge.toId, indegree.get(edge.toId) + 1)
    // Start with nodes nothing points to.
    const roots = nodes.filter(n => indegree.get(n.shapeId) === 0).map(n => n.shapeId)
    // Count of nodes successfully removed in order; if some can never be removed, there is a loop.
    let removed = 0
    while (roots.length) {
        const id = roots.pop()
        removed++
        for (const edge of outgoing.get(id)) {
            indegree.set(edge.toId, indegree.get(edge.toId) - 1)
            if (indegree.get(edge.toId) === 0) roots.push(edge.toId)
        }
    }
    if (removed < nodes.length) messages.push("REVIEW: Cycle present; verify its exit condition and work budget")
    // A flowchart should have at least one node with no outgoing arrows (an end).
    if (!nodes.some(n => outgoing.get(n.shapeId).length === 0)) messages.push("REVIEW: No terminal path")
    // Build the final report: a summary line, the messages, and a reminder that these checks only look at structure.
    return nodes.length + " nodes, " + view.arrows.length + " connections. Entry #" + entry + ".\n\n"
        + (messages.length ? messages.join("\n") : "No structural issues found.")
        + "\n\nSemantic correctness: not established by structural checks."
}
