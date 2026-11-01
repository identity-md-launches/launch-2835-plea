// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PleaToken} from "../src/PleaToken.sol";

/// @dev Restricts transfers to a closed actor set so every token remains accounted for.
contract PleaTokenHandler is Test {
    PleaToken public immutable token;
    address[4] public actors = [address(0xA11CE), address(0xB0B), address(0xCA401), address(0xDA7E)];

    constructor(PleaToken token_) {
        token = token_;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 allowance = token.allowance(from, spender);
        uint256 balance = token.balanceOf(from);
        amount = bound(amount, 0, allowance < balance ? allowance : balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
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
        vm.prank(spender);
        (bool ok,) = address(token).call(abi.encodeCall(token.transferFrom, (owner, spender, 1)));
        assertFalse(ok);
        assertEq(token.allowance(owner, spender), 0);
        assertEq(token.balanceOf(owner), ownerBalance);
        assertEq(token.balanceOf(spender), spenderBalance);
    }
}

contract PleaTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    PleaToken private token;
    PleaTokenHandler private handler;

    function setUp() public {
        token = new PleaToken();
        handler = new PleaTokenHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.overspend.selector;
        selectors[4] = handler.revokeAndTrySpending.selector;
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
}
