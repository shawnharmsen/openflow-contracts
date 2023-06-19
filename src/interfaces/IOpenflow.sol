// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IOpenflowSdk {
    function swap(
        address fromToken,
        address toToken
    ) external returns (bytes memory orderUid);
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
