// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;
import {IERC20} from "../src/interfaces/IERC20.sol";
import {ISettlement} from "../src/interfaces/ISettlement.sol";
import {OrderLib} from "../src/lib/Order.sol";

/// @author Openflow
/// @title Multisig Driver
/// @notice This contract manages the signing logic for Openflow multisig authenticated swap auctions.
contract Driver {
    /// @dev OrderLib is used to generate and decode unique UIDs per order.
    /// A UID consists of digest hash, owner and validTo.
    using OrderLib for bytes;

    /// @dev Settlement contract is used to build a digest hash given a payload.
    address public settlement;

    /// @dev Owner is responsible for signer management (adding/removing signers
    /// and maintaining signature threshold).
    address public owner;

    /// @dev In order for a multisig authenticated order to be executed the order
    /// must be signed by `signatureThreshold` trusted parties. This ensures that the
    /// optimal quote has been selected for a given auction. The main trust component here in multisig
    /// authenticated auctions is that the user is trusting the multisig to only sign quotes that will return
    /// the highest swap value to the end user.
    uint256 public signatureThreshold;

    /// @dev Signers is mapping of authenticated multisig signers.
    mapping(address => bool) public signers;

    /// @dev Initialize owner.
    /// @dev Owner must be a trusted multisig.
    /// @dev Owner can do three things:
    /// - Set signature threshold for multisig swap auctions
    /// - Update trusted signers for multisig swap auctions
    /// - Change owner
    constructor() {
        owner = msg.sender;
    }

    /// @notice Given a digest and encoded signatures, determine if a digest is approved by a
    /// sufficient number of multisig signers.
    /// @dev Reverts if not approved.
    function checkNSignatures(
        bytes32 digest,
        bytes memory signatures
    ) external view {
        ISettlement(settlement).checkNSignatures(
            address(this),
            digest,
            signatures,
            signatureThreshold
        );
    }

    /// @notice Add or remove trusted multisig signers.
    /// @dev Only owner is allowed to perform this action.
    /// @param _signers An array of signer addresses.
    /// @param _status If true, all signers in the array will be approved.
    /// If false all signers in the array will be unapproved.
    function setSigners(address[] memory _signers, bool _status) external {
        require(msg.sender == owner, "Only owner");
        for (uint256 signerIdx; signerIdx < _signers.length; signerIdx++) {
            signers[_signers[signerIdx]] = _status;
        }
    }

    /// @notice Set signature threshold.
    /// @dev Only owner is allowed to perform this action.
    function setSignatureThreshold(uint256 _signatureThreshold) external {
        require(msg.sender == owner, "Only owner");
        signatureThreshold = _signatureThreshold;
    }

    /// @notice Select a new owner.
    /// @dev Only owner is allowed to perform this action.
    function setOwner(address _owner) external {
        require(msg.sender == owner, "Only owner");
        owner = _owner;
    }

    /// @notice Initialize order manager.
    /// @dev Sets settlement.
    /// @dev Can only initialize once.
    /// @param _settlement New settlement address.
    function initialize(address _settlement) external {
        require(settlement == address(0), "Already initialized");
        settlement = _settlement;
    }
}
