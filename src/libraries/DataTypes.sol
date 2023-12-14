// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @notice RToken storage structures
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
        uint256 debtAmount; // Received loan. Debt in redeemable amount owed to the lenders distributed through one or more hats.
        uint256 debtShares; // Shares of the debt to track the interest earned by the debt
        uint256 interestPaid; // Interest paid to the account
    }
}
