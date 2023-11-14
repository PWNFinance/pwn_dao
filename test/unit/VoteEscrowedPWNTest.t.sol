// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import { VoteEscrowedPWN } from "../../src/VoteEscrowedPWN.sol";

import { VoteEscrowedPWNHarness } from "../harness/VoteEscrowedPWNHarness.sol";
import { SlotComputingLib } from "../utils/SlotComputingLib.sol";
import { BasePWNTest } from "../BasePWNTest.sol";


abstract contract VoteEscrowedPWNTest is BasePWNTest {
    using SlotComputingLib for bytes32;

    uint8 public constant EPOCHS_IN_PERIOD = 13;
    bytes32 public constant STAKES_SLOT = bytes32(uint256(7));
    bytes32 public constant POWER_CHANGES_EPOCHS_SLOT = bytes32(uint256(8));
    bytes32 public constant LAST_CALCULATED_STAKER_POWER_EPOCH_SLOT = bytes32(uint256(9));
    bytes32 public constant LAST_CALCULATED_TOTAL_POWER_EPOCH_SLOT = bytes32(uint256(10));

    VoteEscrowedPWNHarness public vePWN;

    address public pwnToken = makeAddr("pwnToken");
    address public stakedPWN = makeAddr("stakedPWN");
    address public epochClock = makeAddr("epochClock");
    address public feeCollector = makeAddr("feeCollector");
    address public owner = makeAddr("owner");
    address public staker = makeAddr("staker");

    uint256 public currentEpoch = 420;

    function setUp() public virtual {
        vm.mockCall(
            epochClock, abi.encodeWithSignature("currentEpoch()"), abi.encode(currentEpoch)
        );
        vm.mockCall(
            pwnToken, abi.encodeWithSignature("transfer(address,uint256)"), abi.encode(true)
        );
        vm.mockCall(
            pwnToken, abi.encodeWithSignature("transferFrom(address,address,uint256)"), abi.encode(true)
        );
        vm.mockCall(
            stakedPWN, abi.encodeWithSignature("mint(address,uint256)"), abi.encode(0)
        );
        vm.mockCall(
            stakedPWN, abi.encodeWithSignature("burn(uint256)"), abi.encode(0)
        );
        vm.mockCall(
            feeCollector,
            abi.encodeWithSignature("claimFees(address,uint256,address[],uint256,uint256)"),
            abi.encode(0)
        );

        vePWN = new VoteEscrowedPWNHarness();
        vePWN.initialize({
            _pwnToken: pwnToken,
            _stakedPWN: stakedPWN,
            _epochClock: epochClock,
            _feeCollector: feeCollector,
            _owner: owner
        });
    }


    struct TestPowerChangeEpoch {
        uint16 epoch;
        int104 powerChange;
    }

    function _createPowerChangesArray(uint256 _amount, uint256 _lockUpEpochs) internal returns (TestPowerChangeEpoch[] memory) {
        return _createPowerChangesArray(uint16(currentEpoch + 1), _amount, _lockUpEpochs);
    }

    function _createPowerChangesArray(uint16 _initialEpoch, uint256 _amount, uint256 _lockUpEpochs) internal returns (TestPowerChangeEpoch[] memory) {
        return _createPowerChangesArray(_initialEpoch, type(uint16).max, _amount, _lockUpEpochs);
    }

    TestPowerChangeEpoch[] private helper_powerChanges;
    function _createPowerChangesArray(
        uint16 _initialEpoch, uint16 _finalEpoch, uint256 _amount, uint256 _lockUpEpochs
    ) internal returns (TestPowerChangeEpoch[] memory) {
        if (_initialEpoch >= _finalEpoch)
            return new TestPowerChangeEpoch[](0);

        uint16 epoch = _initialEpoch;
        uint8 remainingLockup = uint8(_lockUpEpochs);
        int104 int104amount = int104(int256(_amount));
        int104 powerChange = vePWN.exposed_initialPower(int104amount, remainingLockup);

        helper_powerChanges.push(TestPowerChangeEpoch({ epoch: epoch, powerChange: powerChange }));
        while (remainingLockup > 0) {
            (powerChange, epoch, remainingLockup) = vePWN.exposed_nextEpochAndRemainingLockup(int104amount, epoch, remainingLockup);
            if (epoch >= _finalEpoch) break;
            helper_powerChanges.push(TestPowerChangeEpoch({ epoch: epoch, powerChange: powerChange }));
        }
        TestPowerChangeEpoch[] memory array = helper_powerChanges;
        delete helper_powerChanges;
        return array;
    }

    function _mergePowerChanges(TestPowerChangeEpoch[] memory pchs1, TestPowerChangeEpoch[] memory pchs2) internal returns (TestPowerChangeEpoch[] memory) {
        if (pchs1.length == 0)
            return pchs2;
        else if (pchs2.length == 0)
            return pchs1;

        uint256 i1;
        uint256 i2;
        bool stop1;
        bool stop2;
        while (true) {
            if (!stop1 && (pchs1[i1].epoch < pchs2[i2].epoch || stop2)) {
                helper_powerChanges.push(pchs1[i1]);
                if (i1 + 1 < pchs1.length) ++i1; else stop1 = true;
            } else if (!stop2 && (pchs1[i1].epoch > pchs2[i2].epoch || stop1)) {
                helper_powerChanges.push(pchs2[i2]);
                if (i2 + 1 < pchs2.length) ++i2; else stop2 = true;
            } else if (pchs1[i1].epoch == pchs2[i2].epoch && !stop1 && !stop2) {
                int104 powerSum = pchs1[i1].powerChange + pchs2[i2].powerChange;
                if (powerSum != 0) {
                    helper_powerChanges.push(TestPowerChangeEpoch({ epoch: pchs1[i1].epoch, powerChange: powerSum }));
                }
                if (i1 + 1 < pchs1.length) ++i1; else stop1 = true;
                if (i2 + 1 < pchs2.length) ++i2; else stop2 = true;
            }
            if (stop1 && stop2)
                break;
        }

        TestPowerChangeEpoch[] memory array = helper_powerChanges;
        delete helper_powerChanges;
        return array;
    }

    function _storeStake(uint256 _stakeId, uint16 _initialEpoch, uint104 _amount, uint8 _remainingLockup) internal {
        bytes memory rawStakeData = abi.encodePacked(uint128(0), _remainingLockup, _amount, _initialEpoch);
        vm.store(
            address(vePWN), STAKES_SLOT.withMappingKey(_stakeId), abi.decode(rawStakeData, (bytes32))
        );
    }

    // expects storage to be empty
    function _storePowerChanges(address _staker, TestPowerChangeEpoch[] memory powerChanges) internal {
        bytes32 powerChangesSlot = POWER_CHANGES_EPOCHS_SLOT.withMappingKey(_staker);
        vm.store(
            address(vePWN), powerChangesSlot, bytes32(powerChanges.length)
        );

        uint256 necessarySlots = powerChanges.length / 16;
        necessarySlots += powerChanges.length % 16 == 0 ? 0 : 1;
        for (uint256 i; i < necessarySlots; ++i) {
            bool lastLoop = i + 1 == necessarySlots;
            uint256 upperBound = lastLoop ? powerChanges.length % 16 : 16;
            upperBound = upperBound == 0 ? 16 : upperBound;
            bytes32 encodedPowerChanges;
            for (uint256 j; j < upperBound; ++j) {
                TestPowerChangeEpoch memory powerChange = powerChanges[i * 16 + j];
                encodedPowerChanges = encodedPowerChanges | bytes32(uint256(powerChange.epoch)) << (16 * j);

                vePWN.workaround_storeStakerEpochPower(_staker, powerChange.epoch, powerChange.powerChange);
                vePWN.workaround_storeTotalEpochPower(powerChange.epoch, powerChange.powerChange);
            }

            vm.store(
                address(vePWN), keccak256(abi.encode(powerChangesSlot)).withArrayIndex(i), encodedPowerChanges
            );
        }
    }

    function _mockStake(
        address _staker, uint256 _stakeId, uint16 _initialEpoch, uint104 _amount, uint8 _remainingLockup
    ) internal returns (TestPowerChangeEpoch[] memory) {
        vm.mockCall(
            address(stakedPWN),
            abi.encodeWithSignature("ownerOf(uint256)", _stakeId),
            abi.encode(_staker)
        );
        _storeStake(_stakeId, _initialEpoch, _amount, _remainingLockup);
        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangesArray(_initialEpoch, _amount, _remainingLockup);
        _storePowerChanges(_staker, powerChanges);
        return powerChanges;
    }

    // bound

    function _boundAmount(uint256 seed) internal view returns (uint256) {
        return bound(seed, 100, 1e26) / 100 * 100;
    }

    function _boundLockUpEpochs(uint256 seed) internal view returns (uint8) {
        uint8 lockUpEpochs = uint8(bound(seed, EPOCHS_IN_PERIOD, 10 * EPOCHS_IN_PERIOD));
        return lockUpEpochs > 5 * EPOCHS_IN_PERIOD ? 10 * EPOCHS_IN_PERIOD : lockUpEpochs;
    }

    function _boundRemainingLockups(uint256 seed) internal view returns (uint8) {
        return uint8(bound(seed, 1, 10 * EPOCHS_IN_PERIOD));
    }

    // assert

    function _assertPowerChangesSumToZero(address _staker) internal {
        uint256 length = vePWN.workaround_stakerPowerChangeEpochsLength(_staker);
        int104 sum;
        for (uint256 i; i < length; ++i) {
            uint16 epoch = vePWN.powerChangeEpochs(_staker, i);
            sum += vePWN.workaround_getStakerEpochPower(_staker, epoch);
        }
        assertEq(sum, 0);
    }

    function _assertTotalPowerChangesSumToZero(uint256 lastEpoch) internal {
        int104 sum;
        for (uint256 i; i <= lastEpoch; ++i) {
            sum += vePWN.workaround_getTotalEpochPower(i);
        }
        assertEq(sum, 0);
    }

    function _assertEpochPowerAndPosition(address _staker, uint256 _index, uint16 _epoch, int104 _power) internal {
        assertEq(vePWN.powerChangeEpochs(_staker, _index), _epoch, "epoch mismatch");
        assertEq(vePWN.workaround_getStakerEpochPower(_staker, _epoch), _power, "power mismatch");
    }

}


/*----------------------------------------------------------*|
|*  # HELPERS                                               *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Helpers_Test is VoteEscrowedPWNTest {

    function testFuzzHelper_storeStake(uint256 _stakeId, uint16 _initialEpoch, uint104 _amount, uint8 _remainingLockup) external {
        _storeStake(_stakeId, _initialEpoch, _amount, _remainingLockup);

        (uint16 initialEpoch, uint104 amount, uint8 remainingLockup) = vePWN.stakes(_stakeId);
        assertEq(_initialEpoch, initialEpoch);
        assertEq(_amount, amount);
        assertEq(_remainingLockup, remainingLockup);
    }

    function testFuzzHelper_storePowerChanges(address _staker, uint88 _amount, uint8 _lockUpEpochs) external {
        _amount = uint88(bound(_amount, 1, type(uint88).max));
        _lockUpEpochs = _boundLockUpEpochs(_lockUpEpochs);
        TestPowerChangeEpoch[] memory powerChanges = _createPowerChangesArray(_amount, _lockUpEpochs);
        _storePowerChanges(_staker, powerChanges);

        for (uint256 i; i < powerChanges.length; ++i) {
            assertEq(powerChanges[i].epoch, vePWN.powerChangeEpochs(_staker, i));
            assertEq(powerChanges[i].powerChange, vePWN.workaround_getStakerEpochPower(_staker, powerChanges[i].epoch));
        }
    }

}


/*----------------------------------------------------------*|
|*  # EXPOSED FUNCTIONS                                     *|
|*----------------------------------------------------------*/

contract VoteEscrowedPWN_Exposed_Test is VoteEscrowedPWNTest {
    using SlotComputingLib for bytes32;

    function testFuzz_nextEpochAndRemainingLockup_whenLessThanFivePeriods_whenDivisibleByPeriod(uint8 originalRemainingLockup) external {
        originalRemainingLockup = uint8(bound(originalRemainingLockup, 1, 5) * EPOCHS_IN_PERIOD);

        int104 amount = 100;
        uint16 originalEpoch = 100;
        (, uint16 epoch, uint8 remainingLockup) = vePWN.exposed_nextEpochAndRemainingLockup(
            amount, originalEpoch, originalRemainingLockup
        );

        assertEq(epoch, originalEpoch + EPOCHS_IN_PERIOD);
        assertEq(remainingLockup, originalRemainingLockup - EPOCHS_IN_PERIOD);
    }

    function testFuzz_nextEpochAndRemainingLockup_whenLessThanFivePeriods_whenNotDivisibleByPeriod(uint8 originalRemainingLockup) external {
        originalRemainingLockup = uint8(bound(originalRemainingLockup, EPOCHS_IN_PERIOD + 1, 5 * EPOCHS_IN_PERIOD - 1));
        vm.assume(originalRemainingLockup % EPOCHS_IN_PERIOD > 0);

        int104 amount = 100;
        uint16 originalEpoch = 100;
        (, uint16 epoch, uint8 remainingLockup) = vePWN.exposed_nextEpochAndRemainingLockup(
            amount, originalEpoch, originalRemainingLockup
        );

        uint16 diff = uint16(originalRemainingLockup % EPOCHS_IN_PERIOD);
        assertEq(epoch, originalEpoch + diff);
        assertEq(remainingLockup, originalRemainingLockup - diff);
    }

    function testFuzz_nextEpochAndRemainingLockup_whenMoreThanFivePeriods(uint8 originalRemainingLockup) external {
        originalRemainingLockup = uint8(bound(originalRemainingLockup, 5 * EPOCHS_IN_PERIOD + 1, 10 * EPOCHS_IN_PERIOD));

        int104 amount = 100;
        uint16 originalEpoch = 100;
        (, uint16 epoch, uint8 remainingLockup) = vePWN.exposed_nextEpochAndRemainingLockup(
            amount, originalEpoch, originalRemainingLockup
        );

        uint16 diff = uint16(originalRemainingLockup - 5 * EPOCHS_IN_PERIOD);
        assertEq(epoch, originalEpoch + diff);
        assertEq(remainingLockup, originalRemainingLockup - diff);
    }

    function testFuzz_updatePowerChangeEpoch_shouldUpdatePowerChangeValue(address staker, uint16 epoch, int104 power) external {
        power = int104(bound(power, 2, type(int104).max));
        int104 powerFraction = int104(bound(power, 1, power - 1));

        vePWN.exposed_updateEpochPower(staker, epoch, 0, powerFraction);
        assertEq(vePWN.workaround_getStakerEpochPower(staker, epoch), powerFraction);

        vePWN.exposed_updateEpochPower(staker, epoch, 0, power - powerFraction);
        assertEq(vePWN.workaround_getStakerEpochPower(staker, epoch), power);

        vePWN.exposed_updateEpochPower(staker, epoch, 0, -power);
        assertEq(vePWN.workaround_getStakerEpochPower(staker, epoch), 0);
    }

    function testFuzz_updatePowerChangeEpoch_shouldAddEpochToArray_whenPowerChangedFromZeroToNonZero(address staker, uint16 epoch, int104 power) external {
        power = int104(bound(power, 1, type(int104).max));

        uint256 index = vePWN.exposed_updateEpochPower(staker, epoch, 0, power);

        assertEq(vePWN.powerChangeEpochs(staker, index), epoch);
    }

    function test_updatePowerChangeEpoch_shouldKeepArraySorted() external {
        address staker = makeAddr("staker");
        uint16[] memory epochs = new uint16[](5);
        epochs[0] = 3;
        epochs[1] = 2;
        epochs[2] = 3;
        epochs[3] = 5;
        epochs[4] = 0;

        uint256[] memory indices = new uint256[](5);
        indices[0] = 0;
        indices[1] = 0;
        indices[2] = 1;
        indices[3] = 2;
        indices[4] = 0;

        for (uint256 i; i < epochs.length; ++i)
            assertEq(vePWN.exposed_updateEpochPower(staker, epochs[i], 0, 100e10), indices[i]);

        assertEq(vePWN.powerChangeEpochs(staker, 0), 0);
        assertEq(vePWN.powerChangeEpochs(staker, 1), 2);
        assertEq(vePWN.powerChangeEpochs(staker, 2), 3);
        assertEq(vePWN.powerChangeEpochs(staker, 3), 5);

        vm.expectRevert();
        vePWN.powerChangeEpochs(staker, 4);
    }

    function testFuzz_updatePowerChangeEpoch_shouldKeepEpochInArray_whenPowerChangedFromNonZeroToNonZero(address staker, uint16 epoch, int104 power) external {
        power = int104(bound(power, 1, type(int104).max - 1));

        uint256 index = vePWN.exposed_updateEpochPower(staker, epoch, 0, power);

        assertEq(vePWN.powerChangeEpochs(staker, index), epoch);
        assertEq(vePWN.exposed_updateEpochPower(staker, epoch, 0, 1), index);
    }

    function testFuzz_updatePowerChangeEpoch_shouldRemoveEpochFromArray_whenPowerChangedFromNonZeroToZero(address staker, uint16 epoch, int104 power) external {
        power = int104(bound(power, 1, type(int104).max));

        uint256 index = vePWN.exposed_updateEpochPower(staker, epoch, 0, power);

        assertEq(vePWN.powerChangeEpochs(staker, index), epoch);

        index = vePWN.exposed_updateEpochPower(staker, epoch, 0, -power);

        vm.expectRevert();
        vePWN.powerChangeEpochs(staker, index);
    }

    function testFuzz_powerChangeMultipliers_initialPower(uint256 amount, uint8 remainingLockup) external {
        amount = _boundAmount(amount);
        remainingLockup = uint8(bound(remainingLockup, 1, 130));

        int104[] memory periodMultiplier = new int104[](6);
        periodMultiplier[0] = 100;
        periodMultiplier[1] = 115;
        periodMultiplier[2] = 130;
        periodMultiplier[3] = 150;
        periodMultiplier[4] = 175;
        periodMultiplier[5] = 350;

        int104 power = vePWN.exposed_initialPower(int104(uint104(amount)), remainingLockup);

        int104 multiplier;
        if (remainingLockup > EPOCHS_IN_PERIOD * 5)
            multiplier = periodMultiplier[5];
        else
            multiplier = periodMultiplier[remainingLockup / EPOCHS_IN_PERIOD - (remainingLockup % EPOCHS_IN_PERIOD == 0 ? 1 : 0)];
        assertEq(power, int104(uint104(amount)) * multiplier / 100);
    }

    function testFuzz_powerChangeMultipliers_decreasePower(uint256 amount, uint8 remainingLockup) external {
        amount = _boundAmount(amount);
        remainingLockup = uint8(bound(remainingLockup, 1, 130));

        int104[] memory periodMultiplier = new int104[](6);
        periodMultiplier[0] = 15;
        periodMultiplier[1] = 15;
        periodMultiplier[2] = 20;
        periodMultiplier[3] = 25;
        periodMultiplier[4] = 175;
        periodMultiplier[5] = 0;

        int104 power = vePWN.exposed_decreasePower(int104(uint104(amount)), remainingLockup);

        int104 multiplier;
        if (remainingLockup > EPOCHS_IN_PERIOD * 5)
            multiplier = periodMultiplier[5];
        else if (remainingLockup == 0)
            multiplier = 100;
        else
            multiplier = periodMultiplier[remainingLockup / EPOCHS_IN_PERIOD - (remainingLockup % EPOCHS_IN_PERIOD == 0 ? 1 : 0)];
        assertEq(power, -int104(uint104(amount)) * multiplier / 100);
    }

    function test_powerChangeMultipliers_powerChangesShouldSumToZero(uint8 remainingLockup) external {
        vm.assume(remainingLockup > 0);

        int104 powerChange;
        int104 amount = 100;
        int104 sum = vePWN.exposed_initialPower(amount, remainingLockup);
        while (remainingLockup > 0) {
            (powerChange, , remainingLockup) = vePWN.exposed_nextEpochAndRemainingLockup(amount, 0, remainingLockup);
            sum += powerChange;
        }

        assertEq(sum, 0);
    }

}