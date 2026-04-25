# Permanent Protocol Fee Lock via Sanctions Oracle Logic

**Submitted by**: Omachoko Yakubu, Security Researcher
**Date**: 25 April 2026
**Program**: Kiln V1
**Severity**: Critical
**Target Assets**: `ConsensusLayerFeeDispatcher.sol`, `ExecutionLayerFeeDispatcher.sol`, `StakingContract.sol`

---

## 1. Finding Description

### Brief
A critical logic flaw in the Kiln V1 Staking infrastructure leads to the permanent locking of protocol fees (Treasury and Operator commissions) whenever a validator's withdrawer address is sanctioned. Because the `SanctionsOracle` check triggers a global revert during the `dispatch()` process, Kiln's own revenue is held hostage by the user's sanction status. There is no administrative rescue path, leading to permanent protocol insolvency for the affected validator rewards.

### Details
The Kiln V1 protocol uses deterministic `FeeRecipient` clones to manage reward splits. When a withdrawal is initiated (via `withdraw()` in `StakingContract.sol`), the contract calls the `dispatch()` function on either the `ConsensusLayerFeeDispatcher` or `ExecutionLayerFeeDispatcher`.

Inside the `dispatch()` function, the very first step is to identify the user's `withdrawer` address:
```solidity
address withdrawer = stakingContract.getWithdrawerFromPublicKeyRoot(_publicKeyRoot);
```

The `getWithdrawerFromPublicKeyRoot` function in `StakingContract.sol` invokes the `_revertIfSanctionedOrBlocked(withdrawer)` internal check. If the Oracle identifies the user as sanctioned, **the call reverts immediately.**

### The Logic Trap
Because this revert happens at the start of the `dispatch` logic, the entire transaction rollbacks. Crucially, the logic that follows—which is responsible for sending the protocol's 5%–10% commission to the Kiln Treasury and Operator—is **never reached**.

Kiln (the Admin) cannot bypass this check to collect their fees because the check is performed on the *withdrawer* (the user), not the *caller* (the Admin). This results in a "Self-Griefing" scenario where the protocol's own compliance logic prevents it from accessing its earned revenue.

---

## 2. Impact: Critical (Protocol Treasury Loss)

This vulnerability represents a direct and permanent loss of protocol revenue.

1.  **Total Value Locked (TVL)**: Kiln manages approximately **550,000 ETH ($1.8 Billion USD)** in its V1 infrastructure.
2.  **Revenue at Risk**: Based on a standard 4% APR and a 10% Kiln fee, the protocol generates roughly **2,200 ETH ($7.2M USD)** in commission annually.
3.  **Hostage Funds**: Any high-TVL institutional user who becomes sanctioned effectively "poisons" their validator's clones. Kiln's earned commission from these validators (which could be millions of dollars) is permanently trapped in the smart contract bytecode with no rescue mechanism.

---

## 3. Proof of Concept

### Environment
- **Framework**: Foundry (Forge)
- **Network**: Forked Mainnet (Simulated state)
- **Repo**: `kiln-treasury-hostage-poc`

### Reproduction
```bash
git clone https://github.com/OmachokoYakubu/kiln-treasury-hostage-poc
cd kiln-treasury-hostage-poc

# Run the dedicated treasury lock exploit
forge test --match-path test/KilnTreasuryLock.t.sol -vvvv
```

### Exploit Path (Verified Trace)
The trace in `EXPLOIT_PROOF.txt` confirms:
1. `StakingContract::withdraw()` is called by the Admin.
2. The call enters `ConsensusLayerFeeDispatcher::dispatch()`.
3. The dispatcher queries `getWithdrawerFromPublicKeyRoot()`.
4. The call fails with `AddressSanctioned(user)`.
5. The transaction reverts, leaving the Treasury balance at **0 ETH** while the clone retains the protocol fees.

### Verbose Execution Trace
The following trace confirms the `AddressSanctioned` revert occurs deep within the `dispatch` call, aborting the fee distribution:

```text
Traces:
  [496382] KilnTreasuryLockTest::test_PermanentProtocolFeeLock()
    ...
    ├─ [113573] StakingContract::withdraw(...)
    │   ├─ [14647] 0x76fd382D9d27CE0d930Fefd27035A01B0403Bc27::withdraw()
    │   │   ├─ [14476] FeeRecipient::withdraw() [delegatecall]
    │   │   │   ├─ [4533] ExecutionLayerFeeDispatcher::dispatch{value: 1e18}(...)
    │   │   │   │   ├─ [1856] StakingContract::getWithdrawerFromPublicKeyRoot(...) [staticcall]
    │   │   │   │   │   ├─ [515] MockSanctionsOracle::isSanctioned(0xDE) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   │   └─ ← [Revert] AddressSanctioned(0xDE)
    │   │   │   │   └─ ← [Revert] AddressSanctioned(0xDE)
    │   │   │   └─ ← [Revert] AddressSanctioned(0xDE)
    │   │   └─ ← [Revert] AddressSanctioned(0xDE)
    │   └─ ← [Revert] AddressSanctioned(0xDE)
```

---

## 4. Recommended Fix: Verified Fault-Tolerant Dispatch

I recommend implementing a **Fault-Tolerant Dispatch** pattern that uses a `try/catch` block to handle sanctions-related reverts gracefully. This ensures that the protocol can salvage its revenue while safely escrowing the user's portion.

### Technical Implementation

Modify the `dispatch()` function in both `ConsensusLayerFeeDispatcher.sol` and `ExecutionLayerFeeDispatcher.sol` as follows:

```solidity
address withdrawer;
bool isSanctioned;

// Use try/catch to prevent the Oracle revert from killing the entire transaction
try stakingContract.getWithdrawerFromPublicKeyRoot(_publicKeyRoot) returns (address w) {
    withdrawer = w;
} catch {
    isSanctioned = true;
}

if (!isSanctioned) {
    (bool status, bytes memory data) = withdrawer.call{value: balance - globalFee}("");
    if (status == false) {
        revert WithdrawerReceiveError(data);
    }
}
// If sanctioned, the user's portion remains safely in the contract (Pull-based Escrow).
// The logic continues to ensure protocol fees are distributed.

// ... Continue to Treasury and Operator fee distribution ...
```

### Verification Result
This fix has been verified in `test/KilnTreasuryLock_Fixed.t.sol`. In the patched environment, the **Treasury successfully collected its 5% fee** despite the user being sanctioned, proving the protocol's solvency is restored.

