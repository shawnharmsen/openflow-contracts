// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;
import {IOpenflowSdk} from "../interfaces/IOpenflow.sol";
import {OpenflowSdkProxy} from "./OpenflowSdkProxy.sol";

contract OpenflowFactory {
    address public settlement; // Settlement address.
    address public owner; // Owner of the factory. Should be Openflow multisig.
    uint256 public currentVersion; // Current official release version of the SDK.

    /// @dev Map SDK release versions to implementation addresses.
    mapping(uint256 => address) public implementationByVersion;

    /// @dev Initialize the factory.
    constructor(address _settlement) {
        settlement = _settlement;
        owner = msg.sender;
    }

    /// @notice Generate a new SDK instance with default settings.
    /// @dev Generally it makes more sense for users to use the method below where
    /// manager can be specified. Use this method if your SDK instance manager
    /// is the smart contract initiator itself rather than EOA.
    /// @return sdk Openflow SDK instance
    function newSdkInstance() external returns (IOpenflowSdk sdk) {
        address _manager = msg.sender;
        return newSdkInstance(_manager);
    }

    /// @notice Generate a new SDK instance with a user specified manager.
    /// @param _manager Address of the SDK instance manager.
    /// @return sdk Openflow SDK instance
    function newSdkInstance(
        address _manager
    ) public returns (IOpenflowSdk sdk) {
        address _sender = msg.sender;
        address _recipient = msg.sender;
        return newSdkInstance(_manager, _sender, _recipient);
    }

    /// @notice Generate an SDK instance with custom manager, sender and recipient.
    /// @param _manager Address of the SDK instance manager.
    /// @param _sender Address of SDK's default sender.
    /// @param _recipient Address of SDK's default recipient.
    /// @return sdk Openflow SDK instance
    function newSdkInstance(
        address _manager,
        address _sender,
        address _recipient
    ) public returns (IOpenflowSdk sdk) {
        address sdkProxy = address(
            new OpenflowSdkProxy(currentImplementation(), _manager)
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

    /// @notice Publish a new official SDK version.
    /// @dev Only factory owner can publish new versions.
    function newSdkVersion(address implementation) external {
        require(
            msg.sender == owner,
            "Only Openflow multisig can add new SDK versions"
        );
        currentVersion++;
        implementationByVersion[currentVersion] = implementation;
    }

    /// @notice Fetch current implementation
    /// @return implementation Current implementation
    function currentImplementation()
        public
        view
        returns (address implementation)
    {
        implementation = implementationByVersion[currentVersion];
    }
}
