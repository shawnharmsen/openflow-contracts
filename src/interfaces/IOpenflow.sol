// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IOpenflowSdk {
    struct Options {
        /// @dev Driver is responsible for authenticating quote selection.
        /// If no driver is set anyone with the signature will be allowed
        /// to execute the signed payload. Driver is user-configurable
        /// which means the end user does not have to trust Openflow driver
        /// multisig. If the user desires, the user can run their own
        /// decentralized multisig driver.
        address driver;
        /// @dev Oracle is responsible for determining minimum amount out for an order.
        /// If no oracle is provided the default Openflow oracle will be used.
        address oracle;
        /// @dev Acceptable slippage threshold denoted in BIPs.
        uint256 slippageBips;
        /// @dev Maximum duration for auction. The order is invalid after the auction ends.
        uint256 auctionDuration;
        /// @dev Manager is responsible for managing SDK options.
        address manager;
        /// @dev Funds will be transferred to settlement from this sender.
        address sender;
        /// @dev Funds will be sent to recipient after swap.
        address recipient;
    }

    function swap(
        address fromToken,
        address toToken
    ) external returns (bytes memory orderUid);

    function options() external view returns (Options memory options);

    function setOptions(Options memory options) external;
}

interface IOpenflowFactory {
    function newSdkInstance() external returns (IOpenflowSdk sdkInstance);

    function newSdkInstance(
        address manager
    ) external returns (IOpenflowSdk sdkInstance);

    function newSdkInstance(
        address manager,
        address sender,
        address recipient
    ) external returns (IOpenflowSdk sdkInstance);
}
