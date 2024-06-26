// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

// solhint-disable max-line-length

// This code is based on the Aragon's majority voting interface.
// https://github.com/aragon/osx/blob/e90ea8f5cd6b98cbba16db07ab7bc0cdbf517f3e/packages/contracts/src/plugins/governance/majority-voting/IMajorityVoting.sol
// Changes:
// - Add `createProposal` and `getProposal`
// - Add `getVotingToken` and `totalVotingPower`
// - Add `minDuration` and `minProposerVotingPower`

// solhint-enable max-line-length

import { IVotesUpgradeable } from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import { IDAO } from "@aragon/osx/core/dao/IDAO.sol";

/// @title PWN Token Governance Interface
/// @notice The interface of a token governance plugin.
interface IPWNTokenGovernance {

    // # LIFECYCLE

    /// @notice Vote options that a voter can chose from.
    /// @param None The default option state of a voter indicating the absence from the vote.
    /// This option neither influences support nor participation.
    /// @param Abstain This option does not influence the support but counts towards participation.
    /// @param Yes This option increases the support and counts towards participation.
    /// @param No This option decreases the support and counts towards participation.
    enum VoteOption {
        None, Abstain, Yes, No
    }

    /// @notice Creates a new token governance proposal.
    /// @param _metadata The metadata of the proposal.
    /// @param _actions The actions that will be executed after the proposal passes.
    /// @param _allowFailureMap Allows proposal to succeed even if an action reverts. Uses bitmap representation.
    /// If the bit at index `x` is 1, the tx succeeds even if the action at `x` failed.
    /// Passing 0 will be treated as atomic execution.
    /// @param _startDate The start date of the proposal vote.
    /// If 0, the current timestamp is used and the vote starts immediately.
    /// @param _endDate The end date of the proposal vote. If 0, `_startDate + minDuration` is used.
    /// @param _voteOption The chosen vote option to be casted on proposal creation.
    /// @return proposalId The ID of the proposal.
    function createProposal(
        bytes calldata _metadata,
        IDAO.Action[] calldata _actions,
        uint256 _allowFailureMap,
        uint64 _startDate,
        uint64 _endDate,
        VoteOption _voteOption
    ) external returns (uint256 proposalId);

    /// @notice Votes for a vote option and, optionally, executes the proposal.
    /// @dev `_voteOption`, 1 -> abstain, 2 -> yes, 3 -> no
    /// @param _proposalId The ID of the proposal.
    /// @param _voteOption The chosen vote option.
    function vote(uint256 _proposalId, VoteOption _voteOption) external;

    /// @notice Executes a proposal.
    /// @param _proposalId The ID of the proposal to be executed.
    function execute(uint256 _proposalId) external;

    // # PROPOSAL

    /// @notice A container for the proposal parameters at the time of proposal creation.
    /// @param supportThreshold The support threshold value.
    /// The value has to be in the interval [0, 10^6] defined by `RATIO_BASE = 10**6`.
    /// @param startDate The start date of the proposal vote.
    /// @param endDate The end date of the proposal vote.
    /// @param snapshotEpoch The number of the proposal creation epoch.
    /// @param minVotingPower The minimum voting power needed.
    struct ProposalParameters {
        uint32 supportThreshold;
        uint64 startDate;
        uint64 endDate;
        uint64 snapshotEpoch;
        uint256 minVotingPower;
    }

    /// @notice A container for the proposal vote tally.
    /// @param abstain The number of abstain votes casted.
    /// @param yes The number of yes votes casted.
    /// @param no The number of no votes casted.
    struct Tally {
        uint256 abstain;
        uint256 yes;
        uint256 no;
    }

    /// @notice Returns all information for a proposal vote by its ID.
    /// @param proposalId The ID of the proposal.
    /// @return open Whether the proposal is open or not.
    /// @return executed Whether the proposal is executed or not.
    /// @return parameters The parameters of the proposal vote.
    /// @return tally The current tally of the proposal vote.
    /// @return actions The actions to be executed in the associated DAO after the proposal has passed.
    /// @return allowFailureMap The bit map representations of which actions are allowed to revert so tx still succeeds.
    function getProposal(uint256 proposalId) external view returns (
        bool open,
        bool executed,
        ProposalParameters memory parameters,
        Tally memory tally,
        IDAO.Action[] memory actions,
        uint256 allowFailureMap
    );

    /// @notice Checks if the support value defined as
    /// $$\texttt{support} = \frac{N_\text{yes}}{N_\text{yes}+N_\text{no}}$$
    /// for a proposal vote is greater than the support threshold.
    /// @param _proposalId The ID of the proposal.
    /// @return Returns `true` if the  support is greater than the support threshold and `false` otherwise.
    function isSupportThresholdReached(uint256 _proposalId) external view returns (bool);

    /// @notice Checks if the participation value defined as
    /// $$\texttt{participation} = \frac{N_\text{yes}+N_\text{no}+N_\text{abstain}}{N_\text{total}}$$
    /// for a proposal vote is greater or equal than the minimum participation value.
    /// @param _proposalId The ID of the proposal.
    /// @return Returns `true` if the participation is greater than the minimum participation and `false` otherwise.
    function isMinParticipationReached(uint256 _proposalId) external view returns (bool);

    /// @notice Checks if an account can participate on a proposal vote. This can be because the vote
    /// - has not started,
    /// - has ended,
    /// - was executed, or
    /// - the voter doesn't have voting powers.
    /// @param _proposalId The proposal Id.
    /// @param _account The account address to be checked.
    /// @param  _voteOption Whether the voter abstains, supports or opposes the proposal.
    /// @return Returns true if the account is allowed to vote.
    /// @dev The function assumes the queried proposal exists.
    function canVote(uint256 _proposalId, address _account, VoteOption _voteOption) external view returns (bool);

    /// @notice Checks if a proposal can be executed.
    /// @param _proposalId The ID of the proposal to be checked.
    /// @return True if the proposal can be executed, false otherwise.
    function canExecute(uint256 _proposalId) external view returns (bool);

    /// @notice Returns whether the account has voted for the proposal.
    /// Note, that this does not check if the account has voting power.
    /// @param _proposalId The ID of the proposal.
    /// @param _account The account address to be checked.
    /// @return The vote option cast by a voter for a certain proposal.
    function getVoteOption(uint256 _proposalId, address _account) external view returns (VoteOption);

    // # SETTINGS

    /// @notice Returns the support threshold parameter stored in the governance settings.
    /// @return The support threshold parameter.
    function supportThreshold() external view returns (uint32);

    /// @notice Returns the minimum participation parameter stored in the governance settings.
    /// @return The minimum participation parameter.
    function minParticipation() external view returns (uint32);

    /// @notice Returns the minimum duration parameter stored in the governance settings.
    /// @return The minimum duration parameter.
    function minDuration() external view returns (uint64);

    /// @notice Returns the minimum voting power required to create a proposal stored in the governance settings.
    /// @return The minimum voting power required to create a proposal.
    function minProposerVotingPower() external view returns (uint256);

    // # VOTING TOKEN

    /// @notice Getter function for the voting token.
    /// @return The token used for voting.
    function getVotingToken() external view returns (IVotesUpgradeable);

    /// @notice Returns the total voting power checkpointed for a specific epoch.
    /// @param _epoch The epoch to query.
    /// @return The total voting power.
    function totalVotingPower(uint256 _epoch) external view returns (uint256);

}
