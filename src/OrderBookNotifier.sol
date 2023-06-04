// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.19;
import "./interfaces/ISettlement.sol";
import "./interfaces/IERC20.sol";

contract OrderBookNotifier {
    event SubmitOrder(ISettlement.Payload payload);
    event CancelOrder(bytes32 digest);

    function submitOrder(ISettlement.Payload memory payload) external {
        emit SubmitOrder(payload);
    }

    // TODO: Refactor
    function cancelOrders() external {
        // emit CancelOrder(digest);
    }
}
