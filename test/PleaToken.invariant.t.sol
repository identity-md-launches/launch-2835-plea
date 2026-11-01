// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PleaToken} from "../src/PleaToken.sol";

/// @dev Restricts transfers to a closed actor set so every token remains accounted for.
contract PleaTokenHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    PleaToken public immutable token;
    address[4] public actors = [address(0xA11CE), address(0xB0B), address(0xCA401), address(0xDA7E)];

    // Independent transaction ledger: never copy a balance or allowance from the token.
    mapping(address => uint256) public received;
    mapping(address => uint256) public sent;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(PleaToken token_) {
        token = token_;
        received[actors[0]] = SUPPLY;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, received[from] - sent[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordTransfer(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        assertEq(token.allowance(owner, spender), amount);
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 allowance = expectedAllowance[from][spender];
        uint256 balance = received[from] - sent[from];
        amount = bound(amount, 0, allowance < balance ? allowance : balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        _recordTransfer(from, to, amount);
        if (allowance != type(uint256).max) expectedAllowance[from][spender] -= amount;
        assertEq(token.allowance(from, spender), allowance == type(uint256).max ? allowance : allowance - amount);
    }

    function overspend(uint256 fromSeed, uint256 spenderSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[(fromSeed % actors.length + 1) % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 fromBalance = token.balanceOf(from);
        uint256 toBalance = token.balanceOf(to);
        uint256 allowance = token.allowance(from, spender);
        // Deliberately fail regardless of the current approval; verify complete rollback.
        vm.prank(spender);
        (bool ok,) = address(token).call(abi.encodeCall(token.transferFrom, (from, to, fromBalance + 1)));
        assertFalse(ok);
        assertEq(token.balanceOf(from), fromBalance);
        assertEq(token.balanceOf(to), toBalance);
        assertEq(token.allowance(from, spender), allowance);
    }

    function revokeAndTrySpending(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 ownerBalance = token.balanceOf(owner);
        uint256 spenderBalance = token.balanceOf(spender);
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;
        vm.prank(spender);
        (bool ok,) = address(token).call(abi.encodeCall(token.transferFrom, (owner, spender, 1)));
        assertFalse(ok);
        assertEq(token.allowance(owner, spender), 0);
        assertEq(token.balanceOf(owner), ownerBalance);
        assertEq(token.balanceOf(spender), spenderBalance);
    }

    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 boundarySeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256[5] memory edges = [uint256(0), 1, SUPPLY, type(uint256).max - 1, type(uint256).max];
        uint256 amount = edges[boundarySeed % edges.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferBoundary(uint256 fromSeed, uint256 toSeed, uint256 boundarySeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = received[from] - sent[from];
        // Empty accounts still exercise zero transfers; funded ones exercise dust and draining.
        uint256 amount = boundarySeed % 3 == 0 ? 0 : boundarySeed % 3 == 1 && balance > 0 ? 1 : balance;
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordTransfer(from, to, amount);
    }

    function roundTrip(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, received[from] - sent[from]);
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordTransfer(from, to, amount);
        vm.prank(to);
        assertTrue(token.transfer(from, amount));
        _recordTransfer(to, from, amount);
        assertEq(token.balanceOf(from), fromBefore, "round trip changed sender balance");
        assertEq(token.balanceOf(to), toBefore, "round trip changed receiver balance");
    }

    function overdrawWithApproval(uint256 fromSeed, uint256 spenderSeed, bool infinite) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[(fromSeed % actors.length + 1) % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 balance = received[from] - sent[from];
        uint256 amount = balance + 1;
        uint256 approval = infinite ? type(uint256).max : amount;
        vm.prank(from);
        assertTrue(token.approve(spender, approval));
        expectedAllowance[from][spender] = approval;

        // Enough allowance ensures the failure reaches the balance check and rolls back spending.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(spender);
        token.transferFrom(from, to, amount);
    }

    function rejectZeroRecipient(uint256 fromSeed, uint256 spenderSeed, uint256 amount, bool delegated) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, received[from] - sent[from]);
        if (delegated) {
            vm.prank(from);
            assertTrue(token.approve(spender, amount));
            expectedAllowance[from][spender] = amount;
        }
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(delegated ? spender : from);
        if (delegated) token.transferFrom(from, address(0), amount);
        else token.transfer(address(0), amount);
    }

    function _recordTransfer(address from, address to, uint256 amount) private {
        sent[from] += amount;
        received[to] += amount;
    }
}

/// @dev Each property runs after every handler call, including deliberately rejected calls.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract PleaTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    PleaToken private token;
    PleaTokenHandler private handler;

    function setUp() public {
        token = new PleaToken();
        handler = new PleaTokenHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.overspend.selector;
        selectors[4] = handler.revokeAndTrySpending.selector;
        selectors[5] = handler.approveBoundary.selector;
        selectors[6] = handler.transferBoundary.selector;
        selectors[7] = handler.roundTrip.selector;
        selectors[8] = handler.overdrawWithApproval.selector;
        selectors[9] = handler.rejectZeroRecipient.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_TotalSupplyIsAlwaysOneBillionTokens() public view {
        assertEq(token.totalSupply(), SUPPLY);
    }

    function invariant_AllBalancesConserveTheEntireSupply() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_EachBalanceMatchesItsTransactionHistory() public view {
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            assertLe(handler.sent(actor), handler.received(actor), "actor spent more than received");
            assertEq(token.balanceOf(actor), handler.received(actor) - handler.sent(actor), "incorrect actor balance");
        }
    }

    function invariant_AllAllowancesMatchTheirIndependentBudgets() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender), handler.expectedAllowance(owner, spender), "incorrect allowance"
                );
            }
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(address(0), owner), 0);
        }
    }
}
