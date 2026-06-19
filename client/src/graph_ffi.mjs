// Minimal dependency-free SVG graph renderer. Draws the server-provided
// subgraph into #graph-canvas. All filtering is server-side; this only paints.
export function render(data) {
  if (typeof document === "undefined") return;
  const canvas = document.getElementById("graph-canvas");
  if (!canvas) return;

  const graph = JSON.parse(data);
  const nodes = graph.nodes ?? [];
  const edges = graph.edges ?? [];

  const width = 640;
  const height = 420;
  const cx = width / 2;
  const cy = height / 2;
  const radius = Math.min(width, height) / 2 - 60;

  const pos = new Map();
  nodes.forEach((node, i) => {
    const angle = (2 * Math.PI * i) / Math.max(nodes.length, 1);
    pos.set(node.id, {
      x: cx + radius * Math.cos(angle),
      y: cy + radius * Math.sin(angle),
      name: node.name,
    });
  });

  const svgns = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(svgns, "svg");
  svg.setAttribute("width", String(width));
  svg.setAttribute("height", String(height));

  for (const edge of edges) {
    const a = pos.get(edge.from);
    const b = pos.get(edge.to);
    if (!a || !b) continue;
    const line = document.createElementNS(svgns, "line");
    line.setAttribute("x1", a.x);
    line.setAttribute("y1", a.y);
    line.setAttribute("x2", b.x);
    line.setAttribute("y2", b.y);
    line.setAttribute("stroke", "#888");
    svg.appendChild(line);

    const label = document.createElementNS(svgns, "text");
    label.setAttribute("x", (a.x + b.x) / 2);
    label.setAttribute("y", (a.y + b.y) / 2);
    label.setAttribute("font-size", "11");
    label.setAttribute("fill", "#555");
    label.textContent = edge.relationship;
    svg.appendChild(label);
  }

  for (const { x, y, name } of pos.values()) {
    const dot = document.createElementNS(svgns, "circle");
    dot.setAttribute("cx", x);
    dot.setAttribute("cy", y);
    dot.setAttribute("r", "8");
    dot.setAttribute("fill", "#2b6cb0");
    svg.appendChild(dot);

    const label = document.createElementNS(svgns, "text");
    label.setAttribute("x", x + 12);
    label.setAttribute("y", y + 4);
    label.setAttribute("font-size", "12");
    label.textContent = name;
    svg.appendChild(label);
  }

  canvas.replaceChildren(svg);
}
