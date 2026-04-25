# Kiln V1: Permanent Protocol Fee Lock (Critical)

This repository contains a standalone, runnable Proof of Concept (PoC) for a critical logic vulnerability in the Kiln V1 Staking infrastructure.

## 📖 Finding Overview
The Kiln V1 `SanctionsOracle` integration contains a logic flaw that causes the protocol's own fees (Treasury and Operator commissions) to be permanently locked if a validator owner is sanctioned. The `dispatch()` mechanism rollbacks globally upon a sanctions hit, effectively holding the protocol's revenue hostage.

## 📁 Repository Structure
- `src/`: Core Kiln V1 smart contracts.
- `test/KilnTreasuryLock.t.sol`: Unique, atomic Foundry PoC for the Treasury Lock.
- `lib/`: Standalone dependencies (Forge-std, OpenZeppelin).
- `EXPLOIT_PROOF.txt`: Verbose execution trace demonstrating the revert path.
- `CANTINA_SUBMISSION.md`: Formal bug report and impact analysis.

## 🚀 Quick Start (Foundry Required)

### 1. Build
```bash
forge build
```

### 2. Run Exploit
```bash
forge test --match-path test/KilnTreasuryLock.t.sol -vvvv
```

### 3. Verify Trace
Review the `EXPLOIT_PROOF.txt` file to see the internal revert triggered by the `SanctionsOracle` during an Admin withdrawal attempt.

---
**Author**: Omachoko Yakubu
**Target**: Kiln V1 (Cantina Program)
