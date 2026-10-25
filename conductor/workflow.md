# Development Workflow: goose-sql-p2p

This document defines the development workflow and quality gates for the `goose-sql-p2p` project.

## 1. Track-Based Development Cycle
Each feature, component, or milestone is executed as a discrete **Track**:
1. **Specification (`spec.md`)**: Define requirements, schema, wire protocol formats, and interface signatures.
2. **Implementation Plan (`plan.md`)**: Break down work into atomic, testable phases with discrete checkpoints.
3. **TDD / Red-Green-Refactor**: Write unit/integration tests first, implement Goose/C functionality, and verify tests pass.
4. **Interoperability Verification**: Validate against reference Go `sqlite-p2p` nodes before marking the track complete.

## 2. Quality Gates
- Code compiles cleanly with zero C compiler warnings.
- SQLite memory allocations and statement lifecycles are leak-free.
- Configuration loading passes all schema checks against `config.example.json` and real node configs.
- End-to-end P2P replication tests demonstrate 100% causal consistency and data equality across nodes.
