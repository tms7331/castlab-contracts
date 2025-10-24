// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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

contract CastlabExperiment {
    address public immutable admin;
    address public immutable admin_dev;
    IERC20 public immutable token;
    uint256 public nextExperimentId;
    uint256 public constant MIN_AMOUNT = 1 * 10 ** 6;
    struct Experiment {
        uint256 costMin;
        uint256 costMax;
        uint256 totalDeposited;
        uint256 totalBet0;
        uint256 totalBet1;
        uint8 bettingOutcome;
        uint256 experimentCreatedAt;
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
    event BetWithdrawn(
        uint256 indexed experimentId,
        address indexed bettor,
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
    event MarketClosed(uint256 indexed experimentId);
    event AdminWithdraw(uint256 indexed experimentId, uint256 amount);
    event AdminClose(uint256 indexed experimentId);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call this function");
        _;
    }

    modifier onlyAdminPlusDev() {
        require(
            msg.sender == admin || msg.sender == admin_dev,
            "Only admin or admin_dev can call this function"
        );
        _;
    }

    modifier isOpen(uint256 experimentId) {
        require(experiments[experimentId].open, "Experiment is closed");
        _;
    }

    constructor(address _admin, address _admin_dev, address _token) {
        require(_admin != address(0), "Admin address cannot be zero");
        require(_admin_dev != address(0), "Admin_dev address cannot be zero");
        require(_token != address(0), "Token address cannot be zero");
        admin = _admin;
        admin_dev = _admin_dev;
        token = IERC20(_token);
        nextExperimentId = 0;
    }

    // External Functions

    function adminCreateExperiment(
        uint256 costMin,
        uint256 costMax
    ) external onlyAdminPlusDev returns (uint256) {
        require(
            costMin > MIN_AMOUNT,
            "Minimum cost must be greater than 1 USDC"
        );
        require(costMax >= costMin, "Maximum cost must be >= minimum cost");

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
        // Without the > 0 check admin could accidentally close an experiment that doesn't exist yet
        require(experiment.totalDeposited > 0, "No funds to withdraw");
        require(
            experiment.totalDeposited >= experiment.costMin,
            "Minimum cost has not been reached"
        );
        uint256 amount = experiment.totalDeposited;
        experiment.totalDeposited = 0;
        experiment.open = false;
        require(
            token.transfer(admin, amount),
            "Token transfer to admin failed"
        );

        emit AdminWithdraw(experimentId, amount);
    }
    function adminClose(
        uint256 experimentId
    ) external onlyAdminPlusDev isOpen(experimentId) {
        Experiment storage experiment = experiments[experimentId];
        require(
            experiment.totalDeposited == 0,
            "Must return all deposits first"
        );
        require(
            experiment.totalBet0 == 0 && experiment.totalBet1 == 0,
            "Must return all bets first"
        );

        experiment.open = false;
        emit AdminClose(experimentId);
    }

    function adminRefund(
        uint256 experimentId,
        address[] calldata depositors
    ) external onlyAdminPlusDev isOpen(experimentId) {
        Experiment storage experiment = experiments[experimentId];
        require(experiment.totalDeposited > 0, "No funds to return");
        require(depositors.length > 0, "Must specify at least one depositor");

        for (uint256 i = 0; i < depositors.length; i++) {
            address depositor = depositors[i];
            uint256 amount = deposits[experimentId][depositor];

            if (amount > 0) {
                deposits[experimentId][depositor] = 0;
                experiment.totalDeposited -= amount;

                require(
                    token.transfer(depositor, amount),
                    "Token transfer to depositor failed"
                );
                emit Undeposited(experimentId, depositor, amount);
            }
        }
    }

    function adminReturnBet(
        uint256 experimentId,
        address[] calldata users
    ) external onlyAdminPlusDev isOpen(experimentId) {
        Experiment storage experiment = experiments[experimentId];
        require(users.length > 0, "Must specify at least one user");

        for (uint256 i = 0; i < users.length; i++) {
            uint256 amount0 = bets0[experimentId][users[i]];
            uint256 amount1 = bets1[experimentId][users[i]];
            uint256 total = amount0 + amount1;

            if (total > 0) {
                bets0[experimentId][users[i]] = 0;
                bets1[experimentId][users[i]] = 0;
                experiment.totalBet0 -= amount0;
                experiment.totalBet1 -= amount1;
                require(token.transfer(users[i], total), "Transfer failed");
                emit BetReturned(experimentId, users[i], total);
            }
        }
    }

    function adminSetResult(
        uint256 experimentId,
        uint8 result
    ) external onlyAdmin {
        require(result == 0 || result == 1, "Invalid result");

        Experiment storage experiment = experiments[experimentId];
        // Can only set result if experiment is closed
        require(!experiment.open, "Experiment is not closed");
        require(experiment.bettingOutcome == 255, "Result already set");
        require(
            experiment.totalBet0 > 0 || experiment.totalBet1 > 0,
            "No bets placed"
        );

        if (result == 0) {
            require(experiment.totalBet0 > 0, "Winning side has no bets");
        } else {
            require(experiment.totalBet1 > 0, "Winning side has no bets");
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
        Experiment storage experiment = experiments[experimentId];
        require(
            deposits[experimentId][msg.sender] > 0,
            "No deposits to withdraw"
        );

        uint256 amount = deposits[experimentId][msg.sender];
        deposits[experimentId][msg.sender] = 0;
        experiment.totalDeposited -= amount;

        require(token.transfer(msg.sender, amount), "Token transfer failed");

        emit Undeposited(experimentId, msg.sender, amount);
    }

    function userUnbet(uint256 experimentId) external {
        Experiment storage experiment = experiments[experimentId];
        require(
            block.timestamp >= experiment.experimentCreatedAt + 90 days,
            "Must wait 90 days"
        );
        require(experiment.bettingOutcome == 255, "Result already set");

        uint256 amount0 = bets0[experimentId][msg.sender];
        uint256 amount1 = bets1[experimentId][msg.sender];
        uint256 total = amount0 + amount1;
        require(total > 0, "No bets to withdraw");

        bets0[experimentId][msg.sender] = 0;
        bets1[experimentId][msg.sender] = 0;
        experiment.totalBet0 -= amount0;
        experiment.totalBet1 -= amount1;

        require(token.transfer(msg.sender, total), "Transfer failed");

        emit BetWithdrawn(experimentId, msg.sender, total);
    }

    function userClaimBetProfit(uint256 experimentId) external {
        Experiment storage experiment = experiments[experimentId];
        require(experiment.bettingOutcome != 255, "Result not set");

        uint256 payout;
        if (experiment.bettingOutcome == 0) {
            uint256 userBetAmount = bets0[experimentId][msg.sender];
            require(userBetAmount > 0, "No winning bet");
            payout =
                (userBetAmount *
                    (experiment.totalBet0 + experiment.totalBet1)) /
                experiment.totalBet0;
            bets0[experimentId][msg.sender] = 0;
        } else {
            uint256 userBetAmount = bets1[experimentId][msg.sender];
            require(userBetAmount > 0, "No winning bet");
            payout =
                (userBetAmount *
                    (experiment.totalBet0 + experiment.totalBet1)) /
                experiment.totalBet1;
            bets1[experimentId][msg.sender] = 0;
        }

        require(token.transfer(msg.sender, payout), "Transfer failed");

        emit BetProfitClaimed(experimentId, msg.sender, payout);
    }

    // Public Functions

    function userDeposit(
        uint256 experimentId,
        uint256 amount
    ) public isOpen(experimentId) {
        // Hardcoding decimals for USDC
        require(amount > 1 * MIN_AMOUNT, "Deposit must be greater than 1 USDC");

        Experiment storage experiment = experiments[experimentId];

        require(
            experiment.totalDeposited + amount <= experiment.costMax,
            "Deposit would exceed maximum cost"
        );

        require(
            token.transferFrom(msg.sender, address(this), amount),
            "Token transfer failed"
        );
        deposits[experimentId][msg.sender] += amount;
        experiment.totalDeposited += amount;

        emit Deposited(experimentId, msg.sender, amount);
    }

    function userBet(
        uint256 experimentId,
        uint256 betAmount0,
        uint256 betAmount1
    ) public isOpen(experimentId) {
        uint256 totalAmount = betAmount0 + betAmount1;
        require(totalAmount > 0, "Must bet on at least one outcome");
        require(
            betAmount0 == 0 || betAmount0 > MIN_AMOUNT,
            "Bet on outcome 0 must be 0 or greater than 1 USDC"
        );
        require(
            betAmount1 == 0 || betAmount1 > MIN_AMOUNT,
            "Bet on outcome 1 must be 0 or greater than 1 USDC"
        );

        Experiment storage experiment = experiments[experimentId];
        require(experiment.bettingOutcome == 255, "Betting closed");

        require(
            token.transferFrom(msg.sender, address(this), totalAmount),
            "Token transfer failed"
        );

        if (betAmount0 > 0) {
            bets0[experimentId][msg.sender] += betAmount0;
            experiment.totalBet0 += betAmount0;
            emit BetPlaced(experimentId, msg.sender, 0, betAmount0);
        }

        if (betAmount1 > 0) {
            bets1[experimentId][msg.sender] += betAmount1;
            experiment.totalBet1 += betAmount1;
            emit BetPlaced(experimentId, msg.sender, 1, betAmount1);
        }
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
            bool open
        )
    {
        Experiment storage experiment = experiments[experimentId];
        return (
            experiment.costMin,
            experiment.costMax,
            experiment.totalDeposited,
            experiment.open
        );
    }

    function getUserDeposit(
        uint256 experimentId,
        address user
    ) external view returns (uint256) {
        return deposits[experimentId][user];
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
}
