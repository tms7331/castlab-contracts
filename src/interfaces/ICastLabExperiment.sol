// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface ICastLabExperiment {
    // === Events ===
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
    event BetPlaced(
        uint256 indexed experimentId,
        address indexed bettor,
        uint8 outcome,
        uint256 amount
    );
    event BetReturned(
        uint256 indexed experimentId,
        address indexed bettor,
        uint256 amount
    );
    event BetProfitClaimed(
        uint256 indexed experimentId,
        address indexed winner,
        uint256 payout
    );
    event ResultSet(uint256 indexed experimentId, uint8 result);
    event AdminWithdraw(uint256 indexed experimentId, uint256 amount);
    event AdminClose(uint256 indexed experimentId);

    // === Errors ===
    error OnlyAdmin();
    error OnlyAdminOrAdminDev();
    error ExperimentClosed();
    error ZeroAddress();
    error MinCostTooLow();
    error MaxCostBelowMinCost();
    error MinCostNotReached();
    error TokenTransferFailed();
    error MustReturnAllDepositsFirst();
    error MustReturnAllBetsFirst();
    error InvalidResult();
    error ExperimentNotClosed();
    error ResultAlreadySet();
    error WinningSideHasNoBets();
    error DepositBelowMinimum();
    error DepositExceedsMaxCost();
    error MustWait60Days();
    error ResultNotSet();
    error NoWinningBet();
    error BettingClosed();
    error BetBelowMinimum();

    // === Data ===
    struct Experiment {
        uint256 costMin;
        uint256 costMax;
        uint256 totalDeposited;
        uint256 totalBet0;
        uint256 totalBet1;
        uint256 experimentCreatedAt;
        uint8 bettingOutcome;
        bool open;
    }

    // === Functions ===

    // Admin
    function adminCreateExperiment(uint256 costMin, uint256 costMax) external returns (uint256);
    function adminWithdraw(uint256 experimentId) external;
    function adminClose(uint256 experimentId) external;
    function adminRefund(uint256 experimentId, address[] calldata depositors) external;
    function adminReturnBet(uint256 experimentId, address[] calldata users) external;
    function adminSetResult(uint256 experimentId, uint8 result) external;

    // User
    function userDeposit(uint256 experimentId, uint256 amount) external;
    function userBet(uint256 experimentId, uint256 betAmount0, uint256 betAmount1) external;
    function userUndeposit(uint256 experimentId) external;
    function userUnbet(uint256 experimentId) external;
    function userClaimBetProfit(uint256 experimentId) external returns (uint256);

    // View
    function getExperimentInfo(uint256 experimentId) external view returns (Experiment memory);
    function getUserPosition(uint256 experimentId, address user) external view returns (uint256 depositAmount, uint256 betAmount0, uint256 betAmount1);
    function getUserExperiments(address user) external view returns (uint256[] memory experimentIds, uint256[] memory depositAmounts);
}
