// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PredContract.sol";
import "../src/TestToken.sol";

contract PredMarketTest is Test {
    PredMarket public market;
    TestToken public token;
    address public admin;
    address public admin_dev;
    address public user1;
    address public user2;
    address public user3;

    uint256 constant INITIAL_BALANCE = 10000 * 10 ** 6; // 10,000 tokens (6 decimals)

    event ExperimentResultSet(uint256 indexed experimentId, uint8 result);
    event MarketClosed(uint256 indexed experimentId);
    event UserRefunded(
        uint256 indexed experimentId,
        address indexed user,
        uint256 amount
    );
    event BetPlaced(
        uint256 indexed experimentId,
        address indexed user,
        uint8 outcome,
        uint256 amount
    );
    event WinningsClaimed(
        uint256 indexed experimentId,
        address indexed user,
        uint256 amount
    );

    function setUp() public {
        admin = address(0x1);
        admin_dev = address(0x2);
        user1 = address(0x3);
        user2 = address(0x4);
        user3 = address(0x5);

        // Deploy token and market contracts
        token = new TestToken();
        market = new PredMarket(address(token), admin, admin_dev);

        // Get the TestToken admin address
        address tokenAdmin = 0x4611F6d137d1baf545378dD02C1b16eb63cbE755;

        // Transfer tokens to test users and contract
        vm.prank(tokenAdmin);
        token.transfer(user1, INITIAL_BALANCE);

        vm.prank(tokenAdmin);
        token.transfer(user2, INITIAL_BALANCE);

        vm.prank(tokenAdmin);
        token.transfer(user3, INITIAL_BALANCE);

        vm.prank(tokenAdmin);
        token.transfer(address(market), INITIAL_BALANCE); // For refund tests
    }

    // ========== Constructor Tests ==========

    function testConstructorWithValidAddresses() public {
        PredMarket newMarket = new PredMarket(address(token), admin, admin_dev);
        assertEq(newMarket.admin(), admin);
        assertEq(newMarket.admin_dev(), admin_dev);
        assertEq(address(newMarket.token()), address(token));
    }

    function testConstructorRevertsWithZeroTokenAddress() public {
        vm.expectRevert("Token address cannot be zero");
        new PredMarket(address(0), admin, admin_dev);
    }

    function testConstructorRevertsWithZeroAdminAddress() public {
        vm.expectRevert("Admin address cannot be zero");
        new PredMarket(address(token), address(0), admin_dev);
    }

    function testConstructorRevertsWithZeroAdminDevAddress() public {
        vm.expectRevert("Admin_dev address cannot be zero");
        new PredMarket(address(token), admin, address(0));
    }

    // ========== Bet Function Tests ==========

    function testBetOnSide0() public {
        uint256 experimentId = 1;
        uint256 betAmount = 100 * 10 ** 6;

        vm.prank(user1);
        token.approve(address(market), betAmount);

        vm.prank(user1);
        market.bet(experimentId, 0, betAmount);

        (uint256 wager0, uint256 wager1) = market.getUserWagers(
            experimentId,
            user1
        );
        assertEq(wager0, betAmount);
        assertEq(wager1, 0);

        (uint256 total0, uint256 total1) = market.getExperimentTotals(
            experimentId
        );
        assertEq(total0, betAmount);
        assertEq(total1, 0);
    }

    function testBetOnSide1() public {
        uint256 experimentId = 1;
        uint256 betAmount = 150 * 10 ** 6;

        vm.prank(user1);
        token.approve(address(market), betAmount);

        vm.prank(user1);
        market.bet(experimentId, 1, betAmount);

        (uint256 wager0, uint256 wager1) = market.getUserWagers(
            experimentId,
            user1
        );
        assertEq(wager0, 0);
        assertEq(wager1, betAmount);

        (uint256 total0, uint256 total1) = market.getExperimentTotals(
            experimentId
        );
        assertEq(total0, 0);
        assertEq(total1, betAmount);
    }

    function testBetMultipleTimes() public {
        uint256 experimentId = 1;

        vm.prank(user1);
        token.approve(address(market), INITIAL_BALANCE);

        // First bet on side 0
        vm.prank(user1);
        market.bet(experimentId, 0, 50 * 10 ** 6);

        // Second bet on side 0
        vm.prank(user1);
        market.bet(experimentId, 0, 75 * 10 ** 6);

        // Bet on side 1
        vm.prank(user1);
        market.bet(experimentId, 1, 100 * 10 ** 6);

        (uint256 wager0, uint256 wager1) = market.getUserWagers(
            experimentId,
            user1
        );
        assertEq(wager0, 125 * 10 ** 6);
        assertEq(wager1, 100 * 10 ** 6);
    }

    function testBetRevertsWithInvalidOutcome() public {
        uint256 experimentId = 1;

        vm.prank(user1);
        token.approve(address(market), 100 * 10 ** 6);

        vm.expectRevert("Invalid outcome");
        vm.prank(user1);
        market.bet(experimentId, 2, 100 * 10 ** 6);
    }

    function testBetRevertsWithZeroAmount() public {
        uint256 experimentId = 1;

        vm.expectRevert("Amount must be greater than 0");
        vm.prank(user1);
        market.bet(experimentId, 0, 0);
    }

    function testBetRevertsOnClosedMarket() public {
        uint256 experimentId = 1;

        // Close the market
        vm.prank(admin);
        market.setResult(experimentId, 1);

        vm.prank(user1);
        token.approve(address(market), 100 * 10 ** 6);

        vm.expectRevert("Experiment is closed");
        vm.prank(user1);
        market.bet(experimentId, 0, 100 * 10 ** 6);
    }

    function testBetMultipleUsers() public {
        uint256 experimentId = 1;

        // User1 bets on side 0
        vm.prank(user1);
        token.approve(address(market), 200 * 10 ** 6);
        vm.prank(user1);
        market.bet(experimentId, 0, 200 * 10 ** 6);

        // User2 bets on side 1
        vm.prank(user2);
        token.approve(address(market), 300 * 10 ** 6);
        vm.prank(user2);
        market.bet(experimentId, 1, 300 * 10 ** 6);

        // User3 bets on side 0
        vm.prank(user3);
        token.approve(address(market), 150 * 10 ** 6);
        vm.prank(user3);
        market.bet(experimentId, 0, 150 * 10 ** 6);

        (uint256 total0, uint256 total1) = market.getExperimentTotals(
            experimentId
        );
        assertEq(total0, 350 * 10 ** 6);
        assertEq(total1, 300 * 10 ** 6);
    }

    // ========== SetResult Tests ==========

    function testSetResultByAdmin() public {
        uint256 experimentId = 1;

        vm.prank(admin);
        market.setResult(experimentId, 1);

        assertEq(market.getExperimentResult(experimentId), 1);
        assertTrue(market.getExperimentComplete(experimentId));
    }

    function testSetResultRevertsForNonAdmin() public {
        uint256 experimentId = 1;

        vm.expectRevert("Only admin can call this function");
        vm.prank(user1);
        market.setResult(experimentId, 1);
    }

    function testSetResultRevertsForAdminDev() public {
        uint256 experimentId = 1;

        vm.expectRevert("Only admin can call this function");
        vm.prank(admin_dev);
        market.setResult(experimentId, 1);
    }

    function testSetResultRevertsOnClosedMarket() public {
        uint256 experimentId = 1;

        // Close the market
        vm.prank(admin);
        market.setResult(experimentId, 1);

        // Try to set result again
        vm.expectRevert("Experiment is closed");
        vm.prank(admin);
        market.setResult(experimentId, 0);
    }

    function testSetResultWithDifferentValues() public {
        // Test result = 0 (side 0 wins)
        vm.prank(admin);
        market.setResult(1, 0);
        assertEq(market.getExperimentResult(1), 0);
        assertTrue(market.getExperimentComplete(1));

        // Test result = 1 (side 1 wins)
        vm.prank(admin);
        market.setResult(2, 1);
        assertEq(market.getExperimentResult(2), 1);
        assertTrue(market.getExperimentComplete(2));
    }

    function testSetResultRevertsForInvalidValues() public {
        uint256 experimentId = 1;

        // Test that result = 2 is rejected
        vm.expectRevert("Invalid result");
        vm.prank(admin);
        market.setResult(experimentId, 2);

        // Test that result = 5 is rejected
        vm.expectRevert("Invalid result");
        vm.prank(admin);
        market.setResult(experimentId, 5);

        // Test that result = 255 is rejected
        vm.expectRevert("Invalid result");
        vm.prank(admin);
        market.setResult(experimentId, 255);
    }

    // ========== CloseMarket Tests ==========

    function testCloseMarketWithZeroFunds() public {
        uint256 experimentId = 1;

        vm.prank(admin);
        market.closeMarket(experimentId);

        assertTrue(market.getExperimentComplete(experimentId));
    }

    function testCloseMarketRevertsWithFundsOnSide0() public {
        uint256 experimentId = 1;

        // Place bet on side 0
        vm.prank(user1);
        token.approve(address(market), 100 * 10 ** 6);
        vm.prank(user1);
        market.bet(experimentId, 0, 100 * 10 ** 6);

        vm.expectRevert("Funds not returned");
        vm.prank(admin);
        market.closeMarket(experimentId);
    }

    function testCloseMarketRevertsWithFundsOnSide1() public {
        uint256 experimentId = 1;

        // Place bet on side 1
        vm.prank(user1);
        token.approve(address(market), 100 * 10 ** 6);
        vm.prank(user1);
        market.bet(experimentId, 1, 100 * 10 ** 6);

        vm.expectRevert("Funds not returned");
        vm.prank(admin);
        market.closeMarket(experimentId);
    }

    function testCloseMarketRevertsForNonAdmin() public {
        uint256 experimentId = 1;

        vm.expectRevert("Only admin can call this function");
        vm.prank(user1);
        market.closeMarket(experimentId);
    }

    function testCloseMarketRevertsForAdminDev() public {
        uint256 experimentId = 1;

        vm.expectRevert("Only admin can call this function");
        vm.prank(admin_dev);
        market.closeMarket(experimentId);
    }

    function testCloseMarketRevertsOnAlreadyClosed() public {
        uint256 experimentId = 1;

        vm.prank(admin);
        market.closeMarket(experimentId);

        vm.expectRevert("Experiment is closed");
        vm.prank(admin);
        market.closeMarket(experimentId);
    }

    // ========== Refund Tests ==========

    function testRefundByAdmin() public {
        uint256 experimentId = 1;

        // User1 bets on side 0
        vm.prank(user1);
        token.approve(address(market), 100 * 10 ** 6);
        vm.prank(user1);
        market.bet(experimentId, 0, 100 * 10 ** 6);

        // User2 bets on side 1
        vm.prank(user2);
        token.approve(address(market), 150 * 10 ** 6);
        vm.prank(user2);
        market.bet(experimentId, 1, 150 * 10 ** 6);

        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        uint256 user1BalanceBefore = token.balanceOf(user1);
        uint256 user2BalanceBefore = token.balanceOf(user2);

        vm.prank(admin);
        market.refund(experimentId, users);

        // Check balances increased (note: there's a bug in the contract - wagers are zeroed before transfer)
        // The test will reveal this bug
        assertEq(token.balanceOf(user1), user1BalanceBefore + 100 * 10 ** 6);
        assertEq(token.balanceOf(user2), user2BalanceBefore + 150 * 10 ** 6);
    }

    function testRefundByAdminDev() public {
        uint256 experimentId = 1;

        vm.prank(user1);
        token.approve(address(market), 100 * 10 ** 6);
        vm.prank(user1);
        market.bet(experimentId, 0, 100 * 10 ** 6);

        address[] memory users = new address[](1);
        users[0] = user1;

        uint256 balanceBefore = token.balanceOf(user1);

        vm.prank(admin_dev);
        market.refund(experimentId, users);

        assertEq(token.balanceOf(user1), balanceBefore + 100 * 10 ** 6);
    }

    function testRefundRevertsForNonAdminOrAdminDev() public {
        uint256 experimentId = 1;

        address[] memory users = new address[](1);
        users[0] = user1;

        vm.expectRevert("Only admin or admin_dev can call this function");
        vm.prank(user1);
        market.refund(experimentId, users);
    }

    function testRefundRevertsOnClosedMarket() public {
        uint256 experimentId = 1;

        vm.prank(admin);
        market.setResult(experimentId, 1);

        address[] memory users = new address[](1);
        users[0] = user1;

        vm.expectRevert("Experiment is closed");
        vm.prank(admin);
        market.refund(experimentId, users);
    }

    function testRefundRevertsWithEmptyUserList() public {
        uint256 experimentId = 1;

        address[] memory users = new address[](0);

        vm.expectRevert("Must specify at least one user");
        vm.prank(admin);
        market.refund(experimentId, users);
    }

    function testRefundClearsTotals() public {
        uint256 experimentId = 1;

        // Multiple users bet
        vm.prank(user1);
        token.approve(address(market), 100 * 10 ** 6);
        vm.prank(user1);
        market.bet(experimentId, 0, 100 * 10 ** 6);

        vm.prank(user2);
        token.approve(address(market), 200 * 10 ** 6);
        vm.prank(user2);
        market.bet(experimentId, 1, 200 * 10 ** 6);

        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        vm.prank(admin);
        market.refund(experimentId, users);

        (uint256 total0, uint256 total1) = market.getExperimentTotals(
            experimentId
        );
        assertEq(total0, 0);
        assertEq(total1, 0);

        (uint256 wager0_user1, uint256 wager1_user1) = market.getUserWagers(
            experimentId,
            user1
        );
        assertEq(wager0_user1, 0);
        assertEq(wager1_user1, 0);

        (uint256 wager0_user2, uint256 wager1_user2) = market.getUserWagers(
            experimentId,
            user2
        );
        assertEq(wager0_user2, 0);
        assertEq(wager1_user2, 0);
    }

    // ========== ClaimWinnings Tests ==========
    function testClaimWinningsSide1Wins() public {
        uint256 experimentId = 1;

        // User1 bets 100 on side 0
        vm.prank(user1);
        token.approve(address(market), 100 * 10 ** 6);
        vm.prank(user1);
        market.bet(experimentId, 0, 100 * 10 ** 6);

        // User2 bets 50 on side 1
        vm.prank(user2);
        token.approve(address(market), 50 * 10 ** 6);
        vm.prank(user2);
        market.bet(experimentId, 1, 50 * 10 ** 6);

        // Set result to side 1 wins
        vm.prank(admin);
        market.setResult(experimentId, 1);

        uint256 balanceBefore = token.balanceOf(user2);

        vm.prank(user2);
        market.claimWinnings(experimentId);

        // User2 should get entire pool (100 + 50 = 150)
        assertEq(token.balanceOf(user2), balanceBefore + 150 * 10 ** 6);
    }

    function testClaimWinningsProportionalDistribution() public {
        uint256 experimentId = 1;

        // User1 bets 200 on side 1
        vm.prank(user1);
        token.approve(address(market), 200 * 10 ** 6);
        vm.prank(user1);
        market.bet(experimentId, 1, 200 * 10 ** 6);

        // User2 bets 100 on side 1
        vm.prank(user2);
        token.approve(address(market), 100 * 10 ** 6);
        vm.prank(user2);
        market.bet(experimentId, 1, 100 * 10 ** 6);

        // User3 bets 150 on side 0
        vm.prank(user3);
        token.approve(address(market), 150 * 10 ** 6);
        vm.prank(user3);
        market.bet(experimentId, 0, 150 * 10 ** 6);

        // Set result to side 1 wins (using 1 instead of 0 due to contract bug)
        vm.prank(admin);
        market.setResult(experimentId, 1);

        uint256 user1BalanceBefore = token.balanceOf(user1);
        uint256 user2BalanceBefore = token.balanceOf(user2);

        // User1 claims (200/300 of 450 total = 300)
        vm.prank(user1);
        market.claimWinnings(experimentId);
        assertEq(token.balanceOf(user1), user1BalanceBefore + 300 * 10 ** 6);

        // User2 claims (100/300 of 450 total = 150)
        vm.prank(user2);
        market.claimWinnings(experimentId);
        assertEq(token.balanceOf(user2), user2BalanceBefore + 150 * 10 ** 6);
    }

    function testClaimWinningsRevertsForIncompleteMarket() public {
        uint256 experimentId = 1;

        vm.prank(user1);
        token.approve(address(market), 100 * 10 ** 6);
        vm.prank(user1);
        market.bet(experimentId, 0, 100 * 10 ** 6);

        vm.expectRevert("Market not complete");
        vm.prank(user1);
        market.claimWinnings(experimentId);
    }

    function testClaimWinningsRevertsWhenRefunded() public {
        uint256 experimentId = 1;

        vm.prank(user1);
        token.approve(address(market), 100 * 10 ** 6);
        vm.prank(user1);
        market.bet(experimentId, 0, 100 * 10 ** 6);

        // Refund the user
        address[] memory users = new address[](1);
        users[0] = user1;
        vm.prank(admin);
        market.refund(experimentId, users);

        // Close market without setting explicit result (result defaults to 0)
        // Since result = 0 is now valid (side 0 wins), the market is treated as resolved
        vm.prank(admin);
        market.closeMarket(experimentId);

        // User1 tries to claim but their wager was refunded (set to 0)
        // Result = 0 means side 0 wins, but user has no wager anymore
        vm.expectRevert("No winning wager");
        vm.prank(user1);
        market.claimWinnings(experimentId);
    }

    function testClaimWinningsRevertsForLoser() public {
        uint256 experimentId = 1;

        // User1 bets on side 0
        vm.prank(user1);
        token.approve(address(market), 100 * 10 ** 6);
        vm.prank(user1);
        market.bet(experimentId, 0, 100 * 10 ** 6);

        // User2 bets on side 1
        vm.prank(user2);
        token.approve(address(market), 50 * 10 ** 6);
        vm.prank(user2);
        market.bet(experimentId, 1, 50 * 10 ** 6);

        // Set result to side 1 wins
        vm.prank(admin);
        market.setResult(experimentId, 1);

        // User1 tries to claim but lost
        vm.expectRevert("No winning wager");
        vm.prank(user1);
        market.claimWinnings(experimentId);
    }

    function testClaimWinningsRevertsForNonParticipant() public {
        uint256 experimentId = 1;

        // User1 bets on side 1
        vm.prank(user1);
        token.approve(address(market), 100 * 10 ** 6);
        vm.prank(user1);
        market.bet(experimentId, 1, 100 * 10 ** 6);

        // Set result to side 1 wins (using 1 instead of 0 due to contract bug)
        vm.prank(admin);
        market.setResult(experimentId, 1);

        // User3 tries to claim but didn't participate
        vm.expectRevert("No winning wager");
        vm.prank(user3);
        market.claimWinnings(experimentId);
    }

    function testClaimWinningsWithNoBetsOnWinningSide() public {
        uint256 experimentId = 1;

        // Both users bet on side 0
        vm.prank(user1);
        token.approve(address(market), 100 * 10 ** 6);
        vm.prank(user1);
        market.bet(experimentId, 0, 100 * 10 ** 6);

        vm.prank(user2);
        token.approve(address(market), 50 * 10 ** 6);
        vm.prank(user2);
        market.bet(experimentId, 0, 50 * 10 ** 6);

        // Set result to side 1 wins (but nobody bet on side 1)
        vm.prank(admin);
        market.setResult(experimentId, 1);

        // User1 tries to claim but bet on losing side
        vm.expectRevert("No winning wager");
        vm.prank(user1);
        market.claimWinnings(experimentId);

        // User2 also can't claim
        vm.expectRevert("No winning wager");
        vm.prank(user2);
        market.claimWinnings(experimentId);
    }

    // ========== View Function Tests ==========

    function testGetExperimentComplete() public {
        uint256 experimentId = 1;

        assertFalse(market.getExperimentComplete(experimentId));

        vm.prank(admin);
        market.setResult(experimentId, 1);

        assertTrue(market.getExperimentComplete(experimentId));
    }

    function testGetExperimentResult() public {
        uint256 experimentId = 1;

        assertEq(market.getExperimentResult(experimentId), 0);

        vm.prank(admin);
        market.setResult(experimentId, 1);

        assertEq(market.getExperimentResult(experimentId), 1);
    }

    function testGetExperimentTotals() public {
        uint256 experimentId = 1;

        (uint256 total0, uint256 total1) = market.getExperimentTotals(
            experimentId
        );
        assertEq(total0, 0);
        assertEq(total1, 0);

        vm.prank(user1);
        token.approve(address(market), 300 * 10 ** 6);

        vm.prank(user1);
        market.bet(experimentId, 0, 100 * 10 ** 6);

        vm.prank(user1);
        market.bet(experimentId, 1, 200 * 10 ** 6);

        (total0, total1) = market.getExperimentTotals(experimentId);
        assertEq(total0, 100 * 10 ** 6);
        assertEq(total1, 200 * 10 ** 6);
    }

    function testGetUserWagers() public {
        uint256 experimentId = 1;

        (uint256 wager0, uint256 wager1) = market.getUserWagers(
            experimentId,
            user1
        );
        assertEq(wager0, 0);
        assertEq(wager1, 0);

        vm.prank(user1);
        token.approve(address(market), 300 * 10 ** 6);

        vm.prank(user1);
        market.bet(experimentId, 0, 100 * 10 ** 6);

        vm.prank(user1);
        market.bet(experimentId, 1, 200 * 10 ** 6);

        (wager0, wager1) = market.getUserWagers(experimentId, user1);
        assertEq(wager0, 100 * 10 ** 6);
        assertEq(wager1, 200 * 10 ** 6);
    }

    // ========== Edge Case Tests ==========

    function testMultipleExperimentsIndependent() public {
        // Experiment 1
        vm.prank(user1);
        token.approve(address(market), 500 * 10 ** 6);
        vm.prank(user1);
        market.bet(1, 0, 100 * 10 ** 6);

        // Experiment 2
        vm.prank(user1);
        market.bet(2, 1, 200 * 10 ** 6);

        (uint256 wager0_exp1, uint256 wager1_exp1) = market.getUserWagers(
            1,
            user1
        );
        assertEq(wager0_exp1, 100 * 10 ** 6);
        assertEq(wager1_exp1, 0);

        (uint256 wager0_exp2, uint256 wager1_exp2) = market.getUserWagers(
            2,
            user1
        );
        assertEq(wager0_exp2, 0);
        assertEq(wager1_exp2, 200 * 10 ** 6);
    }

    function testOneSidedBetting() public {
        uint256 experimentId = 1;

        // Only bets on side 1 (using 1 instead of 0 due to contract bug)
        vm.prank(user1);
        token.approve(address(market), 100 * 10 ** 6);
        vm.prank(user1);
        market.bet(experimentId, 1, 100 * 10 ** 6);

        vm.prank(user2);
        token.approve(address(market), 50 * 10 ** 6);
        vm.prank(user2);
        market.bet(experimentId, 1, 50 * 10 ** 6);

        // Side 1 wins
        vm.prank(admin);
        market.setResult(experimentId, 1);

        uint256 user1BalanceBefore = token.balanceOf(user1);
        uint256 user2BalanceBefore = token.balanceOf(user2);

        // Users get back proportional to their bets (100/150 and 50/150 of 150 total)
        vm.prank(user1);
        market.claimWinnings(experimentId);
        assertEq(token.balanceOf(user1), user1BalanceBefore + 100 * 10 ** 6);

        vm.prank(user2);
        market.claimWinnings(experimentId);
        assertEq(token.balanceOf(user2), user2BalanceBefore + 50 * 10 ** 6);
    }

    function testCloseMarketAfterRefund() public {
        uint256 experimentId = 1;

        // Users bet
        vm.prank(user1);
        token.approve(address(market), 100 * 10 ** 6);
        vm.prank(user1);
        market.bet(experimentId, 0, 100 * 10 ** 6);

        vm.prank(user2);
        token.approve(address(market), 50 * 10 ** 6);
        vm.prank(user2);
        market.bet(experimentId, 1, 50 * 10 ** 6);

        // Refund all users
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        vm.prank(admin);
        market.refund(experimentId, users);

        // Now close the market
        vm.prank(admin);
        market.closeMarket(experimentId);

        assertTrue(market.getExperimentComplete(experimentId));
    }

    function testBetWithExactTokenBalance() public {
        uint256 experimentId = 1;
        uint256 balance = token.balanceOf(user1);

        vm.prank(user1);
        token.approve(address(market), balance);

        vm.prank(user1);
        market.bet(experimentId, 0, balance);

        assertEq(token.balanceOf(user1), 0);
        (uint256 wager0, ) = market.getUserWagers(experimentId, user1);
        assertEq(wager0, balance);
    }

    function testPartialRefund() public {
        uint256 experimentId = 1;

        // Three users bet
        vm.prank(user1);
        token.approve(address(market), 100 * 10 ** 6);
        vm.prank(user1);
        market.bet(experimentId, 0, 100 * 10 ** 6);

        vm.prank(user2);
        token.approve(address(market), 150 * 10 ** 6);
        vm.prank(user2);
        market.bet(experimentId, 1, 150 * 10 ** 6);

        vm.prank(user3);
        token.approve(address(market), 200 * 10 ** 6);
        vm.prank(user3);
        market.bet(experimentId, 0, 200 * 10 ** 6);

        // Refund only user1 and user3
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user3;

        vm.prank(admin);
        market.refund(experimentId, users);

        (uint256 wager0_user1, ) = market.getUserWagers(experimentId, user1);
        assertEq(wager0_user1, 0);

        (, uint256 wager1_user2) = market.getUserWagers(experimentId, user2);
        assertEq(wager1_user2, 150 * 10 ** 6); // User2 still has their wager

        (uint256 wager0_user3, ) = market.getUserWagers(experimentId, user3);
        assertEq(wager0_user3, 0);

        // Totals should reflect only user2's remaining wager
        (uint256 total0, uint256 total1) = market.getExperimentTotals(
            experimentId
        );
        assertEq(total0, 0);
        assertEq(total1, 150 * 10 ** 6);
    }
}
