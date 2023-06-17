// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import {ISafe} from "../test/interfaces/IGnosisSafe.sol";
import {GnosisHelper} from "../test/support/GnosisHelper.sol";
import "../test/support/Storage.sol";
import "forge-std/Test.sol";

contract GnosisTest is GnosisHelper {
    ISafe safeA;
    ISafe safeB;
    ISafe safeC;
    bytes4 private constant _EIP1271_MAGICVALUE = 0x1626ba7e;
    uint256 public constant INITIAL_TOKEN_AMOUNT = 100 * 1e6; // 100 USDC
    IERC20 public fromToken = IERC20(usdc);
    IERC20 public toToken = IERC20(weth);

    /// @notice notice Create 3 Gnosis Safes:
    /// - SafeA owners:
    ///   - userA
    ///   - userB
    /// - SafeB owners:
    ///   - userA
    /// - SafeC owners:
    ///   - safeA
    ///   - safeB
    function setUp() public {
        startHoax(userA);
        /// @dev SafeA is a simple safe with two EOA owners.
        address[] memory owners = new address[](2);
        owners[0] = userA;
        owners[1] = userB;
        safeA = ISafe(newSafe(owners));
        console.log("Safe A", address(safeA));
        uint256 signatureThreshold = safeA.getThreshold();
        require(signatureThreshold == 2, "Incorrect threshold");
        require(
            safeA.getOwners().length == signatureThreshold,
            "Incorrect owner count"
        );

        /// @dev SafeB has one EOA owner.
        owners = new address[](1);
        owners[0] = userA;
        safeB = ISafe(newSafe(owners));
        console.log("Safe B", address(safeB));

        /// @dev SafeC has two owners (SafeA and SafeB).
        changePrank(address(safeA));
        owners = new address[](2);
        owners[0] = address(safeA);
        owners[1] = address(safeB);
        safeC = ISafe(newSafe(owners));
        console.log("Safe C", address(safeC));
        changePrank(userA);
    }

    function testGnosisSafeEip1271SimpleSwap() external {
        /// @dev Give safe A 100 fromToken.
        deal(address(fromToken), address(safeA), INITIAL_TOKEN_AMOUNT);

        /// @dev Allow settlement to spend fromToken from Gnosis Safe.
        changePrank(address(safeA));
        fromToken.approve(address(settlement), type(uint256).max);
        changePrank(address(userA));

        /// @dev Get quote from sample aggregator.
        uint256 fromAmount = 100 * 1e6;
        require(fromAmount > 0, "Invalid fromAmount");
        UniswapV2Aggregator.Quote memory quote = uniswapAggregator.quote(
            fromAmount,
            address(fromToken),
            address(toToken)
        );
        uint256 slippageBips = 20;
        uint256 toAmount = (quote.quoteAmount * (10000 - slippageBips)) / 10000;

        /// @dev Build payload.
        ISettlement.Hooks memory hooks; // Optional pre and post swap hooks.
        ISettlement.Payload memory payload = ISettlement.Payload({
            fromToken: address(fromToken),
            toToken: address(toToken),
            fromAmount: fromAmount,
            toAmount: toAmount,
            sender: address(safeA),
            recipient: address(safeA),
            deadline: uint32(block.timestamp),
            scheme: ISettlement.Scheme.Eip1271,
            hooks: hooks
        });

        /// @dev Build digest. Order digest is what will be signed.
        bytes32 orderDigest = settlement.buildDigest(payload);

        /// @dev Sign order digest
        bytes memory safeASignature;
        {
            bytes memory orderDigestAsBytes = abi.encodePacked(orderDigest);
            bytes32 safeDigest = safeA.getMessageHashForSafe(
                address(safeA),
                orderDigestAsBytes
            );
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(
                _USER_A_PRIVATE_KEY,
                safeDigest
            );
            bytes memory userASignature = abi.encodePacked(r, s, v);
            (v, r, s) = vm.sign(_USER_B_PRIVATE_KEY, safeDigest);
            bytes memory userBSignature = abi.encodePacked(r, s, v);

            /// @dev Derived signatories must be in sequential order
            safeASignature = abi.encodePacked(userASignature, userBSignature);
        }
        require(
            safeA.isValidSignature(bytes32(orderDigest), safeASignature) ==
                _EIP1271_MAGICVALUE,
            "Bad signature"
        );

        //////////////////// Solver execution ////////////////////

        /// @dev Build executor data.
        bytes memory executorData = abi.encode(
            OrderExecutor.Data({
                fromToken: fromToken,
                toToken: toToken,
                fromAmount: fromAmount,
                toAmount: toAmount,
                recipient: address(safeA),
                target: address(uniswapAggregator),
                payload: abi.encodeWithSelector(
                    UniswapV2Aggregator.executeOrder.selector,
                    quote.routerAddress,
                    quote.path,
                    fromAmount,
                    toAmount
                )
            })
        );

        bytes memory signatures = abi.encodePacked(
            hex"000000000000000000000000",
            address(safeA),
            bytes32(uint256(65 * 1)),
            hex"00",
            bytes32(uint256(safeASignature.length)),
            safeASignature
        );

        /// @dev Build order using
        ISettlement.Order memory order = ISettlement.Order({
            signature: signatures,
            data: executorData,
            payload: payload
        });
        /// @dev Execute order
        ISettlement.Interaction[][2] memory solverInteractions;
        executor.executeOrder(order, solverInteractions);
    }

    /// @dev Sample simple Gnosis Safe signing without OpenFlow
    function testSafeEip1271SimpleSign() external {
        bytes
            memory orderDigest = hex"9de4c55938fc5d093859fb29a973a31dfd516c76d39063470be94ad8518874a0";

        bytes32 safeDigest = safeA.getMessageHashForSafe(
            address(safeA),
            orderDigest
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            _USER_A_PRIVATE_KEY,
            safeDigest
        );
        bytes memory userASignature = abi.encodePacked(r, s, v);
        (v, r, s) = vm.sign(_USER_B_PRIVATE_KEY, safeDigest);
        bytes memory userBSignature = abi.encodePacked(r, s, v);

        // Derived signatories must be in sequential order
        bytes memory signature = abi.encodePacked(
            userASignature,
            userBSignature
        );
        require(
            safeA.isValidSignature(bytes32(orderDigest), signature) ==
                _EIP1271_MAGICVALUE,
            "Bad signature"
        );
    }

    /// @dev Sample complex Gnosis Safe signing without OpenFlow
    function testSafeEip1271ComplexSign() external {
        bytes
            memory orderDigest = hex"9de4c55938fc5d093859fb29a973a31dfd516c76d39063470be94ad8518874a0";

        // Create safe digests
        bytes32 safeADigest = safeA.getMessageHashForSafe(
            address(safeA),
            orderDigest
        );
        bytes32 safeBDigest = safeB.getMessageHashForSafe(
            address(safeB),
            orderDigest
        );

        // Sign safe B digest from user A (the only safe owner)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            _USER_A_PRIVATE_KEY,
            safeBDigest
        );
        bytes memory userASafeBSignature = abi.encodePacked(r, s, v);
        bytes memory safeBSignature = abi.encodePacked(userASafeBSignature);
        require(
            safeB.isValidSignature(bytes32(orderDigest), safeBSignature) ==
                _EIP1271_MAGICVALUE,
            "Invalid safe B signature"
        );

        // Sign safe A digest from user A (1 of 2)
        (v, r, s) = vm.sign(_USER_A_PRIVATE_KEY, safeADigest);
        bytes memory userASafeASignature = abi.encodePacked(r, s, v);

        // Sign safe A digest from user A (2 of 2)
        (v, r, s) = vm.sign(_USER_B_PRIVATE_KEY, safeADigest);
        bytes memory userBSafeASignature = abi.encodePacked(r, s, v);

        // Combined signature
        bytes memory safeASignature = abi.encodePacked(
            userASafeASignature,
            userBSafeASignature
        );
        require(
            safeA.isValidSignature(bytes32(orderDigest), safeASignature) ==
                _EIP1271_MAGICVALUE,
            "Invalid safe A signature"
        );

        require(address(safeB) > address(safeA), "Invalid safe signer order");

        // Now generate joint signature using Gnosis packed contract encoding
        // https://docs.safe.global/learn/safe-core/safe-core-protocol/signatures
        bytes memory safeCSignature = abi.encodePacked(
            hex"000000000000000000000000",
            address(safeA),
            bytes32(uint256(65 * 2)),
            hex"00",
            hex"000000000000000000000000",
            address(safeB),
            bytes32(uint256((65 * 2) + 0x20 + safeASignature.length)),
            hex"00",
            bytes32(uint256(safeASignature.length)),
            safeASignature,
            bytes32(uint256(safeBSignature.length)),
            safeBSignature
        );
        require(
            safeC.isValidSignature(bytes32(orderDigest), safeCSignature) ==
                _EIP1271_MAGICVALUE,
            "Invalid safe C signature"
        );
    }
}
