// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

/// @notice Utility library for masking uints in bytes32.
/// @dev The library is used to mask and type cast different size uints in bytes32.
library BitMaskLib {

    /// @notice Masks a uint8 from a bytes32.
    /// @param from The bytes32 to mask from.
    /// @param rightOffset The offset from the right to start masking.
    /// @return The masked uint8.
    function maskUint8(bytes32 from, uint256 rightOffset) internal pure returns (uint8) {
        return uint8(_rightShift(from, rightOffset, 8));
    }

    /// @notice Masks a uint16 from a bytes32.
    /// @param from The bytes32 to mask from.
    /// @param rightOffset The offset from the right to start masking.
    /// @return The masked uint16.
    function maskUint16(bytes32 from, uint256 rightOffset) internal pure returns (uint16) {
        return uint16(_rightShift(from, rightOffset, 16));
    }

    /// @notice Masks a uint32 from a bytes32.
    /// @param from The bytes32 to mask from.
    /// @param rightOffset The offset from the right to start masking.
    /// @return The masked uint32.
    function maskUint32(bytes32 from, uint256 rightOffset) internal pure returns (uint32) {
        return uint32(_rightShift(from, rightOffset, 32));
    }

    /// @notice Masks a uint64 from a bytes32.
    /// @param from The bytes32 to mask from.
    /// @param rightOffset The offset from the right to start masking.
    /// @return The masked uint64.
    function maskUint64(bytes32 from, uint256 rightOffset) internal pure returns (uint64) {
        return uint64(_rightShift(from, rightOffset, 64));
    }

    /// @notice Masks a uint104 from a bytes32.
    /// @param from The bytes32 to mask from.
    /// @param rightOffset The offset from the right to start masking.
    /// @return The masked uint104.
    function maskUint104(bytes32 from, uint256 rightOffset) internal pure returns (uint104) {
        return uint104(_rightShift(from, rightOffset, 104));
    }


    function _rightShift(bytes32 from, uint256 rightOffset, uint256 typeSize) private pure returns (uint256) {
        // solhint-disable-next-line custom-errors
        require(rightOffset <= 256 - typeSize, "Invalid mask offset");
        return uint256(from >> rightOffset);
    }

}
