// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.10;

import "forge-std/Test.sol";
import "../src/StakingContract.sol";
import "../src/ConsensusLayerFeeDispatcher.sol";
import "../src/ExecutionLayerFeeDispatcher.sol";
import "../src/FeeRecipient.sol";
import "../src/interfaces/ISanctionsOracle.sol";

contract MockSanctionsOracle is ISanctionsOracle {
    mapping(address => bool) public sanctioned;
    function setSanctioned(address _addr, bool _val) external { sanctioned[_addr] = _val; }
    function isSanctioned(address _addr) external view returns (bool) { return sanctioned[_addr]; }
}

contract MockDepositContract {
    function deposit(bytes calldata, bytes calldata, bytes calldata, bytes32) external payable {}
}

contract KilnTreasuryLockTest is Test {
    StakingContract staking;
    ConsensusLayerFeeDispatcher clDispatcher;
    ExecutionLayerFeeDispatcher elDispatcher;
    FeeRecipient feeRecipientImpl;
    MockSanctionsOracle oracle;
    
    address admin = address(uint160(uint256(keccak256("admin"))));
    address user = address(0xDE);
    address treasury = address(0x77);
    
    function setUp() public {
        staking = new StakingContract();
        clDispatcher = new ConsensusLayerFeeDispatcher(0);
        elDispatcher = new ExecutionLayerFeeDispatcher(0);
        feeRecipientImpl = new FeeRecipient();
        oracle = new MockSanctionsOracle();
        MockDepositContract depositContract = new MockDepositContract();
        
        vm.startPrank(admin);
        staking.initialize_1(
            admin, treasury, address(depositContract), 
            address(elDispatcher), address(clDispatcher), address(feeRecipientImpl), 
            500, 1000, 1000, 2000
        );
        staking.setSanctionsOracle(address(oracle));
        clDispatcher.initCLD(address(staking));
        elDispatcher.initELD(address(staking));
        staking.addOperator(admin, admin);
        vm.stopPrank();
    }

    function test_PermanentProtocolFeeLock() public {
        bytes memory publicKey = new bytes(48);
        publicKey[0] = 0x01;
        
        vm.startPrank(admin);
        staking.addValidators(0, 1, publicKey, new bytes(96));
        staking.setOperatorLimit(0, 1, block.number);
        vm.stopPrank();
        
        vm.deal(user, 32 ether);
        vm.prank(user);
        staking.deposit{value: 32 ether}();
        
        address clClone = staking.getCLFeeRecipient(publicKey);
        address elClone = staking.getELFeeRecipient(publicKey);
        vm.deal(clClone, 1 ether);
        vm.deal(elClone, 1 ether);
        
        // Sanction the user
        oracle.setSanctioned(user, true);
        
        // Protocol withdrawal reverts due to sanctioned withdrawer address
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature("AddressSanctioned(address)", user)); 
        staking.withdraw(publicKey);
        
        assertEq(address(treasury).balance, 0, "Treasury should have received 0 fees");
    }
}
