// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PleaToken} from "src/PleaToken.sol";

/// @notice Boundary and sequence regressions complementing the deployment/ERC-20 tests.
/// forge-config: default.fuzz.runs = 1024
contract PleaTokenEdgesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    address private constant OTHER_SPENDER = address(0x5EED2);

    PleaToken private token;

    function setUp() public {
        token = new PleaToken();
    }

    function test_OneMinorUnitCanMoveAndReturn() public {
        assertTrue(token.transfer(ALICE, 1));
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 1));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 1);
        vm.prank(BOB);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumFiniteAllowanceIsSpentUnlikeInfiniteAllowance() public {
        uint256 finite = type(uint256).max - 1;
        assertTrue(token.approve(SPENDER, finite));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), finite - 1);

        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);

        // Replacing the sentinel with a finite value restores finite accounting.
        assertTrue(token.approve(SPENDER, finite));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), finite - 1);
        assertEq(token.balanceOf(ALICE), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromByOwnerStillRequiresSelfApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);

        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_TransactionOriginDoesNotAuthorizeSpending() public {
        assertTrue(token.approve(SPENDER, 10));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, OTHER_SPENDER, 0, 1));
        vm.prank(OTHER_SPENDER, SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 10);
        assertEq(token.allowance(address(this), OTHER_SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_ApprovalForOneOwnerCannotSpendAnotherOwnersBalance() public {
        assertTrue(token.transfer(ALICE, 10));
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 10);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_SpendingIntoSpendersOwnAccountStillConsumesBudget() public {
        assertTrue(token.approve(SPENDER, 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), SPENDER, 1));
        assertEq(token.balanceOf(SPENDER), 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), SPENDER, 1);
        assertEq(token.balanceOf(SPENDER), 1);
    }

    function test_SplitSpendingCannotExceedOriginalApproval() public {
        assertTrue(token.approve(SPENDER, 10));
        vm.startPrank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 4));
        assertTrue(token.transferFrom(address(this), BOB, 6));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        vm.stopPrank();
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 4);
        assertEq(token.balanceOf(BOB), 6);
        assertEq(token.balanceOf(address(this)), SUPPLY - 10);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteApprovalSurvivesFailuresAndCanBeUsedAfterwards() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.startPrank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(address(this), address(0), 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transferFrom(address(this), ALICE, type(uint256).max);
        vm.stopPrank();
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroRecipientIsRejectedForZeroDelegatedTransfer() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, address(0), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroSpenderIsRejectedForZeroAndMaximumApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), type(uint256).max);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_MaximumTransferFailsWithBalanceErrorAndPreservesApprovals() public {
        assertTrue(token.approve(SPENDER, 1));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(ALICE, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(address(this), SPENDER), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_FailedSpendCanRetryAfterReceivingMissingUnit(uint256 balance, uint256 approval) public {
        balance = bound(balance, 0, SUPPLY - 1);
        uint256 amount = balance + 1;
        approval = bound(approval, amount, type(uint256).max);
        assertTrue(token.transfer(ALICE, balance));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, approval));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.allowance(ALICE, SPENDER), approval);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);

        assertTrue(token.transfer(ALICE, 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, amount));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(ALICE, SPENDER), approval == type(uint256).max ? approval : approval - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ReplacedApprovalIsTheEntireNewBudget(uint256 previous, uint256 replacement) public {
        replacement = bound(replacement, 0, SUPPLY - 1);
        assertTrue(token.approve(SPENDER, previous));
        assertTrue(token.approve(SPENDER, replacement));
        assertEq(token.allowance(address(this), SPENDER), replacement);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, replacement, replacement + 1
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, replacement + 1);
        assertEq(token.allowance(address(this), SPENDER), replacement);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, replacement));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), replacement);
        assertEq(token.balanceOf(address(this)), SUPPLY - replacement);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplittingATransferHasTheSameResult(uint256 total, uint256 first) public {
        total = bound(total, 0, SUPPLY);
        first = bound(first, 0, total);
        PleaToken splitToken = new PleaToken();
        assertTrue(token.transfer(ALICE, total));
        assertTrue(splitToken.transfer(ALICE, first));
        assertTrue(splitToken.transfer(ALICE, total - first));
        assertEq(token.balanceOf(ALICE), total);
        assertEq(splitToken.balanceOf(ALICE), token.balanceOf(ALICE));
        assertEq(splitToken.balanceOf(address(this)), token.balanceOf(address(this)));
        assertEq(token.balanceOf(address(this)), SUPPLY - total);
        assertEq(splitToken.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DirectTransferDoesNotConsumeEitherSpendersAllowance(
        uint256 amount,
        uint256 firstApproval,
        uint256 secondApproval
    ) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.approve(SPENDER, firstApproval));
        assertTrue(token.approve(OTHER_SPENDER, secondApproval));
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.allowance(address(this), SPENDER), firstApproval);
        assertEq(token.allowance(address(this), OTHER_SPENDER), secondApproval);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
