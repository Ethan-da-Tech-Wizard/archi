.pragma library

function analyze(view) {
    const nodes = view.shapes
    const ids = new Set(nodes.map(n => n.shapeId))
    const outgoing = new Map(nodes.map(n => [n.shapeId, []]))
    const messages = []
    const label = n => (n.nodeKey || "#" + n.shapeId) + " " + n.text.replace(/\n/g, " ")
    for (const edge of view.arrows) {
        if (!ids.has(edge.fromId) || !ids.has(edge.toId)) {
            messages.push("ERROR: Connection has a missing endpoint")
            continue
        }
        outgoing.get(edge.fromId).push(edge)
    }
    if (ids.size !== nodes.length) messages.push("ERROR: Duplicate node IDs")
    if (!nodes.length) return "Empty view."
    for (const node of nodes) {
        const edges = outgoing.get(node.shapeId)
        if (!node.text.trim()) messages.push("REVIEW: Unnamed node " + label(node))
        if (node.shapeKind === "decision" || node.shapeKind === "diamond") {
            if (edges.length < 2) messages.push("REVIEW: Decision needs branches: " + label(node))
            const labels = edges.map(e => (e.label || "").trim().toLowerCase())
            if (labels.some(text => !text)) messages.push("REVIEW: Unlabeled decision branch: " + label(node))
            if (new Set(labels).size !== labels.length) messages.push("REVIEW: Duplicate branch labels: " + label(node))
        }
    }
    const entry = view.entryId || nodes[0].shapeId
    const reached = new Set()
    const queue = [entry]
    while (queue.length) {
        const id = queue.pop()
        if (reached.has(id)) continue
        reached.add(id)
        for (const edge of outgoing.get(id) || []) queue.push(edge.toId)
    }
    for (const node of nodes)
        if (!reached.has(node.shapeId)) messages.push("REVIEW: Unreachable from entry: " + label(node))
    // Kahn's algorithm detects cycles without recursive stack growth.
    const indegree = new Map(nodes.map(n => [n.shapeId, 0]))
    for (const edges of outgoing.values())
        for (const edge of edges) indegree.set(edge.toId, indegree.get(edge.toId) + 1)
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
    if (removed < nodes.length) messages.push("REVIEW: Cycle present; verify its exit condition and work budget")
    if (!nodes.some(n => outgoing.get(n.shapeId).length === 0)) messages.push("REVIEW: No terminal path")
    return nodes.length + " nodes, " + view.arrows.length + " connections. Entry #" + entry + ".\n\n"
        + (messages.length ? messages.join("\n") : "No structural issues found.")
        + "\n\nSemantic correctness: not established by structural checks."
}
