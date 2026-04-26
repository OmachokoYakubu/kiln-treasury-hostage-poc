# Kiln V1: Protocol Fee Lock PoC

This repository contains a standalone Proof of Concept (PoC) for a critical logic vulnerability in the Kiln V1 Staking infrastructure.

## Vulnerability Overview
The Kiln V1 `SanctionsOracle` integration contains a logic flaw that causes protocol fees (Treasury and Operator commissions) to be permanently locked if a validator owner is sanctioned. The `dispatch()` mechanism reverts globally upon a sanctions hit, preventing the protocol from collecting its earned revenue.

## Repository Structure
- `src/`: Target Kiln V1 smart contracts.
- `test/KilnTreasuryLock.t.sol`: Atomic Foundry PoC.
- `lib/`: Bundled dependencies (Forge-std, OpenZeppelin).
- `EXPLOIT_PROOF.txt`: Execution trace demonstrating the revert path.
- `CANTINA_SUBMISSION.md`: Formal bug report.

## Reproduction Instructions

### 1. Clone and Setup
```bash
git clone https://github.com/OmachokoYakubu/kiln-treasury-hostage-poc
cd kiln-treasury-hostage-poc
forge build
```

### 2. Run Test
```bash
forge test --match-path test/KilnTreasuryLock.t.sol -vvvv
```

### 3. Verification
Review the `EXPLOIT_PROOF.txt` file to observe the internal revert triggered by the `SanctionsOracle` during a withdrawal attempt.

---
**Author**: Omachoko Yakubu
**Target**: Kiln V1 (Cantina Program)
