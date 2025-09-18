// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/ExperimentFunding.sol";
import "../src/TestToken.sol";

contract ExperimentFundingNewTest is Test {
    ExperimentFunding public funding;
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
        funding = new ExperimentFunding(admin, admin2, address(token));

        // Get the TestToken admin addresses
        address tokenAdmin1 = 0x4611F6d137d1baf545378dD02C1b16eb63cbE755;
        address tokenAdmin2 = 0xb306BA7A978906118542346327f3DEB93B5a3ca9;

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
        uint256 experimentId = funding.createExperiment(
            100 * 10 ** 6, // minCost: 100 USDC
            500 * 10 ** 6 // maxCost: 500 USDC
        );

        // User1 approves and deposits 50 USDC
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.deposit(experimentId, 50 * 10 ** 6);

        // User2 approves and deposits 75 USDC
        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.deposit(experimentId, 75 * 10 ** 6);

        // User3 approves and deposits 100 USDC
        vm.prank(user3);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user3);
        funding.deposit(experimentId, 100 * 10 ** 6);

        // Check total deposited is 225 USDC
        (, , uint256 totalDeposited, ) = funding.getExperimentInfo(
            experimentId
        );
        assertEq(totalDeposited, 225 * 10 ** 6);

        // User2 undeposits their 75 USDC
        uint256 user2BalanceBefore = token.balanceOf(user2);
        vm.prank(user2);
        funding.undeposit(experimentId);
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
        funding.adminReturn(experimentId, depositors);
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
        uint256 experimentId = funding.createExperiment(
            100 * 10 ** 6, // minCost: 100 USDC
            500 * 10 ** 6 // maxCost: 500 USDC
        );

        // User1 approves funding contract
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);

        // User1 deposits 60 USDC
        vm.prank(user1);
        funding.deposit(experimentId, 60 * 10 ** 6);
        assertEq(funding.getUserDeposit(experimentId, user1), 60 * 10 ** 6);

        // User1 undeposits the 60 USDC
        vm.prank(user1);
        funding.undeposit(experimentId);
        assertEq(funding.getUserDeposit(experimentId, user1), 0);

        // User1 redeposits 150 USDC (past minCost)
        vm.prank(user1);
        funding.deposit(experimentId, 150 * 10 ** 6);
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
        funding.undeposit(experimentId);

        // User1 also can't deposit anymore
        vm.expectRevert("Experiment is closed");
        vm.prank(user1);
        funding.deposit(experimentId, 10 * 10 ** 6);
    }

    function testMinimumDepositRequirement() public {
        // Admin creates experiment
        vm.prank(admin);
        uint256 experimentId = funding.createExperiment(
            100 * 10 ** 6, // minCost: 100 USDC
            500 * 10 ** 6 // maxCost: 500 USDC
        );

        // User1 approves funding contract
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);

        // Try to deposit exactly 1 USDC (1 * 10^6) - should fail
        vm.expectRevert("Deposit must be greater than 1 USDC");
        vm.prank(user1);
        funding.deposit(experimentId, 1 * 10 ** 6);

        // Try to deposit 0.5 USDC - should fail
        vm.expectRevert("Deposit must be greater than 1 USDC");
        vm.prank(user1);
        funding.deposit(experimentId, 0.5 * 10 ** 6);

        // Deposit 1.1 USDC - should succeed
        vm.prank(user1);
        funding.deposit(experimentId, 1.1 * 10 ** 6);
        assertEq(funding.getUserDeposit(experimentId, user1), 1.1 * 10 ** 6);
    }

    function testCannotExceedMaxCost() public {
        // Admin creates experiment
        vm.prank(admin);
        uint256 experimentId = funding.createExperiment(
            100 * 10 ** 6, // minCost: 100 USDC
            200 * 10 ** 6 // maxCost: 200 USDC
        );

        // User1 approves and deposits 150 USDC
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.deposit(experimentId, 150 * 10 ** 6);

        // User2 tries to deposit 60 USDC (would exceed max)
        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.expectRevert("Deposit would exceed maximum cost");
        vm.prank(user2);
        funding.deposit(experimentId, 60 * 10 ** 6);

        // User2 deposits exactly 50 USDC (reaches max)
        vm.prank(user2);
        funding.deposit(experimentId, 50 * 10 ** 6);

        (, , uint256 totalDeposited, ) = funding.getExperimentInfo(
            experimentId
        );
        assertEq(totalDeposited, 200 * 10 ** 6);
    }

    function testOnlyAdminCanCreateExperiment() public {
        // User1 tries to create experiment - should fail
        vm.expectRevert("Only admin or admin_dev can call this function");
        vm.prank(user1);
        funding.createExperiment(100 * 10 ** 6, 500 * 10 ** 6);

        // Admin1 creates experiment - should succeed
        vm.prank(admin);
        uint256 id1 = funding.createExperiment(100 * 10 ** 6, 500 * 10 ** 6);
        assertEq(id1, 0);

        // Admin2 creates experiment - should succeed
        vm.prank(admin2);
        uint256 id2 = funding.createExperiment(200 * 10 ** 6, 600 * 10 ** 6);
        assertEq(id2, 1);
    }

    function testAdminCannotWithdrawBelowMinCost() public {
        // Admin creates experiment
        vm.prank(admin);
        uint256 experimentId = funding.createExperiment(
            100 * 10 ** 6, // minCost: 100 USDC
            500 * 10 ** 6 // maxCost: 500 USDC
        );

        // User1 deposits 50 USDC (below minCost)
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.deposit(experimentId, 50 * 10 ** 6);

        // Admin tries to withdraw - should fail
        vm.expectRevert("Minimum cost has not been reached");
        vm.prank(admin);
        funding.adminWithdraw(experimentId);

        // User2 deposits 60 USDC (total now 110, above minCost)
        vm.prank(user2);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user2);
        funding.deposit(experimentId, 60 * 10 ** 6);

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
        uint256 exp1 = funding.createExperiment(100 * 10 ** 6, 500 * 10 ** 6);
        vm.prank(admin);
        uint256 exp2 = funding.createExperiment(200 * 10 ** 6, 600 * 10 ** 6);
        vm.prank(admin);
        uint256 exp3 = funding.createExperiment(300 * 10 ** 6, 700 * 10 ** 6);

        // User1 deposits to exp1 and exp3
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);

        vm.prank(user1);
        funding.deposit(exp1, 50 * 10 ** 6);

        vm.prank(user1);
        funding.deposit(exp3, 100 * 10 ** 6);

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
        uint256 experimentId = funding.createExperiment(
            100 * 10 ** 6, // minCost: 100 USDC
            500 * 10 ** 6 // maxCost: 500 USDC
        );

        // User1 deposits
        vm.prank(user1);
        token.approve(address(funding), INITIAL_BALANCE);
        vm.prank(user1);
        funding.deposit(experimentId, 50 * 10 ** 6);

        // Admin tries to close with funds still in - should fail
        vm.expectRevert("Must return all funds first");
        vm.prank(admin);
        funding.adminClose(experimentId);

        // User1 undeposits
        vm.prank(user1);
        funding.undeposit(experimentId);

        // Now admin can close
        vm.prank(admin);
        funding.adminClose(experimentId);

        (, , uint256 totalDeposited, bool open) = funding.getExperimentInfo(
            experimentId
        );
        assertEq(totalDeposited, 0);
        assertFalse(open);
    }
}
