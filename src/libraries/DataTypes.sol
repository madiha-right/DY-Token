// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @notice DY-Token storage structures
 */
library DataTypes {
    /**
     * @notice Hat structure describes who are the recipients of the interest
     *
     * To be a valid hat structure:
     *   - recipients.length == proportions.length
     *   - each value in proportions should be greater than 0
     */
    struct Hat {
        address[] recipients;
        uint16[] proportions;
    }

    /// @dev Account structure
    struct Account {
        Hat hat; // Current hat of the account
        uint256 amount; // Current balance of the account (non realtime)
        uint256 delegatedAmount; // Delegated amount from to the delegators, distributed through one or more hats
        uint256 delegatedShares; // Shares of the delegated amount to track the interest earned by the delegated amount
        uint256 interestPaid; // Interest paid to the account
    }
}
