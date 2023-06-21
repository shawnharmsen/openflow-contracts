// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import {IOpenflowFactory} from "../interfaces/IOpenflow.sol";
import {OpenflowProxy} from "../sdk/OpenflowProxy.sol";

/// @title OpenflowSdkProxy
/// @author Openflow
/// @dev Each SDK instance gets its own proxy contract
/// @dev Only instance owner can update implementation
/// @dev Implementation can be updated from official SDK releases (from factory)
/// or alternatively user can provide their own SDK implementation
contract OpenflowSdkProxy is OpenflowProxy {
    bytes32 constant _FACTORY_SLOT =
        0x59518be4244033293ff114b9adbe6af243c48e1725af3a8f6be4e61b988ce0a9; // keccak256('openflow.factory')

    /// @notice Initialize proxy.
    constructor(
        address _implementationAddress,
        address _ownerAddress
    ) OpenflowProxy(_implementationAddress, _ownerAddress) {
        assembly {
            sstore(_FACTORY_SLOT, caller())
        }
    }

    /// @notice Fetch current factory address.
    function factory() public view returns (address _factoryAddress) {
        assembly {
            _factoryAddress := sload(_FACTORY_SLOT)
        }
    }

    /// @notice Update to the latest SDK version.
    /// @dev SDK version comes from factory.
    /// @dev Only proxy owner can update version.
    function updateSdkVersion() external {
        uint256 currentVersion = IOpenflowFactory(factory()).currentVersion();
        updateSdkVersion(currentVersion);
    }

    /// @notice Update version to a specific factory SDK version
    /// @dev Also supports downgrades.
    /// @dev Only proxy owner can update version.
    /// @param version Version to update to.
    function updateSdkVersion(uint256 version) public {
        require(msg.sender == owner(), "Only owner can update SDK version");
        uint256 currentVersion = IOpenflowFactory(factory()).currentVersion();
        require(version <= currentVersion && version != 0, "Invalid version");
        address implementation = IOpenflowFactory(factory())
            .implementationByVersion(version);
        _updateImplementation(implementation);
    }
}
