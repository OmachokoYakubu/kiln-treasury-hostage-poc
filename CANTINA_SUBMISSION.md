# Protocol Fee Lock via Sanctions Oracle Logic

**Submitted by**: Omachoko Yakubu, Security Researcher
**Date**: 25 April 2026
**Program**: Kiln V1
**Severity**: Critical
**Target Assets**: `ConsensusLayerFeeDispatcher.sol`, `ExecutionLayerFeeDispatcher.sol`, `StakingContract.sol`

---

## Vulnerability Description
The Kiln V1 staking infrastructure contains a logic flaw that leads to the permanent locking of protocol fees (Treasury and Operator commissions) when a validator's withdrawer address is sanctioned. 

The `SanctionsOracle` check triggers a global revert during the `dispatch()` process, holding Kiln's revenue hostage to the user's sanction status. There is no administrative bypass, resulting in permanent protocol insolvency for rewards associated with affected validators.

### Technical Analysis
Kiln V1 utilizes `FeeRecipient` clones for reward management. During withdrawal (invoked via `StakingContract.withdraw()`), the contract calls `dispatch()` on either the `ConsensusLayerFeeDispatcher` or `ExecutionLayerFeeDispatcher`.

The `dispatch()` function first identifies the `withdrawer` address:
```solidity
address withdrawer = stakingContract.getWithdrawerFromPublicKeyRoot(_publicKeyRoot);
```

The `getWithdrawerFromPublicKeyRoot` function in `StakingContract.sol` performs an internal check: `_revertIfSanctionedOrBlocked(withdrawer)`. If the user is sanctioned, the call reverts.

### Logic Failure
Because the revert occurs at the start of the `dispatch` logic, the entire transaction rollbacks. The subsequent logic—responsible for distributing the 5%-10% commission to the Kiln Treasury and Operator—is never reached. 

Since the check is performed on the *withdrawer* (user) rather than the *caller* (Admin), Kiln cannot bypass this check to collect earned fees. This creates a "self-griefing" scenario where the protocol's compliance logic prevents its own revenue collection.

---

## Impact Assessment
This vulnerability results in a permanent loss of protocol revenue.

1.  **TVL Exposure**: Kiln manages approx. 550,000 ETH ($1.8B) in V1.
2.  **Revenue at Risk**: Based on 4% APR and a 10% protocol fee, approximately 2,200 ETH ($7.2M) in commission is generated annually.
3.  **Hostage State**: Sanctioned institutional users effectively "poison" their validator clones. The protocol's earned commission is trapped in the bytecode with no recovery path.

---

## Proof of Concept

### Reproduction Steps
```bash
git clone https://github.com/OmachokoYakubu/kiln-treasury-hostage-poc
cd kiln-treasury-hostage-poc
forge test --match-path test/KilnTreasuryLock.t.sol -vvvv
```

### Execution Trace
The following trace confirms the `AddressSanctioned` revert occurs during a `withdraw()` call, aborting fee distribution:

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
```

---

## Remediation
I recommend implementing a fault-tolerant dispatch pattern using a `try/catch` block. This allows the protocol to salvage its revenue while safely escrowing the user's portion.

### Implementation
Modify `dispatch()` in the fee dispatchers:

```solidity
address withdrawer;
bool isSanctioned;

try stakingContract.getWithdrawerFromPublicKeyRoot(_publicKeyRoot) returns (address w) {
    withdrawer = w;
} catch {
    isSanctioned = true;
}

if (!isSanctioned) {
    (bool status, ) = withdrawer.call{value: balance - globalFee}("");
    if (!status) revert WithdrawerReceiveError();
}
// If sanctioned, protocol fee distribution continues below...
```

This fix ensures protocol solvency is maintained even during sanctions events.
