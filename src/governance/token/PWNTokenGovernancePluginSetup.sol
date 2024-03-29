// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

// solhint-disable max-line-length

// This code is based on the Aragon's token voting plugin setup.
// https://github.com/aragon/osx/blob/e90ea8f5cd6b98cbba16db07ab7bc0cdbf517f3e/packages/contracts/src/plugins/governance/majority-voting/token/TokenVotingSetup.sol
// Changes:
// - Remove `GovernanceERC20` and `GovernanceWrappedERC20`

// solhint-enable max-line-length

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import { DAO } from "@aragon/osx/core/dao/DAO.sol";
import { PermissionLib } from "@aragon/osx/core/permission/PermissionLib.sol";
import { PluginSetup , IPluginSetup} from "@aragon/osx/framework/plugin/setup/PluginSetup.sol";

import { PWNTokenGovernancePlugin } from "./PWNTokenGovernancePlugin.sol";

/// @title PWN Token Governance Plugin Setup
/// @notice The setup contract of the `PWNTokenGovernancePlugin` plugin.
contract PWNTokenGovernancePluginSetup is PluginSetup {
    using Address for address;
    using Clones for address;
    using ERC165Checker for address;

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    /// @notice The address of the `PWNTokenGovernancePlugin` base contract.
    PWNTokenGovernancePlugin private immutable tokenGovernancePluginBase;


    /*----------------------------------------------------------*|
    |*  # ERRORS                                                *|
    |*----------------------------------------------------------*/

    /// @notice Thrown if passed helpers array is of wrong length.
    /// @param length The array length of passed helpers.
    error WrongHelpersArrayLength(uint256 length);


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    /// @notice The contract constructor deploying the plugin implementation contract to clone from.
    constructor() {
        tokenGovernancePluginBase = new PWNTokenGovernancePlugin();
    }


    /*----------------------------------------------------------*|
    |*  # PREPARE INSTALL & UNINSTALL                           *|
    |*----------------------------------------------------------*/

    /// @inheritdoc IPluginSetup
    function prepareInstallation(address _dao, bytes calldata _installParameters)
        external
        returns (address plugin, PreparedSetupData memory preparedSetupData)
    {
        // Decode `_installParameters` to extract the params needed for deploying and initializing
        // `PWNTokenGovernancePlugin` plugin, and the required helpers.
        (
            PWNTokenGovernancePlugin.TokenGovernanceSettings memory governanceSettings,
            address epochClock,
            address votingToken,
            address rewardToken
        ) = decodeInstallationParams(_installParameters);

        // prepare and deploy plugin proxy
        plugin = createERC1967Proxy(
            address(tokenGovernancePluginBase),
            abi.encodeWithSelector(
                PWNTokenGovernancePlugin.initialize.selector,
                _dao, governanceSettings, epochClock, votingToken, rewardToken
            )
        );

        // prepare permissions
        PermissionLib.MultiTargetPermission[] memory permissions = new PermissionLib.MultiTargetPermission[](3);

        // request the permissions to be granted

        // the DAO can update the plugin settings
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: tokenGovernancePluginBase.UPDATE_TOKEN_GOVERNANCE_SETTINGS_PERMISSION_ID()
        });

        // the DAO can upgrade the plugin implementation
        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: tokenGovernancePluginBase.UPGRADE_PLUGIN_PERMISSION_ID()
        });

        // the plugin can call the DAO execute function
        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _dao,
            who: plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: DAO(payable(_dao)).EXECUTE_PERMISSION_ID()
        });

        preparedSetupData.permissions = permissions;
    }

    /// @inheritdoc IPluginSetup
    function prepareUninstallation(address _dao, SetupPayload calldata _payload)
        external
        view
        returns (PermissionLib.MultiTargetPermission[] memory permissions)
    {
        uint256 helperLength = _payload.currentHelpers.length;
        if (helperLength != 0) {
            revert WrongHelpersArrayLength({ length: helperLength });
        }

        // prepare permissions
        permissions = new PermissionLib.MultiTargetPermission[](3);

        // set permissions to be Revoked
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: tokenGovernancePluginBase.UPDATE_TOKEN_GOVERNANCE_SETTINGS_PERMISSION_ID()
        });

        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: tokenGovernancePluginBase.UPGRADE_PLUGIN_PERMISSION_ID()
        });

        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _dao,
            who: _payload.plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: DAO(payable(_dao)).EXECUTE_PERMISSION_ID()
        });
    }


    /*----------------------------------------------------------*|
    |*  # GETTERS                                               *|
    |*----------------------------------------------------------*/

    /// @inheritdoc IPluginSetup
    function implementation() external view virtual override returns (address) {
        return address(tokenGovernancePluginBase);
    }


    /*----------------------------------------------------------*|
    |*  # EN/DECODE INSTALL PARAMS                              *|
    |*----------------------------------------------------------*/

    /// @notice Encodes the given installation parameters into a byte array.
    function encodeInstallationParams(
        PWNTokenGovernancePlugin.TokenGovernanceSettings memory _governanceSettings,
        address _epochClock,
        address _votingToken,
        address _rewardToken
    ) external pure returns (bytes memory) {
        return abi.encode(_governanceSettings, _epochClock, _votingToken, _rewardToken);
    }

    /// @notice Decodes the given byte array into the original installation parameters.
    function decodeInstallationParams(bytes memory _data)
        public
        pure
        returns (
            PWNTokenGovernancePlugin.TokenGovernanceSettings memory governanceSettings,
            address epochClock,
            address votingToken,
            address rewardToken
        )
    {
        (governanceSettings, epochClock, votingToken, rewardToken) = abi.decode(
            _data, (PWNTokenGovernancePlugin.TokenGovernanceSettings, address, address, address)
        );
    }

}
