// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;

interface IStakedPWNSupplyManager {
    function transferStake(address from, address to, uint256 stakeId) external;
}