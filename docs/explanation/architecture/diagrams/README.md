# Architecture diagrams (D2 → SVG)

Sources are `*.d2` ([D2 language](https://d2lang.com/)); committed renders are
`*.svg` for reliable display on GitHub.

```bash
# Install: https://d2lang.com/tour
export PATH="$HOME/.local/bin:$PATH"

# One file
d2 --layout=dagre 03-system-context.d2 03-system-context.svg

# All
for f in *.d2; do d2 --layout=dagre "$f" "${f%.d2}.svg"; done
```

Commit **both** the `.d2` and the regenerated `.svg` when diagrams change.
