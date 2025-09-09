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
    address public immutable admin2;
    IERC20 public immutable token;
    uint256 public nextExperimentId;

    struct Experiment {
        uint256 costMin;
        uint256 costMax;
        uint256 totalDeposited;
        // closed can be triggered by the admin in two ways:
        // close and return funds, or close and withdraw funds
        bool closed;
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
        require(
            msg.sender == admin || msg.sender == admin2,
            "Only admin can call this function"
        );
        _;
    }

    modifier experimentExists(uint256 experimentId) {
        require(experimentId < nextExperimentId, "Experiment does not exist");
        _;
    }

    modifier notClosed(uint256 experimentId) {
        require(!experiments[experimentId].closed, "Experiment is closed");
        _;
    }

    constructor(address _admin, address _admin2, address _token) {
        require(_admin != address(0), "Admin address cannot be zero");
        require(_token != address(0), "Token address cannot be zero");
        admin = _admin;
        admin2 = _admin2;
        token = IERC20(_token);
        nextExperimentId = 0;
    }

    function createExperiment(
        uint256 costMin,
        uint256 costMax
    ) external onlyAdmin returns (uint256) {
        require(costMin > 0, "Minimum cost must be greater than 0");
        require(costMax >= costMin, "Maximum cost must be >= minimum cost");

        uint256 experimentId = nextExperimentId++;
        Experiment storage newExperiment = experiments[experimentId];
        newExperiment.costMin = costMin;
        newExperiment.costMax = costMax;
        newExperiment.totalDeposited = 0;
        newExperiment.closed = false;

        emit ExperimentCreated(experimentId, costMin, costMax);

        return experimentId;
    }

    function deposit(
        uint256 experimentId,
        uint256 amount
    ) external experimentExists(experimentId) notClosed(experimentId) {
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

    function undeposit(
        uint256 experimentId
    ) external experimentExists(experimentId) notClosed(experimentId) {
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
    ) external onlyAdmin notClosed(experimentId) {
        Experiment storage experiment = experiments[experimentId];
        // Without the > 0 check admin could accidentally close an experiment that doesn't exist yet
        require(experiment.totalDeposited > 0, "No funds to withdraw");
        require(
            experiment.totalDeposited >= experiment.costMin,
            "Minimum cost has not been reached"
        );
        uint256 amount = experiment.totalDeposited;
        experiment.totalDeposited = 0;
        experiment.closed = true;
        require(
            token.transfer(admin, amount),
            "Token transfer to admin failed"
        );

        emit AdminWithdraw(experimentId, amount);
    }
    function adminClose(
        uint256 experimentId
    ) external onlyAdmin notClosed(experimentId) {
        Experiment storage experiment = experiments[experimentId];
        require(experiment.totalDeposited == 0, "Must return all funds first");
        experiment.closed = true;
        emit AdminClose(experimentId);
    }

    function adminReturn(
        uint256 experimentId,
        address[] calldata depositors
    ) external onlyAdmin notClosed(experimentId) {
        Experiment storage experiment = experiments[experimentId];
        require(experiment.totalDeposited > 0, "No funds to return");
        require(depositors.length > 0, "Must specify at least one depositor");

        experiment.closed = true;

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
        experimentExists(experimentId)
        returns (
            uint256 costMin,
            uint256 costMax,
            uint256 totalDeposited,
            bool closed
        )
    {
        Experiment storage experiment = experiments[experimentId];
        return (
            experiment.costMin,
            experiment.costMax,
            experiment.totalDeposited,
            experiment.closed
        );
    }

    function getUserDeposit(
        uint256 experimentId,
        address user
    ) external view experimentExists(experimentId) returns (uint256) {
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
