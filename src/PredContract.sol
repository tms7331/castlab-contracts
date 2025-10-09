// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// TODO - need to handle

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

contract PredMarket {
    struct Experiment {
        bool complete;
        uint8 result;
        uint256 totalSide0;
        uint256 totalSide1;
        mapping(address => uint256) wagers0;
        mapping(address => uint256) wagers1;
    }

    address public admin;
    address public admin_dev;
    mapping(uint256 => Experiment) public experiments;
    IERC20 public token;

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

    modifier isOpen(uint256 experimentId) {
        require(!experiments[experimentId].complete, "Experiment is closed");
        _;
    }

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

    constructor(address _token, address _admin, address _admin_dev) {
        require(_admin != address(0), "Admin address cannot be zero");
        require(_admin_dev != address(0), "Admin_dev address cannot be zero");
        require(_token != address(0), "Token address cannot be zero");
        admin = _admin;
        admin_dev = _admin_dev;
        token = IERC20(_token);
    }

    function setResult(
        uint256 experimentId,
        uint8 _result
    ) public onlyAdmin isOpen(experimentId) {
        require(_result == 0 || _result == 1, "Invalid result");
        experiments[experimentId].result = _result;
        experiments[experimentId].complete = true;
        emit ExperimentResultSet(experimentId, _result);
    }

    function closeMarket(
        uint256 experimentId
    ) public onlyAdmin isOpen(experimentId) {
        // Make sure all funds have been returned!
        require(
            experiments[experimentId].totalSide0 == 0,
            "Funds not returned"
        );
        require(
            experiments[experimentId].totalSide1 == 0,
            "Funds not returned"
        );
        experiments[experimentId].complete = true;
        emit MarketClosed(experimentId);
    }

    function refund(
        uint256 experimentId,
        address[] calldata _users
    ) public onlyAdminPlusDev isOpen(experimentId) {
        require(_users.length > 0, "Must specify at least one user");
        for (uint256 i = 0; i < _users.length; i++) {
            uint256 refundAmount = experiments[experimentId].wagers0[
                _users[i]
            ] + experiments[experimentId].wagers1[_users[i]];
            experiments[experimentId].totalSide0 -= experiments[experimentId]
                .wagers0[_users[i]];
            experiments[experimentId].totalSide1 -= experiments[experimentId]
                .wagers1[_users[i]];
            experiments[experimentId].wagers0[_users[i]] = 0;
            experiments[experimentId].wagers1[_users[i]] = 0;
            token.transfer(_users[i], refundAmount);
            emit UserRefunded(experimentId, _users[i], refundAmount);
        }
    }

    function bet(
        uint256 experimentId,
        uint8 outcome,
        uint256 amount
    ) public isOpen(experimentId) {
        require(outcome == 0 || outcome == 1, "Invalid outcome");
        require(amount > 0, "Amount must be greater than 0");
        token.transferFrom(msg.sender, address(this), amount);
        if (outcome == 0) {
            experiments[experimentId].wagers0[msg.sender] += amount;
            experiments[experimentId].totalSide0 += amount;
        } else {
            experiments[experimentId].wagers1[msg.sender] += amount;
            experiments[experimentId].totalSide1 += amount;
        }
        emit BetPlaced(experimentId, msg.sender, outcome, amount);
    }

    function claimWinnings(uint256 experimentId) public {
        require(experiments[experimentId].complete, "Market not complete");

        uint256 our_share;
        if (experiments[experimentId].result == 0) {
            // Side A won
            require(
                experiments[experimentId].wagers0[msg.sender] > 0,
                "No winning wager"
            );
            our_share =
                (experiments[experimentId].wagers0[msg.sender] *
                    (experiments[experimentId].totalSide0 +
                        experiments[experimentId].totalSide1)) /
                experiments[experimentId].totalSide0;
        } else if (experiments[experimentId].result == 1) {
            // Side B won
            require(
                experiments[experimentId].wagers1[msg.sender] > 0,
                "No winning wager"
            );
            our_share =
                (experiments[experimentId].wagers1[msg.sender] *
                    (experiments[experimentId].totalSide0 +
                        experiments[experimentId].totalSide1)) /
                experiments[experimentId].totalSide1;
        } else {
            revert("Invalid result");
        }

        token.transfer(msg.sender, our_share);
        emit WinningsClaimed(experimentId, msg.sender, our_share);
    }

    // Helper functions to get experiment-specific data
    function getExperimentComplete(
        uint256 experimentId
    ) public view returns (bool) {
        return experiments[experimentId].complete;
    }

    function getExperimentResult(
        uint256 experimentId
    ) public view returns (uint8) {
        return experiments[experimentId].result;
    }

    function getExperimentTotals(
        uint256 experimentId
    ) public view returns (uint256 total0, uint256 total1) {
        return (
            experiments[experimentId].totalSide0,
            experiments[experimentId].totalSide1
        );
    }

    function getUserWagers(
        uint256 experimentId,
        address user
    ) public view returns (uint256 wager0, uint256 wager1) {
        return (
            experiments[experimentId].wagers0[user],
            experiments[experimentId].wagers1[user]
        );
    }
}
