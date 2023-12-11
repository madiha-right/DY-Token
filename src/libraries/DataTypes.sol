// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @notice RToken storage structures
 */
library RTokenStructs {
    /// @notice Global stats
    struct GlobalStats {
        uint256 totalSupply; // Total redeemable tokens supply
        uint256 totalSavingsAmount; // Total saving assets in redeemable amount
    }

    /// @notice Account stats stored
    struct AccountStatsView {
        uint256 hatID; // Current hat ID
        uint256 rAmount; // Current redeemable amount
        uint256 rInterest; // Interest portion of the rAmount
        uint256 lDebt; // Current loaned debt amount
        uint256 sInternalAmount; // Current internal savings amount
        uint256 rInterestPayable; // Interest payable
        uint256 cumulativeInterest; // Cumulative interest generated for the account
        uint256 lRecipientsSum; // Loans lent to the recipients
    }

    // TODO: Can't we just use AccountStatsView?
    /// @notice Account stats stored
    struct AccountStatsStored {
        uint256 cumulativeInterest; // Cumulative interest generated for the account
    }

    /// @notice Hat stats view
    struct HatStatsView {
        uint256 useCount; // Number of addresses has the hat
        uint256 totalLoans; // Total net loans distributed through the hat
        uint256 totalSavings; // Total net savings distributed through the hat
    }

    // TODO: dupliacated
    /// @notice Hat stats stored
    struct HatStatsStored {
        uint256 useCount; // Number of addresses has the hat
        uint256 totalLoans; // Total net loans distributed through the hat
        uint256 totalInternalSavings; // Total net savings distributed through the hat
    }

    /**
     * @notice Hat structure describes who are the recipients of the interest
     *
     * To be a valid hat structure:
     *   - at least one recipient
     *   - recipients.length == proportions.length
     *   - each value in proportions should be greater than 0
     */
    struct Hat {
        address[] recipients;
        uint32[] proportions;
    }

    /// @dev Account structure
    struct Account {
        uint256 hatID; // Current selected hat ID of the account
        uint256 rAmount; // Current balance of the account (non realtime)
        uint256 rInterest; // Interest rate portion of the rAmount
        mapping(address => uint256) lRecipients; //  Debt in redeemable amount lent to recipients. In case of self-hat, external debt is optimized to not to be stored in lRecipients.
        uint256 lDebt; // Received loan. Debt in redeemable amount owed to the lenders distributed through one or more hats.
        uint256 sInternalAmount; // Savings internal accounting amount. Debt is sold to buy savings.
    }

    /**
     * Additional Definitions:
     *
     *   - rGross = sInternalToR(sInternalAmount)
     *   - lRecipientsSum = sum(lRecipients)
     *   - interestPayable = rGross - lDebt - rInterest
     *   - realtimeBalance = rAmount + interestPayable
     *
     *   - rAmount aka. tokenBalance
     *   - rGross aka. receivedSavings
     *   - lDebt aka. receivedLoan
     *
     * Account Invariants:
     *
     *   - rAmount = lRecipientsSum + rInterest [with rounding errors]
     *
     * Global Invariants:
     *
     * - globalStats.totalSupply = sum(account.tokenBalance)
     * - globalStats.totalSavingsAmount = sum(account.receivedSavings) [with rounding errors]
     * - sum(hatStats.totalLoans) = sum(account.receivedLoan)
     * - sum(hatStats.totalSavings) = sum(account.receivedSavings + cumulativeInterest - rInterest) [with rounding errors]
     *
     */
}
