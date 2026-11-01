// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PleaToken} from "../src/PleaToken.sol";

/// @dev Test fixture only: reproduces a factory deploying and distributing its balance.
contract TokenFactoryFixture {
    function deploy(bytes32 salt) external returns (PleaToken) {
        return new PleaToken{salt: salt}();
    }

    function distribute(PleaToken token, address recipient, uint256 amount) external {
        require(token.transfer(recipient, amount), "transfer failed");
    }
}

contract PleaTokenTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);

    PleaToken private token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new PleaToken();
    }

    function test_MetadataAndEntireSupply() public view {
        assertEq(token.name(), "plea");
        assertEq(token.symbol(), "PLEA");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_ConstructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        PleaToken fresh = new PleaToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_FactoryReceivesSupplyAndDistributesExactAmounts() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        // A distinct transaction origin must not receive the mint.
        vm.prank(ALICE, BOB);
        PleaToken launched = factory.deploy(keccak256("plea launch test"));
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(ALICE), 0);
        assertEq(launched.balanceOf(BOB), 0);
        assertEq(launched.balanceOf(address(this)), 0);

        address distributor = makeAddr("test distributor");
        address pool = makeAddr("test pool");
        uint256 swarm = SUPPLY * 1_000 / 10_000;
        uint256 liquidity = SUPPLY * 7_700 / 10_000;
        uint256 remainder = SUPPLY - swarm - liquidity;
        factory.distribute(launched, distributor, swarm);
        factory.distribute(launched, pool, liquidity);
        factory.distribute(launched, ALICE, remainder);
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), swarm);
        assertEq(launched.balanceOf(pool), liquidity);
        assertEq(launched.balanceOf(ALICE), remainder);

        vm.prank(distributor);
        assertTrue(launched.transfer(BOB, swarm));
        assertEq(launched.balanceOf(BOB), swarm);
        assertEq(launched.balanceOf(distributor), 0);
        // Exact transfers in both directions; full AMM execution belongs to the launch harness.
        vm.prank(pool);
        assertTrue(launched.transfer(BOB, 1 ether));
        vm.prank(BOB);
        assertTrue(launched.transfer(pool, 1 ether));
        assertEq(launched.balanceOf(BOB), swarm);
        assertEq(launched.balanceOf(pool), liquidity);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_TransferEntireBalanceEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, SUPPLY);
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferToContractWithoutReceiverHook() public {
        // The token itself has no receiver hook; ERC-20 transfers still succeed.
        assertTrue(token.transfer(address(token), 1));
        assertEq(token.balanceOf(address(token)), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertTransferOverBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(ALICE, SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_RevertSelfTransferOverBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(ALICE, 1);
    }

    function test_RevertTransferToZeroEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApproveEmitsEventAndReplacesAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 100);
        assertTrue(token.approve(SPENDER, 100));
        assertEq(token.allowance(address(this), SPENDER), 100);
        assertTrue(token.approve(SPENDER, 7));
        assertEq(token.allowance(address(this), SPENDER), 7);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApproveDoesNotRequireABalance() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, SUPPLY));
        assertEq(token.allowance(ALICE, SPENDER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_RevertApprovalToZero() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_TransferFromConsumesFiniteAllowanceAndEmitsTransfer() public {
        assertTrue(token.approve(SPENDER, 100));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 40);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 40));
        assertEq(token.balanceOf(ALICE), 40);
        assertEq(token.balanceOf(address(this)), SUPPLY - 40);
        assertEq(token.allowance(address(this), SPENDER), 60);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, 60));
        assertEq(token.balanceOf(BOB), 60);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteAllowanceIsNotDecreased() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.startPrank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY / 2));
        assertTrue(token.transferFrom(address(this), BOB, SUPPLY / 2));
        vm.stopPrank();
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY / 2);
        assertEq(token.balanceOf(BOB), SUPPLY / 2);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferFromStillConsumesAllowance() public {
        assertTrue(token.approve(SPENDER, 10));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), 10));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_ZeroTransferFromNeedsNoPositiveAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_RevokeApprovalPreventsFurtherSpending() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 0);
        assertTrue(token.approve(SPENDER, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_RevertTransferFromWithoutAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_RevertTransferFromByDifferentSpender() public {
        assertTrue(token.approve(SPENDER, 100));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_DeployerCannotSpendHolderBalanceWithoutApproval() public {
        assertTrue(token.transfer(ALICE, 100));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.balanceOf(ALICE), 100);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_RevertOverAllowancePreservesState() public {
        assertTrue(token.approve(SPENDER, 10));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 10, 11));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 11);
        assertEq(token.allowance(address(this), SPENDER), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_RevertOverBalanceRollsBackAllowance() public {
        assertTrue(token.transfer(ALICE, 10));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 20));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 10, 11));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 11);
        assertEq(token.allowance(ALICE, SPENDER), 20);
        assertEq(token.balanceOf(ALICE), 10);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertTransferFromToZeroRollsBackAllowance() public {
        assertTrue(token.approve(SPENDER, 10));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 10);
        assertEq(token.allowance(address(this), SPENDER), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertZeroSourceEvenForZeroTransferFrom() public {
        // ERC-20 checks the allowance owner before it reaches the transfer's sender check.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(0), BOB, 0);
    }

    function test_NoMintBurnPauseSeizureOrUpgradeEntryPoints() public {
        assertTrue(token.transfer(ALICE, 100));
        bytes[] memory calls = new bytes[](14);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", BOB, 1);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[4] = abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1);
        calls[5] = abi.encodeWithSignature("pause()");
        calls[6] = abi.encodeWithSignature("blacklist(address)", ALICE);
        calls[7] = abi.encodeWithSignature("freeze(address)", ALICE);
        calls[8] = abi.encodeWithSignature("seize(address)", ALICE);
        calls[9] = abi.encodeWithSignature("initialize(address)", BOB);
        calls[10] = abi.encodeWithSignature("transferOwnership(address)", BOB);
        calls[11] = abi.encodeWithSignature("upgradeTo(address)", BOB);
        calls[12] = abi.encodeWithSignature("setMinter(address)", BOB);
        calls[13] = abi.encodeWithSignature("owner()");

        for (uint256 i; i < calls.length; ++i) {
            (bool fromDeployer,) = address(token).call(calls[i]);
            assertFalse(fromDeployer);
            vm.prank(BOB);
            (bool fromStranger,) = address(token).call(calls[i]);
            assertFalse(fromStranger);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(ALICE), 100);
            assertEq(token.balanceOf(BOB), 0);
            assertEq(token.balanceOf(address(this)), SUPPLY - 100);
        }
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100));
        assertEq(token.balanceOf(BOB), 100);
    }

    function test_RejectsEtherAndUnknownCalls() public {
        vm.deal(address(this), 1 ether);
        (bool paid,) = address(token).call{value: 1 ether}("");
        assertFalse(paid);
        (bool unknown,) = address(token).call(hex"ffffffff");
        assertFalse(unknown);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        if (recipient == address(this)) {
            assertEq(token.balanceOf(address(this)), SUPPLY);
        } else {
            assertEq(token.balanceOf(address(this)), SUPPLY - amount);
            assertEq(token.balanceOf(recipient), amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovedSpending(uint256 approval, uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        approval = bound(approval, amount, type(uint256).max);
        assertTrue(token.approve(SPENDER, approval));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount));
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.allowance(address(this), SPENDER), approval == type(uint256).max ? approval : approval - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RevertTransferAboveBalance(uint256 balance, uint256 excess) public {
        balance = bound(balance, 0, SUPPLY);
        excess = bound(excess, 1, type(uint256).max - balance);
        assertTrue(token.transfer(ALICE, balance));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, balance + excess)
        );
        vm.prank(ALICE);
        token.transfer(BOB, balance + excess);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RevertSpendingAboveAllowance(uint256 approval, uint256 excess) public {
        approval = bound(approval, 0, SUPPLY - 1);
        excess = bound(excess, 1, SUPPLY - approval);
        assertTrue(token.approve(SPENDER, approval));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, approval, approval + excess
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, approval + excess);
        assertEq(token.allowance(address(this), SPENDER), approval);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
