// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import {IOpenflowFactory} from "../interfaces/IOpenflow.sol";

/// @title OpenflowSdkProxy
/// @author Openflow
/// @notice Minimal upgradeable EIP-1967 proxy
/// @dev Each SDK instance gets its own proxy contract
/// @dev Only instance owner can update implementation
/// @dev Implementation can be updated from official SDK releases (from factory)
/// or alternatively user can provide their own SDK implementation
contract OpenflowSdkProxy {
    bytes32 constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc; // keccak256('eip1967.proxy.implementation')
    bytes32 constant _OWNER_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103; // keccak256('eip1967.proxy.admin')
    bytes32 constant _FACTORY_SLOT =
        0x59518be4244033293ff114b9adbe6af243c48e1725af3a8f6be4e61b988ce0a9; // keccak256('openflow.factory')

    constructor(address _implementationAddress, address _ownerAddress) {
        assembly {
            sstore(_IMPLEMENTATION_SLOT, _implementationAddress)
            sstore(_OWNER_SLOT, _ownerAddress)
            sstore(_FACTORY_SLOT, caller())
        }
    }

    function implementationAddress()
        external
        view
        returns (address _implementationAddress)
    {
        assembly {
            _implementationAddress := sload(_IMPLEMENTATION_SLOT)
        }
    }

    function owner() public view returns (address _ownerAddress) {
        assembly {
            _ownerAddress := sload(_OWNER_SLOT)
        }
    }

    function factory() public view returns (address _factoryAddress) {
        assembly {
            _factoryAddress := sload(_FACTORY_SLOT)
        }
    }

    function updateImplementation(address _implementation) external {
        require(
            msg.sender == owner() || msg.sender == address(this),
            "Only owner can update implementation"
        );
        _updateImplementation(_implementation);
    }

    function updateSdkVersion() external {
        uint256 currentVersion = IOpenflowFactory(factory()).currentVersion();
        updateSdkVersion(currentVersion);
    }

    function updateSdkVersion(uint256 version) public {
        require(msg.sender == owner(), "Only owner can update SDK version");
        address implementation = IOpenflowFactory(factory())
            .implementationByVersion(version);
        _updateImplementation(implementation);
    }

    function _updateImplementation(address _implementation) internal {
        assembly {
            sstore(_IMPLEMENTATION_SLOT, _implementation)
        }
    }

    function updateOwner(address _owner) external {
        require(msg.sender == owner(), "Only owners can update owners");
        assembly {
            sstore(_OWNER_SLOT, _owner)
        }
    }

    fallback() external {
        assembly {
            let contractLogic := sload(_IMPLEMENTATION_SLOT)
            calldatacopy(0x0, 0x0, calldatasize())
            let success := delegatecall(
                gas(),
                contractLogic,
                0x0,
                calldatasize(),
                0,
                0
            )
            let returnDataSize := returndatasize()
            returndatacopy(0, 0, returnDataSize)
            switch success
            case 0 {
                revert(0, returnDataSize)
            }
            default {
                return(0, returnDataSize)
            }
        }
    }
}
