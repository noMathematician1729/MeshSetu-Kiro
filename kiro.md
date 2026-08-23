# Kiro for MeshSetu

MeshSetu is an offline emergency communication system built on a BLE mesh overlay—Flutter on the phone, Node and TypeScript on the server, React for the operator dashboard. That's three platforms, a custom transport protocol, and a lot of moving parts for a hackathon team to ship.

Kiro stepped in as our AI development partner. It sits inside the terminal and understands the entire codebase—from the Protobuf frame definitions and BLE GATT layer to the Postgres-backed control-room API. When we're debugging fragmentation logic or wiring up a new triage endpoint, Kiro reads the relevant files, suggests fixes, writes tests, and catches regressions before they hit the build.

The model selection and reasoning-effort controls to match the task at hand—lightweight models for quick refactors, heavier reasoning for protocol design decisions really came in clutch. Specialized agents let us carve out focused workflows: one tuned for Flutter widget trees, another for infrastructure and deployment scripts. MCP tool integrations tie Kiro into our linters and test runners so verification happens in-loop, not after the fact.

The hackathon's extra two thousand credits give us headroom to iterate aggressively on a project this complex. We track spend with `/usage` and use model credit multipliers to stay within budget while still pulling in the capability we need. The result: a reliable offline emergency network, shipped faster because Kiro handles the mechanical weight of development so we can focus on architecture, user experience, and getting the mesh right.

