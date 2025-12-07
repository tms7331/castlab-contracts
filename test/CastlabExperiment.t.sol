// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/CastlabExperiment.sol";
import "./TestToken.sol";

contract CastlabExperimentNewTest is Test {
    CastlabExperiment public funding;
    TestToken public token;
    address public admin = address(0x1);
    address public admin2 = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    address public user3 = address(0x5);

    uint256 constant INITIAL_BALANCE = 10000e6; // 10,000 USDC (6 decimals)

    function setUp() public {
        address tokenAdmin1 = 0x4611F6d137d1baf545378dD02C1b16eb63cbE755;

        vm.startPrank(tokenAdmin1);

        // Deploy token and funding contracts
        token = new TestToken();
        funding = new CastlabExperiment(admin, admin2, address(token));

        // Transfer tokens to test users
        token.transfer(user1, INITIAL_BALANCE);
        token.transfer(user2, INITIAL_BALANCE);
        token.transfer(user3, INITIAL_BALANCE);
        token.transfer(admin, INITIAL_BALANCE);

        vm.stopPrank();
    }

    function testThreeUsersDepositOneUndepositsAdminReturns() public {
        // Admin creates experiment with minCost = 100 USDC, maxCost = 500 USDC
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100e6, // minCost: 100 USDC
            500e6 // maxCost: 500 USDC
        );

        // User1 approves and deposits 50 USDC
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userDeposit(experimentId, 50e6);

        // User2 approves and deposits 75 USDC
        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userDeposit(experimentId, 75e6);

        // User3 approves and deposits 100 USDC
        vm.prank(user3);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user3);
        funding.userDeposit(experimentId, 100e6);

        // Check total deposited is 225 USDC
        ICastLabExperiment.Experiment memory exp = funding.getExperimentInfo(experimentId);
        assertEq(exp.totalDeposited, 225e6);

        // User2 undeposits their 75 USDC
        uint256 user2BalanceBefore = token.balanceOf(user2);
        vm.prank(user2);
        funding.userUndeposit(experimentId);
        assertEq(token.balanceOf(user2), user2BalanceBefore + 75e6);
        (uint256 depositAmount2, , ) = funding.getUserPosition(experimentId, user2);
        assertEq(depositAmount2, 0);

        // Check total deposited is now 150 USDC
        exp = funding.getExperimentInfo(experimentId);
        assertEq(exp.totalDeposited, 150e6);

        // Admin returns remaining funds to user1 and user3
        address[] memory depositors = new address[](2);
        depositors[0] = user1;
        depositors[1] = user3;

        uint256 user1BalanceBefore = token.balanceOf(user1);
        uint256 user3BalanceBefore = token.balanceOf(user3);

        vm.prank(admin);
        funding.adminRefund(experimentId, depositors);
        vm.prank(admin);
        funding.adminClose(experimentId);

        // Verify users got their funds back
        assertEq(token.balanceOf(user1), user1BalanceBefore + 50e6);
        assertEq(token.balanceOf(user3), user3BalanceBefore + 100e6);

        // Verify experiment is closed and deposits are cleared
        exp = funding.getExperimentInfo(experimentId);
        assertEq(exp.totalDeposited, 0);
        assertFalse(exp.open);
        (uint256 depositAmount1, , ) = funding.getUserPosition(experimentId, user1);
        assertEq(depositAmount1, 0);
        (uint256 depositAmount3, , ) = funding.getUserPosition(experimentId, user3);
        assertEq(depositAmount3, 0);
    }

    function testDepositUndepositRedepositPastMinCostAdminCloses() public {
        // Admin creates experiment with minCost = 100 USDC, maxCost = 500 USDC
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100e6, // minCost: 100 USDC
            500e6 // maxCost: 500 USDC
        );

        // User1 approves funding contract
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);

        // User1 deposits 60 USDC
        vm.prank(user1);
        funding.userDeposit(experimentId, 60e6);
        (uint256 depositAmount1, , ) = funding.getUserPosition(experimentId, user1);
        assertEq(depositAmount1, 60e6);

        // User1 undeposits the 60 USDC
        vm.prank(user1);
        funding.userUndeposit(experimentId);
        (uint256 depositAmount2, , ) = funding.getUserPosition(experimentId, user1);
        assertEq(depositAmount2, 0);

        // User1 redeposits 150 USDC (past minCost)
        vm.prank(user1);
        funding.userDeposit(experimentId, 150e6);
        (uint256 depositAmount3, , ) = funding.getUserPosition(experimentId, user1);
        assertEq(depositAmount3, 150e6);

        // Verify total is past minCost
        ICastLabExperiment.Experiment memory exp = funding.getExperimentInfo(experimentId);
        assertEq(exp.totalDeposited, 150e6);
        assertTrue(exp.totalDeposited >= exp.costMin);

        // Admin withdraws the funds (closes the experiment)
        uint256 adminBalanceBefore = token.balanceOf(admin);
        vm.prank(admin);
        funding.adminWithdraw(experimentId);
        assertEq(token.balanceOf(admin), adminBalanceBefore + 150e6);

        // Verify experiment is closed
        exp = funding.getExperimentInfo(experimentId);
        assertEq(exp.totalDeposited, 0);
        assertFalse(exp.open);

        // User1 tries to undeposit but should fail because experiment is closed
        vm.expectRevert(ICastLabExperiment.ExperimentClosed.selector);
        vm.prank(user1);
        funding.userUndeposit(experimentId);

        // User1 also can't deposit anymore
        vm.expectRevert(ICastLabExperiment.ExperimentClosed.selector);
        vm.prank(user1);
        funding.userDeposit(experimentId, 10e6);
    }

    function testMinimumDepositRequirement() public {
        // Admin creates experiment
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100e6, // minCost: 100 USDC
            500e6 // maxCost: 500 USDC
        );

        // User1 approves funding contract
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);

        // Try to deposit 0.5 USDC - should fail
        vm.expectRevert(ICastLabExperiment.DepositBelowMinimum.selector);
        vm.prank(user1);
        funding.userDeposit(experimentId, 0.5e6);

        // Deposit 1 USDC - should succeed
        vm.prank(user1);
        funding.userDeposit(experimentId, 1e6);
        (uint256 depositAmount, , ) = funding.getUserPosition(experimentId, user1);
        assertEq(depositAmount, 1e6);
    }

    function testCannotExceedMaxCost() public {
        // Admin creates experiment
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100e6, // minCost: 100 USDC
            200e6 // maxCost: 200 USDC
        );

        // User1 approves and deposits 150 USDC
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userDeposit(experimentId, 150e6);

        // User2 tries to deposit 60 USDC (would exceed max)
        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.expectRevert(ICastLabExperiment.DepositExceedsMaxCost.selector);
        vm.prank(user2);
        funding.userDeposit(experimentId, 60e6);

        // User2 deposits exactly 50 USDC (reaches max)
        vm.prank(user2);
        funding.userDeposit(experimentId, 50e6);

        assertEq(funding.getExperimentInfo(experimentId).totalDeposited, 200e6);
    }

    function testOnlyAdminCanCreateExperiment() public {
        // User1 tries to create experiment - should fail
        vm.expectRevert(ICastLabExperiment.OnlyAdminOrAdminDev.selector);
        vm.prank(user1);
        funding.adminCreateExperiment(100e6, 500e6);

        // Admin1 creates experiment - should succeed
        vm.prank(admin);
        uint256 id1 = funding.adminCreateExperiment(100e6, 500e6);
        assertEq(id1, 0);

        // Admin2 creates experiment - should succeed
        vm.prank(admin2);
        uint256 id2 = funding.adminCreateExperiment(200e6, 600e6);
        assertEq(id2, 1);
    }

    function testAdminCannotWithdrawBelowMinCost() public {
        // Admin creates experiment
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100e6, // minCost: 100 USDC
            500e6 // maxCost: 500 USDC
        );

        // User1 deposits 50 USDC (below minCost)
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userDeposit(experimentId, 50e6);

        // Admin tries to withdraw - should fail
        vm.expectRevert(ICastLabExperiment.MinCostNotReached.selector);
        vm.prank(admin);
        funding.adminWithdraw(experimentId);

        // User2 deposits 60 USDC (total now 110, above minCost)
        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userDeposit(experimentId, 60e6);

        // Now admin can withdraw
        vm.prank(admin);
        funding.adminWithdraw(experimentId);

        ICastLabExperiment.Experiment memory exp = funding.getExperimentInfo(experimentId);
        assertEq(exp.totalDeposited, 0);
        assertFalse(exp.open);
    }

    function testGetUserExperiments() public {
        // Admin creates multiple experiments
        vm.prank(admin);
        uint256 exp1 = funding.adminCreateExperiment(100e6, 500e6);
        vm.prank(admin);
        funding.adminCreateExperiment(200e6, 600e6); // exp2 not used in test
        vm.prank(admin);
        uint256 exp3 = funding.adminCreateExperiment(300e6, 700e6);

        // User1 deposits to exp1 and exp3
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);

        vm.prank(user1);
        funding.userDeposit(exp1, 50e6);

        vm.prank(user1);
        funding.userDeposit(exp3, 100e6);

        // Get user experiments
        (uint256[] memory expIds, uint256[] memory amounts) = funding.getUserExperiments(user1);

        assertEq(expIds.length, 2);
        assertEq(amounts.length, 2);
        assertEq(expIds[0], exp1);
        assertEq(expIds[1], exp3);
        assertEq(amounts[0], 50e6);
        assertEq(amounts[1], 100e6);
    }

    function testAdminCloseRequiresZeroBalance() public {
        // Admin creates experiment
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100e6, // minCost: 100 USDC
            500e6 // maxCost: 500 USDC
        );

        // User1 deposits
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userDeposit(experimentId, 50e6);

        // Admin tries to close with funds still in - should fail
        vm.expectRevert(ICastLabExperiment.MustReturnAllDepositsFirst.selector);
        vm.prank(admin);
        funding.adminClose(experimentId);

        // User1 undeposits
        vm.prank(user1);
        funding.userUndeposit(experimentId);

        // Now admin can close
        vm.prank(admin);
        funding.adminClose(experimentId);

        ICastLabExperiment.Experiment memory exp = funding.getExperimentInfo(experimentId);
        assertEq(exp.totalDeposited, 0);
        assertFalse(exp.open);
    }

    function testNonExistentExperimentOperations() public {
        uint256 nonExistentId = 999;

        // User tries to deposit to non-existent experiment
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.expectRevert(ICastLabExperiment.ExperimentClosed.selector);
        vm.prank(user1);
        funding.userDeposit(nonExistentId, 50e6);

        // User tries to undeposit from non-existent experiment
        vm.expectRevert(ICastLabExperiment.ExperimentClosed.selector);
        vm.prank(user1);
        funding.userUndeposit(nonExistentId);

        // Admin tries to withdraw from non-existent experiment
        vm.expectRevert(ICastLabExperiment.ExperimentClosed.selector);
        vm.prank(admin);
        funding.adminWithdraw(nonExistentId);

        // Admin tries to close non-existent experiment
        vm.expectRevert(ICastLabExperiment.ExperimentClosed.selector);
        vm.prank(admin);
        funding.adminClose(nonExistentId);

        // Admin tries to return funds from non-existent experiment
        address[] memory depositors = new address[](1);
        depositors[0] = user1;
        vm.expectRevert(ICastLabExperiment.ExperimentClosed.selector);
        vm.prank(admin);
        funding.adminRefund(nonExistentId, depositors);
    }

    function testAdminDevPermissionBoundaries() public {
        // admin_dev can create experiments
        vm.prank(admin2);
        uint256 experimentId = funding.adminCreateExperiment(100e6, 500e6);

        // User deposits some funds
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userDeposit(experimentId, 150e6);

        // admin_dev can NOT withdraw (only admin)
        vm.expectRevert(ICastLabExperiment.OnlyAdmin.selector);
        vm.prank(admin2);
        funding.adminWithdraw(experimentId);

        // admin_dev CAN close after funds returned
        vm.prank(user1);
        funding.userUndeposit(experimentId);
        vm.prank(admin2);
        funding.adminClose(experimentId);

        // Create another experiment for adminReturn test
        vm.prank(admin2);
        uint256 experimentId2 = funding.adminCreateExperiment(100e6, 500e6);

        vm.prank(user1);
        funding.userDeposit(experimentId2, 50e6);

        // admin_dev CAN return funds
        address[] memory depositors = new address[](1);
        depositors[0] = user1;
        vm.prank(admin2);
        funding.adminRefund(experimentId2, depositors);
    }

    function testMultipleDepositsFromSameUser() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(100e6, 500e6);

        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);

        // First deposit: 30 USDC
        vm.prank(user1);
        funding.userDeposit(experimentId, 30e6);
        (uint256 depositAmount1, , ) = funding.getUserPosition(experimentId, user1);
        assertEq(depositAmount1, 30e6);

        // Second deposit: 25 USDC (total: 55)
        vm.prank(user1);
        funding.userDeposit(experimentId, 25e6);
        (uint256 depositAmount2, , ) = funding.getUserPosition(experimentId, user1);
        assertEq(depositAmount2, 55e6);

        // Third deposit: 45 USDC (total: 100)
        vm.prank(user1);
        funding.userDeposit(experimentId, 45e6);
        (uint256 depositAmount3, , ) = funding.getUserPosition(experimentId, user1);
        assertEq(depositAmount3, 100e6);

        // Verify total deposited
        assertEq(funding.getExperimentInfo(experimentId).totalDeposited, 100e6);

        // Undeposit withdraws full accumulated amount
        uint256 balanceBefore = token.balanceOf(user1);
        vm.prank(user1);
        funding.userUndeposit(experimentId);
        assertEq(token.balanceOf(user1), balanceBefore + 100e6);
        (uint256 depositAmount, , ) = funding.getUserPosition(experimentId, user1);
        assertEq(depositAmount, 0);
    }

    function testAdminReturnWithZeroDeposits() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(100e6, 500e6);

        // User1 and User2 deposit
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userDeposit(experimentId, 50e6);

        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userDeposit(experimentId, 75e6);

        // Try to return funds to user3 who never deposited (should be no-op)
        address[] memory depositors = new address[](3);
        depositors[0] = user1;
        depositors[1] = user3; // Never deposited
        depositors[2] = user2;

        uint256 user1BalanceBefore = token.balanceOf(user1);
        uint256 user2BalanceBefore = token.balanceOf(user2);
        uint256 user3BalanceBefore = token.balanceOf(user3);

        vm.prank(admin);
        funding.adminRefund(experimentId, depositors);

        // User1 and User2 get funds, User3 gets nothing (had no deposit)
        assertEq(token.balanceOf(user1), user1BalanceBefore + 50e6);
        assertEq(token.balanceOf(user2), user2BalanceBefore + 75e6);
        assertEq(token.balanceOf(user3), user3BalanceBefore); // No change

        // All deposits cleared
        (uint256 depositAmount1, , ) = funding.getUserPosition(experimentId, user1);
        assertEq(depositAmount1, 0);
        (uint256 depositAmount2, , ) = funding.getUserPosition(experimentId, user2);
        assertEq(depositAmount2, 0);
        (uint256 depositAmount3, , ) = funding.getUserPosition(experimentId, user3);
        assertEq(depositAmount3, 0);
    }

    function testUserActionsAfterAdminWithdraw() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(100e6, 500e6);

        // User1 and User2 deposit
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userDeposit(experimentId, 60e6);

        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userDeposit(experimentId, 80e6);

        // Admin withdraws (experiment succeeds)
        vm.prank(admin);
        funding.adminWithdraw(experimentId);

        // Verify experiment is closed
        ICastLabExperiment.Experiment memory exp = funding.getExperimentInfo(experimentId);
        assertEq(exp.totalDeposited, 0);
        assertFalse(exp.open);

        // IMPORTANT: User deposits are preserved for NFT claims
        (uint256 depositAmount, , ) = funding.getUserPosition(experimentId, user1);
        assertEq(depositAmount, 60e6);
        (uint256 depositAmount2, , ) = funding.getUserPosition(experimentId, user2);
        assertEq(depositAmount2, 80e6);

        // Users cannot undeposit (experiment closed)
        vm.expectRevert(ICastLabExperiment.ExperimentClosed.selector);
        vm.prank(user1);
        funding.userUndeposit(experimentId);

        // Users cannot deposit more (experiment closed)
        vm.expectRevert(ICastLabExperiment.ExperimentClosed.selector);
        vm.prank(user1);
        funding.userDeposit(experimentId, 10e6);

        // Admin cannot withdraw again (experiment closed)
        vm.expectRevert(ICastLabExperiment.ExperimentClosed.selector);
        vm.prank(admin);
        funding.adminWithdraw(experimentId);
    }

    // ============================================
    // BETTING TESTS
    // ============================================

    function testBasicBettingOnBothSides() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(100e6, 500e6);

        // User1 bets 50 USDC on side 0
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userBet(experimentId, 50e6, 0);

        // User2 bets 75 USDC on side 1
        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userBet(experimentId, 0, 75e6);

        // Verify bet amounts are tracked
        assertEq(funding.bets0(experimentId, user1), 50e6);
        assertEq(funding.bets1(experimentId, user2), 75e6);
    }

    function testMinimumBetRequirement() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(100e6, 500e6);

        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);

        // Try to bet 0.5 USDC - should fail
        vm.expectRevert(ICastLabExperiment.BetBelowMinimum.selector);
        vm.prank(user1);
        funding.userBet(experimentId, 0.5e6, 0);

        // Bet 1.1 USDC - should succeed
        vm.prank(user1);
        funding.userBet(experimentId, 1e6, 0);
        assertEq(funding.bets0(experimentId, user1), 1e6);
    }

    function testMultipleBetsFromSameUser() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(100e6, 500e6);

        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);

        // First bet: 30 USDC on side 0
        vm.prank(user1);
        funding.userBet(experimentId, 30e6, 0);
        assertEq(funding.bets0(experimentId, user1), 30e6);

        // Second bet: 25 USDC on side 0 (total: 55)
        vm.prank(user1);
        funding.userBet(experimentId, 25e6, 0);
        assertEq(funding.bets0(experimentId, user1), 55e6);

        // Third bet: 45 USDC on side 0 (total: 100)
        vm.prank(user1);
        funding.userBet(experimentId, 45e6, 0);
        assertEq(funding.bets0(experimentId, user1), 100e6);
    }

    function testUserCanHedgeByBettingBothSides() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(100e6, 500e6);

        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);

        // User1 bets on side 0
        vm.prank(user1);
        funding.userBet(experimentId, 50e6, 0);

        // User1 also bets on side 1 (hedging)
        vm.prank(user1);
        funding.userBet(experimentId, 0, 30e6);

        // Verify both bets are tracked
        assertEq(funding.bets0(experimentId, user1), 50e6);
        assertEq(funding.bets1(experimentId, user1), 30e6);
    }

    function testAdminSetResultAndClaimProfit() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(100e6, 500e6);

        // User3 deposits to fund the experiment
        vm.prank(user3);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user3);
        funding.userDeposit(experimentId, 100e6);

        // User1 bets 100 USDC on side 0
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userBet(experimentId, 100e6, 0);

        // User2 bets 50 USDC on side 1
        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userBet(experimentId, 0, 50e6);

        // Admin withdraws funding (closes experiment)
        vm.prank(admin);
        funding.adminWithdraw(experimentId);

        // Admin sets result to 0 (user1 wins)
        vm.prank(admin);
        funding.adminSetResult(experimentId, 0);

        // User1 claims profit (should get all 150 USDC)
        uint256 user1BalanceBefore = token.balanceOf(user1);
        vm.prank(user1);
        funding.userClaimBetProfit(experimentId);
        assertEq(token.balanceOf(user1), user1BalanceBefore + 150e6);

        // User1's bet should be zeroed
        assertEq(funding.bets0(experimentId, user1), 0);
    }

    function testProportionalPayoutCalculation() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(100e6, 500e6);

        // Admin deposits to fund the experiment
        vm.prank(admin);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(admin);
        funding.userDeposit(experimentId, 100e6);

        // User1 bets 60 USDC on side 0
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userBet(experimentId, 60e6, 0);

        // User2 bets 40 USDC on side 0
        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userBet(experimentId, 40e6, 0);

        // User3 bets 100 USDC on side 1 (loses)
        vm.prank(user3);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user3);
        funding.userBet(experimentId, 0, 100e6);

        // Total pool: 200 USDC
        // Winning side (0): 100 USDC
        // User1 payout: (60 / 100) * 200 = 120 USDC
        // User2 payout: (40 / 100) * 200 = 80 USDC

        // Admin withdraws funding (closes experiment)
        vm.prank(admin);
        funding.adminWithdraw(experimentId);

        // Admin sets result to 0
        vm.prank(admin);
        funding.adminSetResult(experimentId, 0);

        // User1 claims
        uint256 user1BalanceBefore = token.balanceOf(user1);
        vm.prank(user1);
        funding.userClaimBetProfit(experimentId);
        assertEq(token.balanceOf(user1), user1BalanceBefore + 120e6);

        // User2 claims
        uint256 user2BalanceBefore = token.balanceOf(user2);
        vm.prank(user2);
        funding.userClaimBetProfit(experimentId);
        assertEq(token.balanceOf(user2), user2BalanceBefore + 80e6);

        // User3 cannot claim (losing side)
        vm.expectRevert(ICastLabExperiment.NoWinningBet.selector);
        vm.prank(user3);
        funding.userClaimBetProfit(experimentId);
    }

    function testCannotSetResultTwice() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(100e6, 500e6);

        // Admin deposits to fund the experiment
        vm.prank(admin);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(admin);
        funding.userDeposit(experimentId, 100e6);

        // Place some bets
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userBet(experimentId, 50e6, 0);

        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userBet(experimentId, 0, 50e6);

        // Admin withdraws funding (closes experiment)
        vm.prank(admin);
        funding.adminWithdraw(experimentId);

        // Admin sets result to 0
        vm.prank(admin);
        funding.adminSetResult(experimentId, 0);

        // Try to set result again - should fail
        vm.expectRevert(ICastLabExperiment.ResultAlreadySet.selector);
        vm.prank(admin);
        funding.adminSetResult(experimentId, 1);
    }

    function testCannotSetResultWinningSideHasNoBets() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(100e6, 500e6);

        // Admin deposits to fund the experiment
        vm.prank(admin);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(admin);
        funding.userDeposit(experimentId, 100e6);

        // Only user1 bets on side 0
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userBet(experimentId, 50e6, 0);

        // Admin withdraws funding (closes experiment)
        vm.prank(admin);
        funding.adminWithdraw(experimentId);

        // Admin tries to set result to 1 (but no one bet on side 1) - should fail
        vm.expectRevert(ICastLabExperiment.WinningSideHasNoBets.selector);
        vm.prank(admin);
        funding.adminSetResult(experimentId, 1);

        // Admin sets result to 0 - should succeed
        vm.prank(admin);
        funding.adminSetResult(experimentId, 0);
    }

    function testCannotBetAfterResultSet() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(100e6, 500e6);

        // Admin deposits to fund the experiment
        vm.prank(admin);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(admin);
        funding.userDeposit(experimentId, 100e6);

        // Place initial bets
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userBet(experimentId, 50e6, 0);

        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userBet(experimentId, 0, 50e6);

        // Admin withdraws funding (closes experiment)
        vm.prank(admin);
        funding.adminWithdraw(experimentId);

        // Admin sets result
        vm.prank(admin);
        funding.adminSetResult(experimentId, 0);

        // User3 tries to bet - should fail (experiment is closed)
        vm.prank(user3);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.expectRevert(ICastLabExperiment.ExperimentClosed.selector);
        vm.prank(user3);
        funding.userBet(experimentId, 30e6, 0);
    }

    function testCannotClaimBeforeResultSet() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(100e6, 500e6);

        // User1 bets
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userBet(experimentId, 50e6, 0);

        // User1 tries to claim before result set - should fail
        vm.expectRevert(ICastLabExperiment.ResultNotSet.selector);
        vm.prank(user1);
        funding.userClaimBetProfit(experimentId);
    }

    function testCannotClaimTwice() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(100e6, 500e6);

        // Admin deposits to fund the experiment
        vm.prank(admin);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(admin);
        funding.userDeposit(experimentId, 100e6);

        // User1 bets on side 0
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userBet(experimentId, 50e6, 0);

        // User2 bets on side 1
        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userBet(experimentId, 0, 50e6);

        // Admin withdraws funding (closes experiment)
        vm.prank(admin);
        funding.adminWithdraw(experimentId);

        // Admin sets result to 0
        vm.prank(admin);
        funding.adminSetResult(experimentId, 0);

        // User1 claims once
        vm.prank(user1);
        funding.userClaimBetProfit(experimentId);

        // User1 tries to claim again - should fail
        vm.expectRevert(ICastLabExperiment.NoWinningBet.selector);
        vm.prank(user1);
        funding.userClaimBetProfit(experimentId);
    }

    function testUserUnbetAfter60Days() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(100e6, 500e6);

        // User1 bets on both sides
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userBet(experimentId, 50e6, 0);
        vm.prank(user1);
        funding.userBet(experimentId, 0, 30e6);

        // Try to unbet before 30 days - should fail
        vm.expectRevert(ICastLabExperiment.MustWait60Days.selector);
        vm.prank(user1);
        funding.userUnbet(experimentId);

        // Fast forward 60 days
        vm.warp(block.timestamp + 60 days);

        // Now user can unbet
        uint256 user1BalanceBefore = token.balanceOf(user1);
        vm.prank(user1);
        funding.userUnbet(experimentId);

        // User should get both bets back (50 + 30 = 80)
        assertEq(token.balanceOf(user1), user1BalanceBefore + 80e6);

        // Bets should be zeroed
        assertEq(funding.bets0(experimentId, user1), 0);
        assertEq(funding.bets1(experimentId, user1), 0);
    }

    function testCannotUnbetAfterResultSet() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(100e6, 500e6);

        // Admin deposits to fund the experiment
        vm.prank(admin);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(admin);
        funding.userDeposit(experimentId, 100e6);

        // User1 bets
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userBet(experimentId, 50e6, 0);

        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userBet(experimentId, 0, 50e6);

        // Admin withdraws funding (closes experiment)
        vm.prank(admin);
        funding.adminWithdraw(experimentId);

        // Admin sets result
        vm.prank(admin);
        funding.adminSetResult(experimentId, 0);

        // Fast forward 30 days
        vm.warp(block.timestamp + 60 days);

        // User tries to unbet - should fail because result is set
        vm.expectRevert(ICastLabExperiment.ResultAlreadySet.selector);
        vm.prank(user1);
        funding.userUnbet(experimentId);
    }

    function testAdminReturnBetToMultipleUsers() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(100e6, 500e6);

        // User1 bets 50 USDC on side 0
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userBet(experimentId, 50e6, 0);

        // User2 bets 75 USDC on side 1
        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userBet(experimentId, 0, 75e6);

        // User3 bets on both sides
        vm.prank(user3);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user3);
        funding.userBet(experimentId, 30e6, 0);
        vm.prank(user3);
        funding.userBet(experimentId, 0, 20e6);

        // Admin returns bets
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        uint256 user1BalanceBefore = token.balanceOf(user1);
        uint256 user2BalanceBefore = token.balanceOf(user2);
        uint256 user3BalanceBefore = token.balanceOf(user3);

        vm.prank(admin);
        funding.adminReturnBet(experimentId, users);

        // Verify users got their bets back
        assertEq(token.balanceOf(user1), user1BalanceBefore + 50e6);
        assertEq(token.balanceOf(user2), user2BalanceBefore + 75e6);
        assertEq(token.balanceOf(user3), user3BalanceBefore + 50e6); // 30 + 20

        // Verify bets are cleared
        assertEq(funding.bets0(experimentId, user1), 0);
        assertEq(funding.bets1(experimentId, user2), 0);
        assertEq(funding.bets0(experimentId, user3), 0);
        assertEq(funding.bets1(experimentId, user3), 0);
    }

    function testAdminDevCanReturnBets() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(100e6, 500e6);

        // User1 bets
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userBet(experimentId, 50e6, 0);

        // admin_dev returns bet
        address[] memory users = new address[](1);
        users[0] = user1;

        vm.prank(admin2); // admin2 is admin_dev
        funding.adminReturnBet(experimentId, users);

        assertEq(funding.bets0(experimentId, user1), 0);
    }

    function testAdminCloseMarketRequiresAllDepositsReturned() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(100e6, 500e6);

        // User1 deposits
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userDeposit(experimentId, 50e6);

        // Try to close market with deposits still active - should fail
        vm.expectRevert(ICastLabExperiment.MustReturnAllDepositsFirst.selector);
        vm.prank(admin);
        funding.adminClose(experimentId);

        // Return deposit
        vm.prank(user1);
        funding.userUndeposit(experimentId);

        // Now can close market
        vm.prank(admin);
        funding.adminClose(experimentId);
    }

    function testOnlyAdminCanSetResult() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(100e6, 500e6);

        // Admin deposits to fund the experiment
        vm.prank(admin);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(admin);
        funding.userDeposit(experimentId, 100e6);

        // Place bets
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userBet(experimentId, 50e6, 0);

        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userBet(experimentId, 0, 50e6);

        // Admin withdraws funding (closes experiment)
        vm.prank(admin);
        funding.adminWithdraw(experimentId);

        // admin_dev tries to set result - should fail
        vm.expectRevert(ICastLabExperiment.OnlyAdmin.selector);
        vm.prank(admin2);
        funding.adminSetResult(experimentId, 0);

        // Regular user tries to set result - should fail
        vm.expectRevert(ICastLabExperiment.OnlyAdmin.selector);
        vm.prank(user1);
        funding.adminSetResult(experimentId, 0);

        // Admin sets result - should succeed
        vm.prank(admin);
        funding.adminSetResult(experimentId, 0);
    }

    function testOnlyAdminOrDevCanCloseMarket() public {
        // Create first experiment for admin_dev to close
        vm.prank(admin);
        uint256 experimentId1 = funding.adminCreateExperiment(100e6, 500e6);

        // admin_dev can close market - should succeed
        vm.prank(admin2);
        funding.adminClose(experimentId1);

        // Verify it's closed
        assertFalse(funding.getExperimentInfo(experimentId1).open);

        // Create second experiment for admin to close
        vm.prank(admin);
        uint256 experimentId2 = funding.adminCreateExperiment(100e6, 500e6);

        // Admin can close market - should succeed
        vm.prank(admin);
        funding.adminClose(experimentId2);

        // Verify it's closed
        assertFalse(funding.getExperimentInfo(experimentId2).open);

        // Create third experiment for regular user test
        vm.prank(admin);
        uint256 experimentId3 = funding.adminCreateExperiment(100e6, 500e6);

        // Regular user cannot close market - should fail
        vm.expectRevert(ICastLabExperiment.OnlyAdminOrAdminDev.selector);
        vm.prank(user1);
        funding.adminClose(experimentId3);
    }

    function testUserFundAndBetConvenienceFunction() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(100e6, 500e6);

        // User1 funds and bets in one transaction
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userFundAndBet(
            experimentId,
            50e6, // fund amount
            30e6, // bet amount on outcome 0
            0 // bet amount on outcome 1
        );

        // Verify both deposit and bet were recorded
        (uint256 depositAmount, , ) = funding.getUserPosition(experimentId, user1);
        assertEq(depositAmount, 50e6);
        assertEq(funding.bets0(experimentId, user1), 30e6);
    }

    function testUserFundAndBetWithZeroFund() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(100e6, 500e6);

        // User1 only bets (no funding)
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userFundAndBet(
            experimentId,
            0, // no fund amount
            30e6, // bet amount on outcome 0
            0 // bet amount on outcome 1
        );

        // Verify only bet was recorded
        (uint256 depositAmount, , ) = funding.getUserPosition(experimentId, user1);
        assertEq(depositAmount, 0);
        assertEq(funding.bets0(experimentId, user1), 30e6);
    }

    function testUserFundAndBetWithZeroBet() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(100e6, 500e6);

        // User1 only funds (no betting)
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userFundAndBet(
            experimentId,
            50e6, // fund amount
            0, // bet amount on outcome 0
            0 // bet amount on outcome 1
        );

        // Verify only deposit was recorded
        (uint256 depositAmount, , ) = funding.getUserPosition(experimentId, user1);
        assertEq(depositAmount, 50e6);
        assertEq(funding.bets0(experimentId, user1), 0);
    }

    function testCannotBetOnClosedExperiment() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(100e6, 500e6);

        // Close the experiment
        vm.prank(admin);
        funding.adminClose(experimentId);

        // Try to bet on closed experiment - should fail
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.expectRevert(ICastLabExperiment.ExperimentClosed.selector);
        vm.prank(user1);
        funding.userBet(experimentId, 50e6, 0);
    }

    function testCompleteSuccessPath() public {
        // Admin creates experiment
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(100e6, 500e6);

        // Users deposit to fund experiment
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userDeposit(experimentId, 60e6);

        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userDeposit(experimentId, 80e6);

        // Users place bets
        vm.prank(user1);
        funding.userBet(experimentId, 40e6, 0);

        vm.prank(user2);
        funding.userBet(experimentId, 0, 60e6);

        // Admin withdraws funding (experiment succeeds)
        vm.prank(admin);
        funding.adminWithdraw(experimentId);

        // Admin sets result
        vm.prank(admin);
        funding.adminSetResult(experimentId, 0);

        // Winner claims profit
        uint256 user1BalanceBefore = token.balanceOf(user1);
        vm.prank(user1);
        funding.userClaimBetProfit(experimentId);
        // User1 should get all 100 USDC (40 + 60)
        assertEq(token.balanceOf(user1), user1BalanceBefore + 100e6);
    }
}
