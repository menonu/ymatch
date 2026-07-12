# Architecture diagrams (D2 → SVG)

**Only C4 structural views** are authored here. Sequences, state machines, and
simple flowcharts use **Mermaid** inline in the markdown (see section 06, CI
sketch, cross-container data flow).

| File stem | Used in |
|-----------|---------|
| `03-system-context` | [03-context.md](../03-context.md) |
| `03-containers` | [03-context.md](../03-context.md) |
| `05-backend-components` | [05-building-blocks.md](../05-building-blocks.md) |
| `05-frontend-components` | [05-building-blocks.md](../05-building-blocks.md) |
| `07-deployment-oci` | [07-deployment.md](../07-deployment.md) |
| `07-deployment-local` | [07-deployment.md](../07-deployment.md) |

Each diagram is a paired `*.d2` source + committed `*.svg` render
([D2 language](https://d2lang.com/)).

```bash
# Install: https://d2lang.com/tour
export PATH="$HOME/.local/bin:$PATH"

# One file
d2 --layout=dagre 03-system-context.d2 03-system-context.svg

# All C4 diagrams in this directory
for f in *.d2; do d2 --layout=dagre "$f" "${f%.d2}.svg"; done
```

Commit **both** the `.d2` and the regenerated `.svg` when a C4 diagram changes.
