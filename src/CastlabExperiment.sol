// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./interfaces/IERC20.sol";
import "./interfaces/ICastLabExperiment.sol";

contract CastlabExperiment is ICastLabExperiment {
    address public immutable ADMIN;
    address public immutable ADMIN_DEV;
    IERC20 public immutable TOKEN;
    
    // Hardcoding decimals for USDC
    uint256 public constant MIN_AMOUNT = 1e6;
    uint256 public nextExperimentId;

    mapping(uint256 => Experiment) public experiments;
    mapping(uint256 => mapping(address => uint256)) public deposits;
    mapping(uint256 => mapping(address => uint256)) public bets0;
    mapping(uint256 => mapping(address => uint256)) public bets1;

    modifier onlyAdmin() {
        require(msg.sender == ADMIN, OnlyAdmin());
        _;
    }

    modifier onlyAdminPlusDev() {
        require(msg.sender == ADMIN || msg.sender == ADMIN_DEV, OnlyAdminOrAdminDev());
        _;
    }

    modifier isOpen(uint256 experimentId) {
        // experimentId >= nextExperimentId is mostly unnecessary but doesn't hurt
        require(experimentId < nextExperimentId && experiments[experimentId].open, ExperimentClosed());
        _;
    }

    constructor(address _admin, address _adminDev, address _token) {
        require(_admin != address(0), ZeroAddress());
        require(_adminDev != address(0), ZeroAddress());
        require(_token != address(0), ZeroAddress());

        ADMIN = _admin;
        ADMIN_DEV = _adminDev;
        TOKEN = IERC20(_token);
    }

    // External Functions

    function adminCreateExperiment(
        uint256 costMin,
        uint256 costMax
    ) external onlyAdminPlusDev returns (uint256) {
        require(costMin >= MIN_AMOUNT, MinCostTooLow());
        require(costMax >= costMin, MaxCostBelowMinCost());

        uint256 experimentId = nextExperimentId++;
        Experiment storage newExperiment = experiments[experimentId];
        newExperiment.costMin = costMin;
        newExperiment.costMax = costMax;
        newExperiment.totalDeposited = 0;
        newExperiment.totalBet0 = 0;
        newExperiment.totalBet1 = 0;
        newExperiment.bettingOutcome = type(uint8).max;
        newExperiment.experimentCreatedAt = block.timestamp;
        newExperiment.open = true;

        emit ExperimentCreated(experimentId, costMin, costMax);
        return experimentId;
    }

    function adminWithdraw(
        uint256 experimentId
    ) external onlyAdmin isOpen(experimentId) {
        Experiment storage experiment = experiments[experimentId];
        require(experiment.totalDeposited >= experiment.costMin, MinCostNotReached());

        uint256 amount = experiment.totalDeposited;
        experiment.totalDeposited = 0;
        experiment.open = false;

        require(TOKEN.transfer(ADMIN, amount), TokenTransferFailed());
        
        emit AdminWithdraw(experimentId, amount);
    }
    function adminClose(
        uint256 experimentId
    ) external onlyAdminPlusDev isOpen(experimentId) {
        Experiment storage experiment = experiments[experimentId];

        require(experiment.totalDeposited == 0, MustReturnAllDepositsFirst());
        require(experiment.totalBet0 == 0 && experiment.totalBet1 == 0, MustReturnAllBetsFirst());

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
        require(result == 0 || result == 1, InvalidResult());

        Experiment storage experiment = experiments[experimentId];
        
        // These two constraints ensure it was a real experiment (only created
        // experiments will have bettingOutcome == type(uint8).max, and is closed for betting)
        require(!experiment.open, ExperimentNotClosed());
        require(experiment.bettingOutcome == type(uint8).max, ResultAlreadySet());

        // If winning side has no bets - we should refund everyone
        if (result == 0) {
            require(experiment.totalBet0 != 0, WinningSideHasNoBets());
        } else {
            require(experiment.totalBet1 != 0, WinningSideHasNoBets());
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
        require(block.timestamp >= experiment.experimentCreatedAt + 60 days, MustWait60Days());
        require(experiment.bettingOutcome == type(uint8).max, ResultAlreadySet());

        _returnBet(experimentId, msg.sender);
    }

    function userClaimBetProfit(uint256 experimentId) external returns (uint256) {
        Experiment storage experiment = experiments[experimentId];
        require(experiment.bettingOutcome != type(uint8).max, ResultNotSet());

        uint256 payout;
        if (experiment.bettingOutcome == 0) {
            uint256 userBetAmount = bets0[experimentId][msg.sender];
            require(userBetAmount != 0, NoWinningBet());
            payout = (userBetAmount * (experiment.totalBet0 + experiment.totalBet1)) / experiment.totalBet0;
            bets0[experimentId][msg.sender] = 0;
        } else {
            uint256 userBetAmount = bets1[experimentId][msg.sender];
            require(userBetAmount != 0, NoWinningBet());
            payout = (userBetAmount * (experiment.totalBet0 + experiment.totalBet1)) / experiment.totalBet1;
            bets1[experimentId][msg.sender] = 0;
        }

        require(TOKEN.transfer(msg.sender, payout), TokenTransferFailed());

        emit BetProfitClaimed(experimentId, msg.sender, payout);

        return payout;
    }

    // External View Functions
    function getExperimentInfo(uint256 experimentId) external view returns (Experiment memory)
    {
        return experiments[experimentId];
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

    function getUserExperiments(address user)
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
        require(amount >= MIN_AMOUNT, DepositBelowMinimum());

        Experiment storage experiment = experiments[experimentId];

        require(experiment.totalDeposited + amount <= experiment.costMax, DepositExceedsMaxCost());

        require(TOKEN.transferFrom(msg.sender, address(this), amount), TokenTransferFailed());

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

        require(TOKEN.transferFrom(msg.sender, address(this), totalAmount), TokenTransferFailed());

        if (betAmount0 > 0) {
            require(betAmount0 >= MIN_AMOUNT, BetBelowMinimum());
            bets0[experimentId][msg.sender] += betAmount0;
            experiment.totalBet0 += betAmount0;
            emit BetPlaced(experimentId, msg.sender, 0, betAmount0);
        }

        if (betAmount1 > 0) {
            require(betAmount1 >= MIN_AMOUNT, BetBelowMinimum());
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
            require(TOKEN.transfer(user, amount), TokenTransferFailed());
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
            require(TOKEN.transfer(user, total), TokenTransferFailed());
        }

        emit BetReturned(experimentId, user, total);
    }
}
