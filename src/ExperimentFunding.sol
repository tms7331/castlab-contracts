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

contract ExperimentFunding {
    address public immutable admin;
    address public immutable admin_dev;
    IERC20 public immutable token;
    uint256 public nextExperimentId;

    struct Experiment {
        uint256 costMin;
        uint256 costMax;
        uint256 totalDeposited;
        // open indicates whether deposits/withdrawals are allowed
        // Admin can close the experiment by setting open to false via:
        // - adminWithdraw (after withdrawing funds)
        // - adminClose (after ensuring all funds returned)
        bool open;
    }

    mapping(uint256 => Experiment) public experiments;
    // Public mapping to track deposits: experimentId => depositor => amount
    mapping(uint256 => mapping(address => uint256)) public deposits;

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

    function createExperiment(
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
        newExperiment.open = true;

        emit ExperimentCreated(experimentId, costMin, costMax);

        return experimentId;
    }

    function deposit(
        uint256 experimentId,
        uint256 amount
    ) external isOpen(experimentId) {
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

    function undeposit(uint256 experimentId) external isOpen(experimentId) {
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
    ) external onlyAdmin isOpen(experimentId) {
        Experiment storage experiment = experiments[experimentId];
        require(experiment.totalDeposited == 0, "Must return all funds first");
        experiment.open = false;
        emit AdminClose(experimentId);
    }

    function adminReturn(
        uint256 experimentId,
        address[] calldata depositors
    ) external onlyAdmin isOpen(experimentId) {
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
