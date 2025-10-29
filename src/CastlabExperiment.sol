// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

// Custom Errors
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

contract CastlabExperiment {
    address public immutable ADMIN;
    address public immutable ADMIN_DEV;
    IERC20 public immutable TOKEN;
    // Hardcoding decimals for USDC
    uint256 public constant MIN_AMOUNT = 1 * 10 ** 6;
    uint256 public nextExperimentId;
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

    mapping(uint256 => Experiment) public experiments;
    mapping(uint256 => mapping(address => uint256)) public deposits;
    mapping(uint256 => mapping(address => uint256)) public bets0;
    mapping(uint256 => mapping(address => uint256)) public bets1;

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

    modifier onlyAdmin() {
        if (msg.sender != ADMIN) revert OnlyAdmin();
        _;
    }

    modifier onlyAdminPlusDev() {
        if (msg.sender != ADMIN && msg.sender != ADMIN_DEV)
            revert OnlyAdminOrAdminDev();
        _;
    }

    modifier isOpen(uint256 experimentId) {
        // experimentId >= nextExperimentId is mostly unnecessary but doesn't hurt -
        if (experimentId >= nextExperimentId || !experiments[experimentId].open)
            revert ExperimentClosed();
        _;
    }

    constructor(address _admin, address _adminDev, address _token) {
        if (_admin == address(0)) revert ZeroAddress();
        if (_adminDev == address(0)) revert ZeroAddress();
        if (_token == address(0)) revert ZeroAddress();
        ADMIN = _admin;
        ADMIN_DEV = _adminDev;
        TOKEN = IERC20(_token);
        nextExperimentId = 0;
    }

    // External Functions

    function adminCreateExperiment(
        uint256 costMin,
        uint256 costMax
    ) external onlyAdminPlusDev returns (uint256) {
        if (costMin < MIN_AMOUNT) revert MinCostTooLow();
        if (costMax < costMin) revert MaxCostBelowMinCost();

        uint256 experimentId = nextExperimentId++;
        Experiment storage newExperiment = experiments[experimentId];
        newExperiment.costMin = costMin;
        newExperiment.costMax = costMax;
        newExperiment.totalDeposited = 0;
        newExperiment.totalBet0 = 0;
        newExperiment.totalBet1 = 0;
        newExperiment.bettingOutcome = 255;
        newExperiment.experimentCreatedAt = block.timestamp;
        newExperiment.open = true;

        emit ExperimentCreated(experimentId, costMin, costMax);
        return experimentId;
    }

    function adminWithdraw(
        uint256 experimentId
    ) external onlyAdmin isOpen(experimentId) {
        Experiment storage experiment = experiments[experimentId];
        if (experiment.totalDeposited < experiment.costMin)
            revert MinCostNotReached();

        uint256 amount = experiment.totalDeposited;
        experiment.totalDeposited = 0;
        experiment.open = false;
        if (!TOKEN.transfer(ADMIN, amount)) revert TokenTransferFailed();

        emit AdminWithdraw(experimentId, amount);
    }
    function adminClose(
        uint256 experimentId
    ) external onlyAdminPlusDev isOpen(experimentId) {
        Experiment storage experiment = experiments[experimentId];
        if (experiment.totalDeposited != 0) revert MustReturnAllDepositsFirst();
        if (experiment.totalBet0 != 0 || experiment.totalBet1 != 0)
            revert MustReturnAllBetsFirst();

        experiment.open = false;
        emit AdminClose(experimentId);
    }

    function adminRefund(
        uint256 experimentId,
        address[] calldata depositors
    ) external onlyAdminPlusDev isOpen(experimentId) {
        for (uint256 i = 0; i < depositors.length; i++) {
            _returnDeposit(experimentId, depositors[i]);
        }
    }

    function adminReturnBet(
        uint256 experimentId,
        address[] calldata users
    ) external onlyAdminPlusDev {
        // admin can return bets even after experiment is closed
        for (uint256 i = 0; i < users.length; i++) {
            _returnBet(experimentId, users[i]);
        }
    }

    function adminSetResult(
        uint256 experimentId,
        uint8 result
    ) external onlyAdmin {
        if (result != 0 && result != 1) revert InvalidResult();

        Experiment storage experiment = experiments[experimentId];
        // These two constraints ensure it was a real experiment (only created
        // experiments will have bettingOutcome == 255, and is closed for betting)
        if (experiment.open) revert ExperimentNotClosed();
        if (experiment.bettingOutcome != 255) revert ResultAlreadySet();

        // If winning side has no bets - we should refund everyone
        if (result == 0) {
            if (experiment.totalBet0 == 0) revert WinningSideHasNoBets();
        } else {
            if (experiment.totalBet1 == 0) revert WinningSideHasNoBets();
        }

        experiment.bettingOutcome = result;

        emit ResultSet(experimentId, result);
    }

    function userFundAndBet(
        uint256 experimentId,
        uint256 fundAmount,
        uint256 betAmount0,
        uint256 betAmount1
    ) external {
        if (fundAmount > 0) {
            userDeposit(experimentId, fundAmount);
        }
        if (betAmount0 > 0 || betAmount1 > 0) {
            userBet(experimentId, betAmount0, betAmount1);
        }
    }

    function userUndeposit(uint256 experimentId) external isOpen(experimentId) {
        _returnDeposit(experimentId, msg.sender);
    }

    function userUnbet(uint256 experimentId) external {
        Experiment storage experiment = experiments[experimentId];
        if (block.timestamp < experiment.experimentCreatedAt + 60 days)
            revert MustWait60Days();
        if (experiment.bettingOutcome != 255) revert ResultAlreadySet();

        _returnBet(experimentId, msg.sender);
    }

    function userClaimBetProfit(
        uint256 experimentId
    ) external returns (uint256) {
        Experiment storage experiment = experiments[experimentId];
        if (experiment.bettingOutcome == 255) revert ResultNotSet();

        uint256 payout;
        if (experiment.bettingOutcome == 0) {
            uint256 userBetAmount = bets0[experimentId][msg.sender];
            if (userBetAmount == 0) revert NoWinningBet();
            payout =
                (userBetAmount *
                    (experiment.totalBet0 + experiment.totalBet1)) /
                experiment.totalBet0;
            bets0[experimentId][msg.sender] = 0;
        } else {
            uint256 userBetAmount = bets1[experimentId][msg.sender];
            if (userBetAmount == 0) revert NoWinningBet();
            payout =
                (userBetAmount *
                    (experiment.totalBet0 + experiment.totalBet1)) /
                experiment.totalBet1;
            bets1[experimentId][msg.sender] = 0;
        }

        if (!TOKEN.transfer(msg.sender, payout)) revert TokenTransferFailed();

        emit BetProfitClaimed(experimentId, msg.sender, payout);

        return payout;
    }

    // External View Functions
    function getExperimentInfo(
        uint256 experimentId
    )
        external
        view
        returns (
            uint256 costMin,
            uint256 costMax,
            uint256 totalDeposited,
            uint256 totalBet0,
            uint256 totalBet1,
            uint256 experimentCreatedAt,
            uint8 bettingOutcome,
            bool open
        )
    {
        Experiment storage experiment = experiments[experimentId];
        return (
            experiment.costMin,
            experiment.costMax,
            experiment.totalDeposited,
            experiment.totalBet0,
            experiment.totalBet1,
            experiment.experimentCreatedAt,
            experiment.bettingOutcome,
            experiment.open
        );
    }

    function getUserPosition(
        uint256 experimentId,
        address user
    )
        external
        view
        returns (uint256 depositAmount, uint256 betAmount0, uint256 betAmount1)
    {
        return (
            deposits[experimentId][user],
            bets0[experimentId][user],
            bets1[experimentId][user]
        );
    }

    function getUserExperiments(
        address user
    )
        external
        view
        returns (
            uint256[] memory experimentIds,
            uint256[] memory depositAmounts
        )
    {
        // First, count how many experiments the user has deposited to
        uint256 count = 0;
        for (uint256 i = 0; i < nextExperimentId; i++) {
            if (deposits[i][user] > 0) {
                count++;
            }
        }

        // Create arrays to store the results
        experimentIds = new uint256[](count);
        depositAmounts = new uint256[](count);

        // Fill the arrays
        uint256 index = 0;
        for (uint256 i = 0; i < nextExperimentId; i++) {
            if (deposits[i][user] > 0) {
                experimentIds[index] = i;
                depositAmounts[index] = deposits[i][user];
                index++;
            }
        }

        return (experimentIds, depositAmounts);
    }

    // Public Functions

    function userDeposit(
        uint256 experimentId,
        uint256 amount
    ) public isOpen(experimentId) {
        if (amount < MIN_AMOUNT) revert DepositBelowMinimum();

        Experiment storage experiment = experiments[experimentId];

        if (experiment.totalDeposited + amount > experiment.costMax)
            revert DepositExceedsMaxCost();

        if (!TOKEN.transferFrom(msg.sender, address(this), amount))
            revert TokenTransferFailed();

        deposits[experimentId][msg.sender] += amount;
        experiment.totalDeposited += amount;

        emit Deposited(experimentId, msg.sender, amount);
    }

    function userBet(
        uint256 experimentId,
        uint256 betAmount0,
        uint256 betAmount1
    ) public isOpen(experimentId) {
        Experiment storage experiment = experiments[experimentId];
        uint256 totalAmount = betAmount0 + betAmount1;

        if (!TOKEN.transferFrom(msg.sender, address(this), totalAmount))
            revert TokenTransferFailed();

        if (betAmount0 > 0) {
            if (betAmount0 < MIN_AMOUNT) revert BetBelowMinimum();
            bets0[experimentId][msg.sender] += betAmount0;
            experiment.totalBet0 += betAmount0;
            emit BetPlaced(experimentId, msg.sender, 0, betAmount0);
        }

        if (betAmount1 > 0) {
            if (betAmount1 < MIN_AMOUNT) revert BetBelowMinimum();
            bets1[experimentId][msg.sender] += betAmount1;
            experiment.totalBet1 += betAmount1;
            emit BetPlaced(experimentId, msg.sender, 1, betAmount1);
        }
    }

    // Internal Functions

    function _returnDeposit(uint256 experimentId, address user) internal {
        Experiment storage experiment = experiments[experimentId];
        uint256 amount = deposits[experimentId][user];

        if (amount > 0) {
            deposits[experimentId][user] = 0;
            experiment.totalDeposited -= amount;
            if (!TOKEN.transfer(user, amount)) revert TokenTransferFailed();
        }
        emit Undeposited(experimentId, user, amount);
    }

    function _returnBet(uint256 experimentId, address user) internal {
        // Note - inefficient for admin returns to have this here but keeps it simple
        Experiment storage experiment = experiments[experimentId];
        uint256 amount0 = bets0[experimentId][user];
        uint256 amount1 = bets1[experimentId][user];
        uint256 total = amount0 + amount1;
        if (total > 0) {
            bets0[experimentId][user] = 0;
            bets1[experimentId][user] = 0;
            experiment.totalBet0 -= amount0;
            experiment.totalBet1 -= amount1;
            if (!TOKEN.transfer(user, total)) revert TokenTransferFailed();
        }
        emit BetReturned(experimentId, user, total);
    }
}
