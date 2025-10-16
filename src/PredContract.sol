// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev Minimal ERC20 interface for token interactions
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

/// @title PredMarket - Prediction Market for Binary Experiment Outcomes
/// @notice This contract allows users to bet on binary outcomes of experiments using ERC20 tokens
/// @dev Designed for use with USDC token. Winners receive proportional payouts from the total pool
contract PredMarket {
    /// @notice Experiment data structure containing all market information
    /// @dev Uses mappings for wagers, cannot be returned directly by public getter
    struct Experiment {
        bool complete;                          // Whether the experiment has concluded
        uint8 result;                           // Outcome: 0 = side 0 won, 1 = side 1 won
        uint256 totalSide0;                     // Total tokens wagered on side 0
        uint256 totalSide1;                     // Total tokens wagered on side 1
        mapping(address => uint256) wagers0;    // Individual wagers on side 0 by address
        mapping(address => uint256) wagers1;    // Individual wagers on side 1 by address
    }

    /// @notice Primary administrator with full control over experiment results
    address public admin;

    /// @notice Secondary administrator with limited permissions (can refund users)
    address public admin_dev;

    /// @notice Mapping of experiment IDs to their data
    mapping(uint256 => Experiment) public experiments;

    /// @notice Tracks which experiment IDs have been officially created
    mapping(uint256 => bool) public experimentExists;

    /// @notice ERC20 token used for all wagers and payouts (USDC)
    IERC20 public token;

    /// @notice Minimum bet amount (1 USDC with 6 decimals)
    uint256 public constant MIN_BET = 1e6;

    /// @notice Emitted when a new experiment is created
    /// @param experimentId The unique identifier for the experiment
    event ExperimentCreated(uint256 indexed experimentId);

    /// @notice Emitted when an experiment result is set
    /// @param experimentId The unique identifier for the experiment
    /// @param result The outcome (0 = side 0 won, 1 = side 1 won)
    event ExperimentResultSet(uint256 indexed experimentId, uint8 result);

    /// @notice Emitted when a market is closed without a result (after full refund)
    /// @param experimentId The unique identifier for the experiment
    event MarketClosed(uint256 indexed experimentId);

    /// @notice Emitted when a user receives a refund
    /// @param experimentId The unique identifier for the experiment
    /// @param user The address receiving the refund
    /// @param amount The amount of tokens refunded
    event UserRefunded(
        uint256 indexed experimentId,
        address indexed user,
        uint256 amount
    );

    /// @notice Emitted when a bet is placed
    /// @param experimentId The unique identifier for the experiment
    /// @param user The address placing the bet
    /// @param outcome The side being bet on (0 or 1)
    /// @param amount The amount of tokens wagered
    event BetPlaced(
        uint256 indexed experimentId,
        address indexed user,
        uint8 outcome,
        uint256 amount
    );

    /// @notice Emitted when winnings are claimed
    /// @param experimentId The unique identifier for the experiment
    /// @param user The address claiming winnings
    /// @param amount The amount of tokens won
    event WinningsClaimed(
        uint256 indexed experimentId,
        address indexed user,
        uint256 amount
    );

    /// @notice Ensures the experiment is still open for betting
    /// @param experimentId The experiment to check
    modifier isOpen(uint256 experimentId) {
        require(!experiments[experimentId].complete, "Experiment is closed");
        _;
    }

    /// @notice Restricts function access to the primary admin only
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call this function");
        _;
    }

    /// @notice Restricts function access to either admin or admin_dev
    modifier onlyAdminPlusDev() {
        require(
            msg.sender == admin || msg.sender == admin_dev,
            "Only admin or admin_dev can call this function"
        );
        _;
    }

    /// @notice Ensures the experiment has been officially created
    /// @param experimentId The experiment to validate
    modifier validExperiment(uint256 experimentId) {
        require(experimentExists[experimentId], "Experiment doesn't exist");
        _;
    }

    /// @notice Initializes the prediction market contract
    /// @param _token Address of the ERC20 token to use for wagers (USDC)
    /// @param _admin Address of the primary administrator
    /// @param _admin_dev Address of the secondary administrator
    /// @dev All addresses must be non-zero
    constructor(address _token, address _admin, address _admin_dev) {
        require(_admin != address(0), "Admin address cannot be zero");
        require(_admin_dev != address(0), "Admin_dev address cannot be zero");
        require(_token != address(0), "Token address cannot be zero");
        admin = _admin;
        admin_dev = _admin_dev;
        token = IERC20(_token);
    }

    /// @notice Creates a new experiment for betting
    /// @param experimentId The unique identifier for the new experiment
    /// @dev Only admin can call this. Prevents accidental bets on non-existent markets
    function createExperiment(uint256 experimentId) public onlyAdmin {
        require(!experimentExists[experimentId], "Experiment already exists");
        experimentExists[experimentId] = true;
        emit ExperimentCreated(experimentId);
    }

    /// @notice Sets the result of an experiment, determining the winning side
    /// @param experimentId The unique identifier for the experiment
    /// @param _result The outcome (0 = side 0 won, 1 = side 1 won)
    /// @dev Only admin can call. Validates that winning side has bets to prevent fund lockup
    /// @dev Once set, the experiment is marked complete and betting is closed
    function setResult(
        uint256 experimentId,
        uint8 _result
    ) public onlyAdmin validExperiment(experimentId) isOpen(experimentId) {
        require(_result == 0 || _result == 1, "Invalid result");

        // Prevent setting a result where winning side has no bets
        if (_result == 0) {
            require(
                experiments[experimentId].totalSide0 > 0,
                "Winning side has no bets"
            );
        } else {
            require(
                experiments[experimentId].totalSide1 > 0,
                "Winning side has no bets"
            );
        }

        experiments[experimentId].result = _result;
        experiments[experimentId].complete = true;
        emit ExperimentResultSet(experimentId, _result);
    }

    /// @notice Closes a market without setting a result (used after full refund)
    /// @param experimentId The unique identifier for the experiment
    /// @dev Only admin can call. Requires all funds to be refunded first (totals = 0)
    /// @dev This is an alternative to setResult when the experiment is cancelled
    function closeMarket(
        uint256 experimentId
    ) public onlyAdmin validExperiment(experimentId) isOpen(experimentId) {
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

    /// @notice Refunds users' wagers, typically when an experiment is cancelled
    /// @param experimentId The unique identifier for the experiment
    /// @param _users Array of user addresses to refund
    /// @dev Can be called by admin or admin_dev. Processes refunds in batches
    /// @dev Returns both side 0 and side 1 wagers to each user, updates totals
    function refund(
        uint256 experimentId,
        address[] calldata _users
    ) public onlyAdminPlusDev validExperiment(experimentId) isOpen(experimentId) {
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

    /// @notice Places a bet on an experiment outcome
    /// @param experimentId The unique identifier for the experiment
    /// @param outcome The side to bet on (0 or 1)
    /// @param amount The amount of tokens to wager (minimum 1 USDC)
    /// @dev Requires prior token approval. Experiment must be open
    /// @dev Users can bet multiple times on the same or different sides
    function bet(
        uint256 experimentId,
        uint8 outcome,
        uint256 amount
    ) public validExperiment(experimentId) isOpen(experimentId) {
        require(outcome == 0 || outcome == 1, "Invalid outcome");
        require(amount >= MIN_BET, "Amount below minimum bet");
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

    /// @notice Claims winnings for a completed experiment
    /// @param experimentId The unique identifier for the experiment
    /// @dev Only winners can claim. Payout is proportional to wager size relative to winning side total
    /// @dev Formula: user_payout = (user_wager / winning_side_total) * total_pool
    /// @dev Wagers are zeroed after claiming to prevent double-claiming
    function claimWinnings(uint256 experimentId)
        public
        validExperiment(experimentId)
    {
        require(experiments[experimentId].complete, "Market not complete");

        uint256 our_share;
        if (experiments[experimentId].result == 0) {
            // Side 0 won
            require(
                experiments[experimentId].wagers0[msg.sender] > 0,
                "No winning wager"
            );
            our_share =
                (experiments[experimentId].wagers0[msg.sender] *
                    (experiments[experimentId].totalSide0 +
                        experiments[experimentId].totalSide1)) /
                experiments[experimentId].totalSide0;
            experiments[experimentId].wagers0[msg.sender] = 0;
        } else if (experiments[experimentId].result == 1) {
            // Side 1 won
            require(
                experiments[experimentId].wagers1[msg.sender] > 0,
                "No winning wager"
            );
            our_share =
                (experiments[experimentId].wagers1[msg.sender] *
                    (experiments[experimentId].totalSide0 +
                        experiments[experimentId].totalSide1)) /
                experiments[experimentId].totalSide1;
            experiments[experimentId].wagers1[msg.sender] = 0;
        } else {
            revert("Invalid result");
        }

        token.transfer(msg.sender, our_share);
        emit WinningsClaimed(experimentId, msg.sender, our_share);
    }

    /// @notice Checks if an experiment is complete
    /// @param experimentId The unique identifier for the experiment
    /// @return bool True if the experiment has concluded (result set or closed)
    function getExperimentComplete(
        uint256 experimentId
    ) public view returns (bool) {
        return experiments[experimentId].complete;
    }

    /// @notice Gets the result of a completed experiment
    /// @param experimentId The unique identifier for the experiment
    /// @return uint8 The outcome (0 = side 0 won, 1 = side 1 won)
    /// @dev Returns 0 by default if result not set. Check complete status first
    function getExperimentResult(
        uint256 experimentId
    ) public view returns (uint8) {
        return experiments[experimentId].result;
    }

    /// @notice Gets the total amounts wagered on each side
    /// @param experimentId The unique identifier for the experiment
    /// @return total0 Total tokens wagered on side 0
    /// @return total1 Total tokens wagered on side 1
    function getExperimentTotals(
        uint256 experimentId
    ) public view returns (uint256 total0, uint256 total1) {
        return (
            experiments[experimentId].totalSide0,
            experiments[experimentId].totalSide1
        );
    }

    /// @notice Gets a user's wagers on both sides for an experiment
    /// @param experimentId The unique identifier for the experiment
    /// @param user The address to query
    /// @return wager0 Amount wagered on side 0
    /// @return wager1 Amount wagered on side 1
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
