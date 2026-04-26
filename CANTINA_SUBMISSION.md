# Protocol Fee Lock via Sanctions Oracle Logic

**Submitted by**: Omachoko Yakubu, Security Researcher
**Date**: 25 April 2026
**Program**: Kiln V1
**Severity**: Critical
**Target Assets**: `ConsensusLayerFeeDispatcher.sol`, `ExecutionLayerFeeDispatcher.sol`, `StakingContract.sol`

---

## Summary
A critical logic flaw in Kiln V1 causes protocol revenue (Treasury and Operator fees) to be permanently locked if a validator owner is sanctioned.

## Finding Description
The Kiln V1 staking infrastructure uses `FeeRecipient` clones to manage reward splits. During the withdrawal process (invoked via `StakingContract.withdraw()`), the contract calls `dispatch()` on a fee dispatcher. 

The `dispatch()` function attempts to retrieve the `withdrawer` address using `stakingContract.getWithdrawerFromPublicKeyRoot(_publicKeyRoot)`. However, `getWithdrawerFromPublicKeyRoot` contains an internal call to `_revertIfSanctionedOrBlocked(withdrawer)`. 

If the user associated with that validator is sanctioned, the function reverts the entire transaction. This breaks the security guarantee of protocol revenue isolation; because the revert occurs at the start of the `dispatch` logic, the code responsible for distributing the 5%-10% Kiln commission to the Treasury and Operator is never reached. Since there is no administrative bypass, Kiln is blocked from collecting its own earned fees whenever a user is sanctioned.

## Impact Explanation
I have assessed this as **Critical** because it leads to a permanent loss of protocol revenue with no recovery path. Kiln manages approximately 550,000 ETH ($1.8B) in its V1 infrastructure, generating roughly $7.2M USD in commission annually. Any high-TVL institutional user who becomes sanctioned effectively "poisons" the validator's clones, holding the protocol's earned commission hostage indefinitely.

## Likelihood Explanation
The likelihood is **High** for an institutional-grade protocol like Kiln. In the current regulatory environment (OFAC, etc.), sanctions are a recurring and material risk. The vulnerability specifically triggers during the very events (sanctions) the protocol attempts to comply with, making it a systemic logic failure rather than an edge case.

## Proof of Concept
I have provided a standalone Foundry repository to reproduce this issue.

**Reproduction Steps**:
```bash
git clone https://github.com/OmachokoYakubu/kiln-treasury-hostage-poc
cd kiln-treasury-hostage-poc
forge test --match-path test/KilnTreasuryLock.t.sol -vvvv
```

**Execution Trace**:
The following trace confirms the `AddressSanctioned` revert occurs during an Admin-initiated `withdraw()` call, aborting the fee distribution:

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

## Recommendation
I recommend implementing a fault-tolerant dispatch pattern using a `try/catch` block to handle sanctions-related reverts gracefully. This ensures the protocol can salvage its revenue while safely escrowing the user's portion.

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
```

---

**Report Ends**
