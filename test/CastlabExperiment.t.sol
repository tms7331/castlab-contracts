// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/CastlabExperiment.sol";
import "../src/TestToken.sol";

contract CastlabExperimentNewTest is Test {
    CastlabExperiment public funding;
    TestToken public token;
    address public admin;
    address public admin2;
    address public user1;
    address public user2;
    address public user3;

    uint256 constant INITIAL_BALANCE = 10000 * 10 ** 6; // 10,000 USDC (6 decimals)

    event ExperimentCreated(
        uint256 indexed experimentId,
        uint256 costMin,
        uint256 costMax
    );
    event Deposited(
        uint256 indexed experimentId,
        address indexed depositor,
        uint256 amount
    );
    event Undeposited(
        uint256 indexed experimentId,
        address indexed depositor,
        uint256 amount
    );
    event AdminWithdraw(uint256 indexed experimentId, uint256 amount);
    event AdminClose(uint256 indexed experimentId);

    function setUp() public {
        admin = address(0x1);
        admin2 = address(0x2);
        user1 = address(0x3);
        user2 = address(0x4);
        user3 = address(0x5);

        // Deploy token and funding contracts
        token = new TestToken();
        funding = new CastlabExperiment(admin, admin2, address(token));

        // Get the TestToken admin addresses
        address tokenAdmin1 = 0x4611F6d137d1baf545378dD02C1b16eb63cbE755;

        // Transfer tokens to test users
        vm.prank(tokenAdmin1);
        token.transfer(user1, INITIAL_BALANCE);

        vm.prank(tokenAdmin1);
        token.transfer(user2, INITIAL_BALANCE);

        vm.prank(tokenAdmin1);
        token.transfer(user3, INITIAL_BALANCE);

        vm.prank(tokenAdmin1);
        token.transfer(admin, INITIAL_BALANCE);
    }

    function testThreeUsersDepositOneUndepositsAdminReturns() public {
        // Admin creates experiment with minCost = 100 USDC, maxCost = 500 USDC
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6, // minCost: 100 USDC
            500 * 10 ** 6 // maxCost: 500 USDC
        );

        // User1 approves and deposits 50 USDC
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userDeposit(experimentId, 50 * 10 ** 6);

        // User2 approves and deposits 75 USDC
        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userDeposit(experimentId, 75 * 10 ** 6);

        // User3 approves and deposits 100 USDC
        vm.prank(user3);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user3);
        funding.userDeposit(experimentId, 100 * 10 ** 6);

        // Check total deposited is 225 USDC
        (, , uint256 totalDeposited, ) = funding.getExperimentInfo(
            experimentId
        );
        assertEq(totalDeposited, 225 * 10 ** 6);

        // User2 undeposits their 75 USDC
        uint256 user2BalanceBefore = token.balanceOf(user2);
        vm.prank(user2);
        funding.userUndeposit(experimentId);
        assertEq(token.balanceOf(user2), user2BalanceBefore + 75 * 10 ** 6);
        assertEq(funding.getUserDeposit(experimentId, user2), 0);

        // Check total deposited is now 150 USDC
        (, , totalDeposited, ) = funding.getExperimentInfo(experimentId);
        assertEq(totalDeposited, 150 * 10 ** 6);

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
        assertEq(token.balanceOf(user1), user1BalanceBefore + 50 * 10 ** 6);
        assertEq(token.balanceOf(user3), user3BalanceBefore + 100 * 10 ** 6);

        // Verify experiment is closed and deposits are cleared
        bool open;
        (, , totalDeposited, open) = funding.getExperimentInfo(experimentId);
        assertEq(totalDeposited, 0);
        assertFalse(open);
        assertEq(funding.getUserDeposit(experimentId, user1), 0);
        assertEq(funding.getUserDeposit(experimentId, user3), 0);
    }

    function testDepositUndepositRedepositPastMinCostAdminCloses() public {
        // Admin creates experiment with minCost = 100 USDC, maxCost = 500 USDC
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6, // minCost: 100 USDC
            500 * 10 ** 6 // maxCost: 500 USDC
        );

        // User1 approves funding contract
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);

        // User1 deposits 60 USDC
        vm.prank(user1);
        funding.userDeposit(experimentId, 60 * 10 ** 6);
        assertEq(funding.getUserDeposit(experimentId, user1), 60 * 10 ** 6);

        // User1 undeposits the 60 USDC
        vm.prank(user1);
        funding.userUndeposit(experimentId);
        assertEq(funding.getUserDeposit(experimentId, user1), 0);

        // User1 redeposits 150 USDC (past minCost)
        vm.prank(user1);
        funding.userDeposit(experimentId, 150 * 10 ** 6);
        assertEq(funding.getUserDeposit(experimentId, user1), 150 * 10 ** 6);

        // Verify total is past minCost
        (uint256 costMin, , uint256 totalDeposited, ) = funding
            .getExperimentInfo(experimentId);
        assertEq(totalDeposited, 150 * 10 ** 6);
        assertTrue(totalDeposited >= costMin);

        // Admin withdraws the funds (closes the experiment)
        uint256 adminBalanceBefore = token.balanceOf(admin);
        vm.prank(admin);
        funding.adminWithdraw(experimentId);
        assertEq(token.balanceOf(admin), adminBalanceBefore + 150 * 10 ** 6);

        // Verify experiment is closed
        bool open;
        (, , totalDeposited, open) = funding.getExperimentInfo(experimentId);
        assertEq(totalDeposited, 0);
        assertFalse(open);

        // User1 tries to undeposit but should fail because experiment is closed
        vm.expectRevert("Experiment is closed");
        vm.prank(user1);
        funding.userUndeposit(experimentId);

        // User1 also can't deposit anymore
        vm.expectRevert("Experiment is closed");
        vm.prank(user1);
        funding.userDeposit(experimentId, 10 * 10 ** 6);
    }

    function testMinimumDepositRequirement() public {
        // Admin creates experiment
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6, // minCost: 100 USDC
            500 * 10 ** 6 // maxCost: 500 USDC
        );

        // User1 approves funding contract
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);

        // Try to deposit exactly 1 USDC (1 * 10^6) - should fail
        vm.expectRevert("Deposit must be greater than 1 USDC");
        vm.prank(user1);
        funding.userDeposit(experimentId, 1 * 10 ** 6);

        // Try to deposit 0.5 USDC - should fail
        vm.expectRevert("Deposit must be greater than 1 USDC");
        vm.prank(user1);
        funding.userDeposit(experimentId, 0.5 * 10 ** 6);

        // Deposit 1.1 USDC - should succeed
        vm.prank(user1);
        funding.userDeposit(experimentId, 1.1 * 10 ** 6);
        assertEq(funding.getUserDeposit(experimentId, user1), 1.1 * 10 ** 6);
    }

    function testCannotExceedMaxCost() public {
        // Admin creates experiment
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6, // minCost: 100 USDC
            200 * 10 ** 6 // maxCost: 200 USDC
        );

        // User1 approves and deposits 150 USDC
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userDeposit(experimentId, 150 * 10 ** 6);

        // User2 tries to deposit 60 USDC (would exceed max)
        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.expectRevert("Deposit would exceed maximum cost");
        vm.prank(user2);
        funding.userDeposit(experimentId, 60 * 10 ** 6);

        // User2 deposits exactly 50 USDC (reaches max)
        vm.prank(user2);
        funding.userDeposit(experimentId, 50 * 10 ** 6);

        (, , uint256 totalDeposited, ) = funding.getExperimentInfo(
            experimentId
        );
        assertEq(totalDeposited, 200 * 10 ** 6);
    }

    function testOnlyAdminCanCreateExperiment() public {
        // User1 tries to create experiment - should fail
        vm.expectRevert("Only admin or admin_dev can call this function");
        vm.prank(user1);
        funding.adminCreateExperiment(100 * 10 ** 6, 500 * 10 ** 6);

        // Admin1 creates experiment - should succeed
        vm.prank(admin);
        uint256 id1 = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );
        assertEq(id1, 0);

        // Admin2 creates experiment - should succeed
        vm.prank(admin2);
        uint256 id2 = funding.adminCreateExperiment(
            200 * 10 ** 6,
            600 * 10 ** 6
        );
        assertEq(id2, 1);
    }

    function testAdminCannotWithdrawBelowMinCost() public {
        // Admin creates experiment
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6, // minCost: 100 USDC
            500 * 10 ** 6 // maxCost: 500 USDC
        );

        // User1 deposits 50 USDC (below minCost)
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userDeposit(experimentId, 50 * 10 ** 6);

        // Admin tries to withdraw - should fail
        vm.expectRevert("Minimum cost has not been reached");
        vm.prank(admin);
        funding.adminWithdraw(experimentId);

        // User2 deposits 60 USDC (total now 110, above minCost)
        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userDeposit(experimentId, 60 * 10 ** 6);

        // Now admin can withdraw
        vm.prank(admin);
        funding.adminWithdraw(experimentId);

        (, , uint256 totalDeposited, bool open) = funding.getExperimentInfo(
            experimentId
        );
        assertEq(totalDeposited, 0);
        assertFalse(open);
    }

    function testGetUserExperiments() public {
        // Admin creates multiple experiments
        vm.prank(admin);
        uint256 exp1 = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );
        vm.prank(admin);
        funding.adminCreateExperiment(200 * 10 ** 6, 600 * 10 ** 6); // exp2 not used in test
        vm.prank(admin);
        uint256 exp3 = funding.adminCreateExperiment(
            300 * 10 ** 6,
            700 * 10 ** 6
        );

        // User1 deposits to exp1 and exp3
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);

        vm.prank(user1);
        funding.userDeposit(exp1, 50 * 10 ** 6);

        vm.prank(user1);
        funding.userDeposit(exp3, 100 * 10 ** 6);

        // Get user experiments
        (uint256[] memory expIds, uint256[] memory amounts) = funding
            .getUserExperiments(user1);

        assertEq(expIds.length, 2);
        assertEq(amounts.length, 2);
        assertEq(expIds[0], exp1);
        assertEq(expIds[1], exp3);
        assertEq(amounts[0], 50 * 10 ** 6);
        assertEq(amounts[1], 100 * 10 ** 6);
    }

    function testAdminCloseRequiresZeroBalance() public {
        // Admin creates experiment
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6, // minCost: 100 USDC
            500 * 10 ** 6 // maxCost: 500 USDC
        );

        // User1 deposits
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userDeposit(experimentId, 50 * 10 ** 6);

        // Admin tries to close with funds still in - should fail
        vm.expectRevert("Must return all funds first");
        vm.prank(admin);
        funding.adminClose(experimentId);

        // User1 undeposits
        vm.prank(user1);
        funding.userUndeposit(experimentId);

        // Now admin can close
        vm.prank(admin);
        funding.adminClose(experimentId);

        (, , uint256 totalDeposited, bool open) = funding.getExperimentInfo(
            experimentId
        );
        assertEq(totalDeposited, 0);
        assertFalse(open);
    }

    function testNonExistentExperimentOperations() public {
        uint256 nonExistentId = 999;

        // User tries to deposit to non-existent experiment
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.expectRevert("Experiment is closed");
        vm.prank(user1);
        funding.userDeposit(nonExistentId, 50 * 10 ** 6);

        // User tries to undeposit from non-existent experiment
        vm.expectRevert("Experiment is closed");
        vm.prank(user1);
        funding.userUndeposit(nonExistentId);

        // Admin tries to withdraw from non-existent experiment
        vm.expectRevert("Experiment is closed");
        vm.prank(admin);
        funding.adminWithdraw(nonExistentId);

        // Admin tries to close non-existent experiment
        vm.expectRevert("Experiment is closed");
        vm.prank(admin);
        funding.adminClose(nonExistentId);

        // Admin tries to return funds from non-existent experiment
        address[] memory depositors = new address[](1);
        depositors[0] = user1;
        vm.expectRevert("Experiment is closed");
        vm.prank(admin);
        funding.adminRefund(nonExistentId, depositors);
    }

    function testAdminDevPermissionBoundaries() public {
        // admin_dev can create experiments
        vm.prank(admin2);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        // User deposits some funds
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userDeposit(experimentId, 150 * 10 ** 6);

        // admin_dev can NOT withdraw (only admin)
        vm.expectRevert("Only admin can call this function");
        vm.prank(admin2);
        funding.adminWithdraw(experimentId);

        // admin_dev CAN close after funds returned
        vm.prank(user1);
        funding.userUndeposit(experimentId);
        vm.prank(admin2);
        funding.adminClose(experimentId);

        // Create another experiment for adminReturn test
        vm.prank(admin2);
        uint256 experimentId2 = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        vm.prank(user1);
        funding.userDeposit(experimentId2, 50 * 10 ** 6);

        // admin_dev CAN return funds
        address[] memory depositors = new address[](1);
        depositors[0] = user1;
        vm.prank(admin2);
        funding.adminRefund(experimentId2, depositors);
    }

    function testMultipleDepositsFromSameUser() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);

        // First deposit: 30 USDC
        vm.prank(user1);
        funding.userDeposit(experimentId, 30 * 10 ** 6);
        assertEq(funding.getUserDeposit(experimentId, user1), 30 * 10 ** 6);

        // Second deposit: 25 USDC (total: 55)
        vm.prank(user1);
        funding.userDeposit(experimentId, 25 * 10 ** 6);
        assertEq(funding.getUserDeposit(experimentId, user1), 55 * 10 ** 6);

        // Third deposit: 45 USDC (total: 100)
        vm.prank(user1);
        funding.userDeposit(experimentId, 45 * 10 ** 6);
        assertEq(funding.getUserDeposit(experimentId, user1), 100 * 10 ** 6);

        // Verify total deposited
        (, , uint256 totalDeposited, ) = funding.getExperimentInfo(
            experimentId
        );
        assertEq(totalDeposited, 100 * 10 ** 6);

        // Undeposit withdraws full accumulated amount
        uint256 balanceBefore = token.balanceOf(user1);
        vm.prank(user1);
        funding.userUndeposit(experimentId);
        assertEq(token.balanceOf(user1), balanceBefore + 100 * 10 ** 6);
        assertEq(funding.getUserDeposit(experimentId, user1), 0);
    }

    function testAdminReturnWithZeroDeposits() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        // User1 and User2 deposit
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userDeposit(experimentId, 50 * 10 ** 6);

        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userDeposit(experimentId, 75 * 10 ** 6);

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
        assertEq(token.balanceOf(user1), user1BalanceBefore + 50 * 10 ** 6);
        assertEq(token.balanceOf(user2), user2BalanceBefore + 75 * 10 ** 6);
        assertEq(token.balanceOf(user3), user3BalanceBefore); // No change

        // All deposits cleared
        assertEq(funding.getUserDeposit(experimentId, user1), 0);
        assertEq(funding.getUserDeposit(experimentId, user2), 0);
        assertEq(funding.getUserDeposit(experimentId, user3), 0);
    }

    function testUserActionsAfterAdminWithdraw() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        // User1 and User2 deposit
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userDeposit(experimentId, 60 * 10 ** 6);

        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userDeposit(experimentId, 80 * 10 ** 6);

        // Admin withdraws (experiment succeeds)
        vm.prank(admin);
        funding.adminWithdraw(experimentId);

        // Verify experiment is closed
        (, , uint256 totalDeposited, bool open) = funding.getExperimentInfo(
            experimentId
        );
        assertEq(totalDeposited, 0);
        assertFalse(open);

        // IMPORTANT: User deposits are preserved for NFT claims
        assertEq(funding.getUserDeposit(experimentId, user1), 60 * 10 ** 6);
        assertEq(funding.getUserDeposit(experimentId, user2), 80 * 10 ** 6);

        // Users cannot undeposit (experiment closed)
        vm.expectRevert("Experiment is closed");
        vm.prank(user1);
        funding.userUndeposit(experimentId);

        // Users cannot deposit more (experiment closed)
        vm.expectRevert("Experiment is closed");
        vm.prank(user1);
        funding.userDeposit(experimentId, 10 * 10 ** 6);

        // Admin cannot withdraw again (experiment closed)
        vm.expectRevert("Experiment is closed");
        vm.prank(admin);
        funding.adminWithdraw(experimentId);
    }

    // ============================================
    // BETTING TESTS
    // ============================================

    function testBasicBettingOnBothSides() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        // User1 bets 50 USDC on side 0
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userBet(experimentId, 50 * 10 ** 6, 0);

        // User2 bets 75 USDC on side 1
        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userBet(experimentId, 0, 75 * 10 ** 6);

        // Verify bet amounts are tracked
        assertEq(funding.bets0(experimentId, user1), 50 * 10 ** 6);
        assertEq(funding.bets1(experimentId, user2), 75 * 10 ** 6);
    }

    function testMinimumBetRequirement() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);

        // Try to bet exactly 1 USDC - should fail
        vm.expectRevert("Bet on outcome 0 must be 0 or greater than 1 USDC");
        vm.prank(user1);
        funding.userBet(experimentId, 1 * 10 ** 6, 0);

        // Try to bet 0.5 USDC - should fail
        vm.expectRevert("Bet on outcome 0 must be 0 or greater than 1 USDC");
        vm.prank(user1);
        funding.userBet(experimentId, 0.5 * 10 ** 6, 0);

        // Bet 1.1 USDC - should succeed
        vm.prank(user1);
        funding.userBet(experimentId, 1.1 * 10 ** 6, 0);
        assertEq(funding.bets0(experimentId, user1), 1.1 * 10 ** 6);
    }

    function testCannotBetOnInvalidOutcome() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);

        // Try to bet with no amount on either side - should fail
        vm.expectRevert("Must bet on at least one outcome");
        vm.prank(user1);
        funding.userBet(experimentId, 0, 0);
    }

    function testMultipleBetsFromSameUser() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);

        // First bet: 30 USDC on side 0
        vm.prank(user1);
        funding.userBet(experimentId, 30 * 10 ** 6, 0);
        assertEq(funding.bets0(experimentId, user1), 30 * 10 ** 6);

        // Second bet: 25 USDC on side 0 (total: 55)
        vm.prank(user1);
        funding.userBet(experimentId, 25 * 10 ** 6, 0);
        assertEq(funding.bets0(experimentId, user1), 55 * 10 ** 6);

        // Third bet: 45 USDC on side 0 (total: 100)
        vm.prank(user1);
        funding.userBet(experimentId, 45 * 10 ** 6, 0);
        assertEq(funding.bets0(experimentId, user1), 100 * 10 ** 6);
    }

    function testUserCanHedgeByBettingBothSides() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);

        // User1 bets on side 0
        vm.prank(user1);
        funding.userBet(experimentId, 50 * 10 ** 6, 0);

        // User1 also bets on side 1 (hedging)
        vm.prank(user1);
        funding.userBet(experimentId, 0, 30 * 10 ** 6);

        // Verify both bets are tracked
        assertEq(funding.bets0(experimentId, user1), 50 * 10 ** 6);
        assertEq(funding.bets1(experimentId, user1), 30 * 10 ** 6);
    }

    function testAdminSetResultAndClaimProfit() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        // User1 bets 100 USDC on side 0
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userBet(experimentId, 100 * 10 ** 6, 0);

        // User2 bets 50 USDC on side 1
        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userBet(experimentId, 0, 50 * 10 ** 6);

        // Admin sets result to 0 (user1 wins)
        vm.prank(admin);
        funding.adminSetResult(experimentId, 0);

        // User1 claims profit (should get all 150 USDC)
        uint256 user1BalanceBefore = token.balanceOf(user1);
        vm.prank(user1);
        funding.userClaimBetProfit(experimentId);
        assertEq(token.balanceOf(user1), user1BalanceBefore + 150 * 10 ** 6);

        // User1's bet should be zeroed
        assertEq(funding.bets0(experimentId, user1), 0);
    }

    function testProportionalPayoutCalculation() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        // User1 bets 60 USDC on side 0
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userBet(experimentId, 60 * 10 ** 6, 0);

        // User2 bets 40 USDC on side 0
        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userBet(experimentId, 40 * 10 ** 6, 0);

        // User3 bets 100 USDC on side 1 (loses)
        vm.prank(user3);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user3);
        funding.userBet(experimentId, 0, 100 * 10 ** 6);

        // Total pool: 200 USDC
        // Winning side (0): 100 USDC
        // User1 payout: (60 / 100) * 200 = 120 USDC
        // User2 payout: (40 / 100) * 200 = 80 USDC

        // Admin sets result to 0
        vm.prank(admin);
        funding.adminSetResult(experimentId, 0);

        // User1 claims
        uint256 user1BalanceBefore = token.balanceOf(user1);
        vm.prank(user1);
        funding.userClaimBetProfit(experimentId);
        assertEq(token.balanceOf(user1), user1BalanceBefore + 120 * 10 ** 6);

        // User2 claims
        uint256 user2BalanceBefore = token.balanceOf(user2);
        vm.prank(user2);
        funding.userClaimBetProfit(experimentId);
        assertEq(token.balanceOf(user2), user2BalanceBefore + 80 * 10 ** 6);

        // User3 cannot claim (losing side)
        vm.expectRevert("No winning bet");
        vm.prank(user3);
        funding.userClaimBetProfit(experimentId);
    }

    function testCannotSetResultTwice() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        // Place some bets
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userBet(experimentId, 50 * 10 ** 6, 0);

        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userBet(experimentId, 0, 50 * 10 ** 6);

        // Admin sets result to 0
        vm.prank(admin);
        funding.adminSetResult(experimentId, 0);

        // Try to set result again - should fail
        vm.expectRevert("Result already set");
        vm.prank(admin);
        funding.adminSetResult(experimentId, 1);
    }

    function testCannotSetResultWinningSideHasNoBets() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        // Only user1 bets on side 0
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userBet(experimentId, 50 * 10 ** 6, 0);

        // Admin tries to set result to 1 (but no one bet on side 1) - should fail
        vm.expectRevert("Winning side has no bets");
        vm.prank(admin);
        funding.adminSetResult(experimentId, 1);

        // Admin sets result to 0 - should succeed
        vm.prank(admin);
        funding.adminSetResult(experimentId, 0);
    }

    function testCannotSetResultWithNoBets() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        // No bets placed
        // Admin tries to set result - should fail
        vm.expectRevert("No bets placed");
        vm.prank(admin);
        funding.adminSetResult(experimentId, 0);
    }

    function testCannotBetAfterResultSet() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        // Place initial bets
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userBet(experimentId, 50 * 10 ** 6, 0);

        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userBet(experimentId, 0, 50 * 10 ** 6);

        // Admin sets result
        vm.prank(admin);
        funding.adminSetResult(experimentId, 0);

        // User3 tries to bet - should fail
        vm.prank(user3);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.expectRevert("Betting closed");
        vm.prank(user3);
        funding.userBet(experimentId, 30 * 10 ** 6, 0);
    }

    function testCannotClaimBeforeResultSet() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        // User1 bets
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userBet(experimentId, 50 * 10 ** 6, 0);

        // User1 tries to claim before result set - should fail
        vm.expectRevert("Result not set");
        vm.prank(user1);
        funding.userClaimBetProfit(experimentId);
    }

    function testCannotClaimTwice() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        // User1 bets on side 0
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userBet(experimentId, 50 * 10 ** 6, 0);

        // User2 bets on side 1
        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userBet(experimentId, 0, 50 * 10 ** 6);

        // Admin sets result to 0
        vm.prank(admin);
        funding.adminSetResult(experimentId, 0);

        // User1 claims once
        vm.prank(user1);
        funding.userClaimBetProfit(experimentId);

        // User1 tries to claim again - should fail
        vm.expectRevert("No winning bet");
        vm.prank(user1);
        funding.userClaimBetProfit(experimentId);
    }

    function testUserUnbetAfter90Days() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        // User1 bets on both sides
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userBet(experimentId, 50 * 10 ** 6, 0);
        vm.prank(user1);
        funding.userBet(experimentId, 0, 30 * 10 ** 6);

        // Try to unbet before 30 days - should fail
        vm.expectRevert("Must wait 90 days");
        vm.prank(user1);
        funding.userUnbet(experimentId);

        // Fast forward 90 days
        vm.warp(block.timestamp + 90 days);

        // Now user can unbet
        uint256 user1BalanceBefore = token.balanceOf(user1);
        vm.prank(user1);
        funding.userUnbet(experimentId);

        // User should get both bets back (50 + 30 = 80)
        assertEq(token.balanceOf(user1), user1BalanceBefore + 80 * 10 ** 6);

        // Bets should be zeroed
        assertEq(funding.bets0(experimentId, user1), 0);
        assertEq(funding.bets1(experimentId, user1), 0);
    }

    function testCannotUnbetAfterResultSet() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        // User1 bets
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userBet(experimentId, 50 * 10 ** 6, 0);

        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userBet(experimentId, 0, 50 * 10 ** 6);

        // Admin sets result
        vm.prank(admin);
        funding.adminSetResult(experimentId, 0);

        // Fast forward 30 days
        vm.warp(block.timestamp + 90 days);

        // User tries to unbet - should fail because result is set
        vm.expectRevert("Result already set");
        vm.prank(user1);
        funding.userUnbet(experimentId);
    }

    function testAdminReturnBetToMultipleUsers() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        // User1 bets 50 USDC on side 0
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userBet(experimentId, 50 * 10 ** 6, 0);

        // User2 bets 75 USDC on side 1
        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userBet(experimentId, 0, 75 * 10 ** 6);

        // User3 bets on both sides
        vm.prank(user3);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user3);
        funding.userBet(experimentId, 30 * 10 ** 6, 0);
        vm.prank(user3);
        funding.userBet(experimentId, 0, 20 * 10 ** 6);

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
        assertEq(token.balanceOf(user1), user1BalanceBefore + 50 * 10 ** 6);
        assertEq(token.balanceOf(user2), user2BalanceBefore + 75 * 10 ** 6);
        assertEq(token.balanceOf(user3), user3BalanceBefore + 50 * 10 ** 6); // 30 + 20

        // Verify bets are cleared
        assertEq(funding.bets0(experimentId, user1), 0);
        assertEq(funding.bets1(experimentId, user2), 0);
        assertEq(funding.bets0(experimentId, user3), 0);
        assertEq(funding.bets1(experimentId, user3), 0);
    }

    function testAdminDevCanReturnBets() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        // User1 bets
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userBet(experimentId, 50 * 10 ** 6, 0);

        // admin_dev returns bet
        address[] memory users = new address[](1);
        users[0] = user1;

        vm.prank(admin2); // admin2 is admin_dev
        funding.adminReturnBet(experimentId, users);

        assertEq(funding.bets0(experimentId, user1), 0);
    }

    function testAdminCloseMarketRequiresAllBetsReturned() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        // User1 bets
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userBet(experimentId, 50 * 10 ** 6, 0);

        // Try to close market with bets still active - should fail
        vm.expectRevert("Must return all bets first");
        vm.prank(admin);
        funding.adminCloseMarket(experimentId);

        // Return bet
        address[] memory users = new address[](1);
        users[0] = user1;
        vm.prank(admin);
        funding.adminReturnBet(experimentId, users);

        // Now can close market
        vm.prank(admin);
        funding.adminCloseMarket(experimentId);
    }

    function testAdminCloseMarketRequiresAllDepositsReturned() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        // User1 deposits
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userDeposit(experimentId, 50 * 10 ** 6);

        // Try to close market with deposits still active - should fail
        vm.expectRevert("Must return all deposits first");
        vm.prank(admin);
        funding.adminCloseMarket(experimentId);

        // Return deposit
        vm.prank(user1);
        funding.userUndeposit(experimentId);

        // Now can close market
        vm.prank(admin);
        funding.adminCloseMarket(experimentId);
    }

    function testOnlyAdminCanSetResult() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        // Place bets
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userBet(experimentId, 50 * 10 ** 6, 0);

        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userBet(experimentId, 0, 50 * 10 ** 6);

        // admin_dev tries to set result - should fail
        vm.expectRevert("Only admin can call this function");
        vm.prank(admin2);
        funding.adminSetResult(experimentId, 0);

        // Regular user tries to set result - should fail
        vm.expectRevert("Only admin can call this function");
        vm.prank(user1);
        funding.adminSetResult(experimentId, 0);

        // Admin sets result - should succeed
        vm.prank(admin);
        funding.adminSetResult(experimentId, 0);
    }

    function testOnlyAdminCanCloseMarket() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        // admin_dev tries to close market - should fail
        vm.expectRevert("Only admin can call this function");
        vm.prank(admin2);
        funding.adminCloseMarket(experimentId);

        // Admin can close market
        vm.prank(admin);
        funding.adminCloseMarket(experimentId);
    }

    function testUserFundAndBetConvenienceFunction() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        // User1 funds and bets in one transaction
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userFundAndBet(
            experimentId,
            50 * 10 ** 6, // fund amount
            30 * 10 ** 6, // bet amount on outcome 0
            0 // bet amount on outcome 1
        );

        // Verify both deposit and bet were recorded
        assertEq(funding.getUserDeposit(experimentId, user1), 50 * 10 ** 6);
        assertEq(funding.bets0(experimentId, user1), 30 * 10 ** 6);
    }

    function testUserFundAndBetWithZeroFund() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        // User1 only bets (no funding)
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userFundAndBet(
            experimentId,
            0, // no fund amount
            30 * 10 ** 6, // bet amount on outcome 0
            0 // bet amount on outcome 1
        );

        // Verify only bet was recorded
        assertEq(funding.getUserDeposit(experimentId, user1), 0);
        assertEq(funding.bets0(experimentId, user1), 30 * 10 ** 6);
    }

    function testUserFundAndBetWithZeroBet() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        // User1 only funds (no betting)
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userFundAndBet(
            experimentId,
            50 * 10 ** 6, // fund amount
            0, // bet amount on outcome 0
            0 // bet amount on outcome 1
        );

        // Verify only deposit was recorded
        assertEq(funding.getUserDeposit(experimentId, user1), 50 * 10 ** 6);
        assertEq(funding.bets0(experimentId, user1), 0);
    }

    function testCannotBetOnClosedExperiment() public {
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        // Close the experiment
        vm.prank(admin);
        funding.adminClose(experimentId);

        // Try to bet on closed experiment - should fail
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.expectRevert("Experiment is closed");
        vm.prank(user1);
        funding.userBet(experimentId, 50 * 10 ** 6, 0);
    }

    function testCompleteSuccessPath() public {
        // Admin creates experiment
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        // Users deposit to fund experiment
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userDeposit(experimentId, 60 * 10 ** 6);

        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userDeposit(experimentId, 80 * 10 ** 6);

        // Users place bets
        vm.prank(user1);
        funding.userBet(experimentId, 40 * 10 ** 6, 0);

        vm.prank(user2);
        funding.userBet(experimentId, 0, 60 * 10 ** 6);

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
        assertEq(token.balanceOf(user1), user1BalanceBefore + 100 * 10 ** 6);
    }

    function testCompleteFailurePath() public {
        // Admin creates experiment
        vm.prank(admin);
        uint256 experimentId = funding.adminCreateExperiment(
            100 * 10 ** 6,
            500 * 10 ** 6
        );

        // Users deposit
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.userDeposit(experimentId, 50 * 10 ** 6);

        // Users place bets
        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.userBet(experimentId, 30 * 10 ** 6, 0);

        // Admin decides to cancel experiment
        // First refund deposits
        address[] memory depositors = new address[](1);
        depositors[0] = user1;
        vm.prank(admin);
        funding.adminRefund(experimentId, depositors);

        // Then return bets
        address[] memory bettors = new address[](1);
        bettors[0] = user2;
        vm.prank(admin);
        funding.adminReturnBet(experimentId, bettors);

        // Finally close market
        vm.prank(admin);
        funding.adminCloseMarket(experimentId);

        // Verify experiment is closed
        (, , , bool open) = funding.getExperimentInfo(experimentId);
        assertFalse(open);
    }
}
