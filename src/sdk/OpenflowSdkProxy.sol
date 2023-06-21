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
        0xbc0b033692987f57b00e59fb320fa52dee8008f8dd89a9404b16c6c70befc06d; // keccak256('openflow.sdk.factory')
    bytes32 constant _VERSION_SLOT =
        0xd9b5749cb01e4e7fad114e8dee44b84863de878d17f808275ae4b45e0620d128; // keccak256('openflow.sdk.version')

    /// @notice Initialize proxy.
    constructor(
        address _implementationAddress,
        address _ownerAddress
    ) OpenflowProxy(_implementationAddress, _ownerAddress) {
        uint256 currentVersion = IOpenflowFactory(msg.sender).currentVersion();
        assembly {
            sstore(_FACTORY_SLOT, caller())
            sstore(_VERSION_SLOT, currentVersion)
        }
    }

    /// @notice Fetch current factory address.
    function factory() public view returns (address _factoryAddress) {
        assembly {
            _factoryAddress := sload(_FACTORY_SLOT)
        }
    }

    /// @notice Fetch current implementation version.
    function implementationVersion() public view returns (address _version) {
        assembly {
            _version := sload(_VERSION_SLOT)
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
        assembly {
            sstore(_VERSION_SLOT, version)
        }
        uint256 currentVersion = IOpenflowFactory(factory()).currentVersion();
        require(version <= currentVersion && version != 0, "Invalid version");
        address implementation = IOpenflowFactory(factory())
            .implementationByVersion(version);
        _updateImplementation(implementation);
    }
}
