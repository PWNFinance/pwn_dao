// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.18;


contract MockWallet {

    receive() external payable {
        revert("not supported");
    }

}
