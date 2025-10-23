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

    function deposit(
        uint256 experimentId,
        uint256 amount
    ) public isOpen(experimentId) {
        // Hardcoding decimals for USDC
        require(amount > 1 * 10 ** 6, "Deposit must be greater than 1 USDC");

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

    function bet(
        uint256 experimentId,
        uint8 outcome,
        uint256 amount
    ) public isOpen(experimentId) {
        require(amount > 1 * 10 ** 6, "Bet must be greater than 1 USDC");
        require(outcome == 0 || outcome == 1, "Invalid outcome");
        Experiment storage experiment = experiments[experimentId];
        require(experiment.bettingOutcome == 255, "Betting closed");

        require(
            token.transferFrom(msg.sender, address(this), amount),
            "Token transfer failed"
        );

        if (outcome == 0) {
            bets0[experimentId][msg.sender] += amount;
            experiment.totalBet0 += amount;
        } else {
            bets1[experimentId][msg.sender] += amount;
            experiment.totalBet1 += amount;
        }
    }

    function userFundAndBet(
        uint256 experimentId,
        uint256 fundAmount,
        uint8 betOutcome,
        uint256 betAmount
    ) external {
        if (fundAmount > 0) {
            deposit(experimentId, fundAmount);
        }
        if (betAmount > 0) {
            bet(experimentId, betOutcome, betAmount);
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
            block.timestamp >= experiment.experimentCreatedAt + 30 days,
            "Must wait 30 days"
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
    }

    function userClaimBetProfit(uint256 experimentId) external {
        Experiment storage experiment = experiments[experimentId];
        require(experiment.bettingOutcome != 255, "Result not set");

        uint256 payout;
        if (experiment.bettingOutcome == 0) {
            uint256 userBet = bets0[experimentId][msg.sender];
            require(userBet > 0, "No winning bet");
            payout =
                (userBet * (experiment.totalBet0 + experiment.totalBet1)) /
                experiment.totalBet0;
            bets0[experimentId][msg.sender] = 0;
        } else {
            uint256 userBet = bets1[experimentId][msg.sender];
            require(userBet > 0, "No winning bet");
            payout =
                (userBet * (experiment.totalBet0 + experiment.totalBet1)) /
                experiment.totalBet1;
            bets1[experimentId][msg.sender] = 0;
        }

        require(token.transfer(msg.sender, payout), "Transfer failed");
    }

    function adminCreateExperiment(
        uint256 costMin,
        uint256 costMax
    ) external onlyAdminPlusDev returns (uint256) {
        require(costMin > 0, "Minimum cost must be greater than 0");
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
        require(experiment.totalDeposited == 0, "Must return all funds first");
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
            }
        }
    }

    function adminCloseMarket(
        uint256 experimentId
    ) external onlyAdmin isOpen(experimentId) {
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
    }

    function adminSetResult(
        uint256 experimentId,
        uint8 result
    ) external onlyAdmin {
        Experiment storage experiment = experiments[experimentId];
        require(experiment.bettingOutcome == 255, "Result already set");
        require(result == 0 || result == 1, "Invalid result");
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
    }

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
