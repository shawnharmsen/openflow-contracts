// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import {IOpenflowSdk} from "../interfaces/IOpenflow.sol";
import {OpenflowSdkProxy} from "./OpenflowSdkProxy.sol";

contract OpenflowFactory {
    address public settlement;
    address public owner;
    uint256 public currentVersion;
    mapping(uint256 => address) public implementationByVersion;

    constructor(address _settlement) {
        settlement = _settlement;
        owner = msg.sender;
    }

    function newSdkInstance() external returns (IOpenflowSdk sdk) {
        address _manager = msg.sender;
        return newSdkInstance(_manager);
    }

    function newSdkInstance(
        address _manager
    ) public returns (IOpenflowSdk sdk) {
        address _sender = msg.sender;
        address _recipient = msg.sender;
        return newSdkInstance(_manager, _sender, _recipient);
    }

    function newSdkVersion(address implementation) external {
        require(
            msg.sender == owner,
            "Only Openflow multisig can add new SDK versions"
        );
        currentVersion++;
        implementationByVersion[currentVersion] = implementation;
    }

    function newSdkInstance(
        address _manager,
        address _sender,
        address _recipient
    ) public returns (IOpenflowSdk sdk) {
        address currentImplementation = implementationByVersion[currentVersion];
        address sdkProxy = address(
            new OpenflowSdkProxy(currentImplementation, _manager)
        );
        sdk = IOpenflowSdk(sdkProxy);
        sdk.initialize(
            settlement,
            _manager,
            _sender,
            _recipient,
            currentVersion
        );
    }

    /// @notice Clones using EIP-1167 template
    function _cloneWithTemplateAddress(
        address templateAddress
    ) internal returns (address poolAddress) {
        bytes20 _templateAddress = bytes20(templateAddress);
        assembly {
            let clone := mload(0x40)
            mstore(
                clone,
                0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000
            )
            mstore(add(clone, 0x14), _templateAddress)
            mstore(
                add(clone, 0x28),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )
            poolAddress := create(0, clone, 0x37)
        }
    }
}
