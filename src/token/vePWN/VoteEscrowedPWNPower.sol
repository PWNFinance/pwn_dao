// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import { SafeCast } from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import { EpochPowerLib } from "src/lib/EpochPowerLib.sol";
import { Error } from "src/lib/Error.sol";
import { VoteEscrowedPWNBase } from "./VoteEscrowedPWNBase.sol";

/// @title VoteEscrowedPWNPower
/// @notice Contract for the vote-escrowed PWN token implementing power functions.
contract VoteEscrowedPWNPower is VoteEscrowedPWNBase {
    using EpochPowerLib for bytes32;

    struct EpochPower {
        uint16 epoch;
        int104 power;
    }


    /*----------------------------------------------------------*|
    |*  # EVENTS                                                *|
    |*----------------------------------------------------------*/

    /// @notice Emitted when the total power for an epoch is calculated.
    /// @param epoch The epoch for which the total power was calculated.
    event TotalPowerCalculated(uint256 indexed epoch);


    /*----------------------------------------------------------*|
    |*  # STAKE POWER                                           *|
    |*----------------------------------------------------------*/

    function stakePowers(uint256 initialEpoch, uint256 amount, uint256 lockUpEpochs)
        external
        pure
        returns (EpochPower[] memory powers)
    {
        if (amount < 100 || amount % 100 > 0 || amount > type(uint88).max) {
            revert Error.InvalidAmount();
        }
        if (lockUpEpochs < 1 || lockUpEpochs > EPOCHS_IN_YEAR * 10) {
            revert Error.InvalidLockUpPeriod();
        }
        // calculate how many epochs are needed
        uint256 epochs;
        if (lockUpEpochs > EPOCHS_IN_YEAR * 5) {
            epochs = 7;
        } else {
            epochs = lockUpEpochs / EPOCHS_IN_YEAR + (lockUpEpochs % EPOCHS_IN_YEAR > 0 ? 2 : 1);
        }

        powers = new EpochPower[](epochs);
        uint16 epoch = SafeCast.toUint16(initialEpoch);
        uint8 remainingLockup = uint8(lockUpEpochs);
        int104 _amount = SafeCast.toInt104(int256(uint256(amount)));
        int104 power = _power(_amount, remainingLockup);
        // calculate epoch powers
        powers[0] = EpochPower({ epoch: epoch, power: power });
        for (uint256 i = 1; i < epochs; ++i) {
            uint8 epochsToNextPowerChange = _epochsToNextPowerChange(remainingLockup);
            remainingLockup -= epochsToNextPowerChange;
            epoch += epochsToNextPowerChange;
            power += _powerDecrease(_amount, remainingLockup);
            powers[i] = EpochPower({ epoch: epoch, power: power });
        }
    }


    /*----------------------------------------------------------*|
    |*  # STAKER POWER                                          *|
    |*----------------------------------------------------------*/

    /// @notice Returns the power of a staker at given epochs.
    /// @param staker The staker address.
    /// @param epochs The epochs for which to return the powers.
    /// @return powers The powers of the staker at the given epochs.
    function stakerPowers(address staker, uint256[] calldata epochs) external view returns (uint256[] memory) {
        uint256[] memory powers = new uint256[](epochs.length);
        for (uint256 i; i < epochs.length;) {
            powers[i] = stakerPowerAt({
                staker: staker,
                epoch: epochs[i]
            });
            unchecked { ++i; }
        }
        return powers;
    }

    /// @inheritdoc VoteEscrowedPWNBase
    function stakerPowerAt(address staker, uint256 epoch) override virtual public view returns (uint256) {
        uint16 _epoch = SafeCast.toUint16(epoch);
        uint256[] memory stakeIds = stakedPWN.ownedTokenIdsAt(staker, _epoch);
        uint256 stakesLength = stakeIds.length;
        int104 power;
        for (uint256 i; i < stakesLength;) {
            // sum up all stake powers
            power += _stakePowerAt({
                stake: stakes[stakeIds[i]],
                epoch: _epoch
            });

            unchecked { ++i; }
        }

        return SafeCast.toUint256(int256(power));
    }

    function _stakePowerAt(Stake memory stake, uint16 epoch) internal pure returns (int104) {
        if (stake.initialEpoch > epoch) {
            return 0; // not staked yet
        }
        if (stake.initialEpoch + stake.lockUpEpochs <= epoch) {
            return 0; // lockup expired
        }
        return _power({
            amount: SafeCast.toInt104(int256(uint256(stake.amount))),
            lockUpEpochs: stake.lockUpEpochs - uint8(epoch - stake.initialEpoch)
        });
    }


    /*----------------------------------------------------------*|
    |*  # TOTAL POWER                                           *|
    |*----------------------------------------------------------*/

    /// @notice Returns the total power at given epochs.
    /// @param epochs The epochs for which to return the total powers.
    /// @return powers The total powers at the given epochs.
    function totalPowers(uint256[] calldata epochs) external view returns (uint256[] memory) {
        uint256[] memory powers = new uint256[](epochs.length);
        for (uint256 i; i < epochs.length;) {
            powers[i] = totalPowerAt(epochs[i]);
            unchecked { ++i; }
        }
        return powers;
    }

    /// @inheritdoc VoteEscrowedPWNBase
    function totalPowerAt(uint256 epoch) override virtual public view returns (uint256) {
        if (lastCalculatedTotalPowerEpoch >= epoch) {
            return SafeCast.toUint256(int256(TOTAL_POWER_NAMESPACE.getEpochPower(epoch)));
        }

        // sum the rest of epochs
        int104 totalPower;
        for (uint256 i = lastCalculatedTotalPowerEpoch; i <= epoch;) {
            totalPower += TOTAL_POWER_NAMESPACE.getEpochPower(i);
            unchecked { ++i; }
        }

        return SafeCast.toUint256(int256(totalPower));
    }

    /// @notice Calculates the total power up to the current epoch.
    /// @dev For more information, see {VoteEscrowedPWNPower.calculateTotalPowerUpTo}.
    function calculateTotalPower() external {
        calculateTotalPowerUpTo(epochClock.currentEpoch());
    }

    /// @notice Calculates the total power up to a given epoch.
    /// @dev The total power is not calculated for every epoch and needs to be calculated explicitly.
    /// This function calculates the total power for all epochs up to the given epoch.
    function calculateTotalPowerUpTo(uint256 epoch) public {
        if (epoch > epochClock.currentEpoch()) {
            revert Error.EpochStillRunning();
        }
        if (lastCalculatedTotalPowerEpoch >= epoch) {
            revert Error.PowerAlreadyCalculated(lastCalculatedTotalPowerEpoch);
        }

        for (uint256 i = lastCalculatedTotalPowerEpoch; i < epoch;) {
            TOTAL_POWER_NAMESPACE.updateEpochPower({
                epoch: i + 1,
                power: TOTAL_POWER_NAMESPACE.getEpochPower(i)
            });

            unchecked { ++i; }
        }

        lastCalculatedTotalPowerEpoch = epoch;

        emit TotalPowerCalculated(epoch);
    }

}
