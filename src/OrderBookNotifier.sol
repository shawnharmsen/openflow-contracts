// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.19;
import "./interfaces/ISettlement.sol";
import "./interfaces/IERC20.sol";

contract OrderBookNotifier {
    uint256 internal constant UID_LENGTH = 56;
    mapping(bytes => uint256) public filledAmount;
    mapping(bytes => bytes) public activeOrders;

    // Order types
    // - Multisig order
    // - Auction order

    // Harvest
    // Swap.....
    //

    event SubmitOrder(ISettlement.Payload payload);
    event OrderInvalidated(address indexed owner, bytes orderUid);

    function submitOrder(ISettlement.Payload memory payload) external {
        emit SubmitOrder(payload);
    }

    function invalidateOrder(bytes calldata orderUid) external {
        (, address owner, ) = extractOrderUidParams(orderUid);
        require(owner == msg.sender, "GPv2: caller does not own order");
        filledAmount[orderUid] = type(uint256).max;
        emit OrderInvalidated(owner, orderUid);
    }

    function extractOrderUidParams(
        bytes calldata orderUid
    ) public pure returns (bytes32 orderDigest, address owner, uint32 validTo) {
        require(orderUid.length == UID_LENGTH, "GPv2: invalid uid");
        assembly {
            orderDigest := calldataload(orderUid.offset)
            owner := shr(96, calldataload(add(orderUid.offset, 32)))
            validTo := shr(224, calldataload(add(orderUid.offset, 52)))
        }
    }
}
