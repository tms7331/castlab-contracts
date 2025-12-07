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
    function adminCreateExperiment(uint256 costMin, uint256 costMax) external returns (uint256);
    function adminWithdraw(uint256 experimentId) external;
    function adminClose(uint256 experimentId) external;
    function adminRefund(uint256 experimentId, address[] calldata depositors) external;
    function adminReturnBet(uint256 experimentId, address[] calldata users) external;
    function adminSetResult(uint256 experimentId, uint8 result) external;
}
