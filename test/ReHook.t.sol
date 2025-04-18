// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {Constants} from "v4-core/test/utils/Constants.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {ReHook} from "../src/ReHook.sol";
import {console2} from "forge-std/console2.sol";

contract ReHookTest is Test, Deployers {

    using SafeCast for *;

    address hook;

    uint256 userPrivateKey;
    address user1;
    address user2;
    address user3;
    address user4;

    function setUp() public {
        initializeManagerRoutersAndPoolsWithLiq(IHooks(address(0)));
    }
    function adduser() public{
        user1 = vm.addr(1);
        user2 = vm.addr(2);
        user3 = vm.addr(3);
        user4 = vm.addr(4);
        key.currency0.transfer(address(user1), 10e18);
        key.currency1.transfer(address(user1), 10e18);
        key.currency0.transfer(address(user2), 10e18);
        key.currency1.transfer(address(user2), 10e18);
        key.currency0.transfer(address(user3), 10e18);
        key.currency1.transfer(address(user3), 10e18);
        _setApprovalsFor(user1, address(Currency.unwrap(key.currency0)));
        _setApprovalsFor(user1, address(Currency.unwrap(key.currency1)));
        _setApprovalsFor(user2, address(Currency.unwrap(key.currency0)));
        _setApprovalsFor(user2, address(Currency.unwrap(key.currency1)));
        _setApprovalsFor(user3, address(Currency.unwrap(key.currency0)));
        _setApprovalsFor(user3, address(Currency.unwrap(key.currency1)));
        _setApprovalsFor(user4, address(Currency.unwrap(key.currency0)));
        _setApprovalsFor(user4, address(Currency.unwrap(key.currency1)));
    }
    function testHook() public {

        address impl = address(new ReHook(manager));
        address hookAddr = address(uint160(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG|Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG|Hooks.AFTER_ADD_LIQUIDITY_FLAG| Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG));
        _etchHookAndInitPool(hookAddr, impl);
        adduser();
        
        // test1 for adding liquidity
        IPoolManager.ModifyLiquidityParams memory AL1params = IPoolManager.ModifyLiquidityParams({ // 1e18
            tickLower: TickMath.MIN_TICK,
            tickUpper: TickMath.MAX_TICK,
            liquidityDelta: 1e18,
            salt: 0
        });
        // test2 for adding liquidity
        IPoolManager.ModifyLiquidityParams memory AL2params = IPoolManager.ModifyLiquidityParams({ // 7*1e17
            tickLower: TickMath.MIN_TICK,
            tickUpper: TickMath.MAX_TICK,
            liquidityDelta: 7*1e17,
            salt: 0
        });
        // test3 for adding liquidity
        IPoolManager.ModifyLiquidityParams memory AL3params = IPoolManager.ModifyLiquidityParams({ // -5*1e17
            tickLower: TickMath.MIN_TICK,
            tickUpper: TickMath.MAX_TICK,
            liquidityDelta: -5*1e17,
            salt: 0
        });
        // test4 for adding liquidity
        IPoolManager.ModifyLiquidityParams memory AL4params = IPoolManager.ModifyLiquidityParams({ // -6*1e7
            tickLower: TickMath.MIN_TICK,
            tickUpper: TickMath.MAX_TICK,
            liquidityDelta: -6*1e7,
            salt: 0
        });

        // test1 for beforeSwap
        IPoolManager.SwapParams memory SW1params = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: 1e10,
            sqrtPriceLimitX96: false ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
        });
        // test2 for beforeSwap
        IPoolManager.SwapParams memory SW2params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 1e9,
            sqrtPriceLimitX96: true ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
        });

        vm.startPrank(user1);
        bytes32 message = keccak256(abi.encode(key));
        userPrivateKey = 1;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, message);
        bytes memory signature = abi.encodePacked(bytes32(r), bytes32(s), uint8(v));
        bytes memory hookData = signature;
        printlog();
        modifyLiquidityRouter.modifyLiquidity(key, AL1params, hookData, false, true);
        swapRouter.swap(key, SW2params, _defaultTestSettings(), ZERO_BYTES);
        vm.warp(block.timestamp + 1 hours);
        printlog();
        swapRouter.swap(key, SW1params, _defaultTestSettings(), ZERO_BYTES);
        printlog();

        // do some swaps
        for(int256 i = 1; i < 10; i++) {
            vm.warp(block.timestamp + 1 hours);
            IPoolManager.SwapParams memory SWparams = IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: i*1e9,
                sqrtPriceLimitX96: true ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
            });
            swapRouter.swap(key, SWparams, _defaultTestSettings(), ZERO_BYTES);
        }
        // checek the hook balance
        assertEq(MockERC20(Currency.unwrap(key.currency0)).balanceOf(hook), 46*1e7); // 46 = 1+1+2+3+4+5+6+7+8+9
        vm.stopPrank();

        vm.startPrank(user2);
        userPrivateKey = 2;
        (v, r, s) = vm.sign(userPrivateKey, message);
        signature = abi.encodePacked(bytes32(r), bytes32(s), uint8(v));
        hookData = signature;
        vm.warp(block.timestamp + 2 hours);
        printlog();
        modifyLiquidityRouter.modifyLiquidity(key, AL1params, hookData, false, true);
        vm.warp(block.timestamp + 3 hours);
        printlog();
        uint256 hookBalanceBeforeClaim0 = MockERC20(Currency.unwrap(key.currency0)).balanceOf(hook);
        uint256 hookBalanceBeforeClaim1 = MockERC20(Currency.unwrap(key.currency1)).balanceOf(hook);
        vm.warp(block.timestamp + 4 hours);
        printlog();
        modifyLiquidityRouter.modifyLiquidity(key, AL2params, hookData, false, true);
        uint256 hookBalanceAfterClaim0 = MockERC20(Currency.unwrap(key.currency0)).balanceOf(hook);
        uint256 hookBalanceAfterClaim1 = MockERC20(Currency.unwrap(key.currency1)).balanceOf(hook);
        vm.warp(block.timestamp + 5 hours);
        printlog();
        assertGt(hookBalanceBeforeClaim0, hookBalanceAfterClaim0);
        assertGt(hookBalanceBeforeClaim1, hookBalanceAfterClaim1);
        vm.warp(block.timestamp + 6 hours);
        printlog();
        swapRouter.swap(key, SW2params, _defaultTestSettings(), ZERO_BYTES);
        vm.warp(block.timestamp + 7 hours);
        printlog();
        
        vm.stopPrank();

        vm.startPrank(user1);
        userPrivateKey = 1;
        (v, r, s) = vm.sign(userPrivateKey, message);
        signature = abi.encodePacked(bytes32(r), bytes32(s), uint8(v));
        hookData = signature;

        modifyLiquidityRouter.modifyLiquidity(key, AL2params, hookData, false, true);
        vm.warp(block.timestamp + 8 hours);
        printlog();
        hookBalanceBeforeClaim0 = MockERC20(Currency.unwrap(key.currency0)).balanceOf(hook);
        hookBalanceBeforeClaim1 = MockERC20(Currency.unwrap(key.currency1)).balanceOf(hook);
        vm.warp(block.timestamp + 9 hours);
        printlog();
        modifyLiquidityRouter.modifyLiquidity(key, AL1params, hookData, false, true);
        hookBalanceAfterClaim0 = MockERC20(Currency.unwrap(key.currency0)).balanceOf(hook);
        hookBalanceAfterClaim1 = MockERC20(Currency.unwrap(key.currency1)).balanceOf(hook);
        vm.warp(block.timestamp + 10 hours);
        printlog();
        assertGt(hookBalanceBeforeClaim0, hookBalanceAfterClaim0);
        assertGt(hookBalanceBeforeClaim1, hookBalanceAfterClaim1);
        vm.warp(block.timestamp + 11 hours);
        printlog();
        swapRouter.swap(key, SW2params, _defaultTestSettings(), ZERO_BYTES);
        vm.warp(block.timestamp + 12 hours);
        printlog();
        
        vm.stopPrank();

        vm.startPrank(user2);
        userPrivateKey = 2;
        (v, r, s) = vm.sign(userPrivateKey, message);
        signature = abi.encodePacked(bytes32(r), bytes32(s), uint8(v));
        hookData = signature;
        vm.warp(block.timestamp + 13 hours);
        printlog();
        modifyLiquidityRouter.modifyLiquidity(key, AL3params, hookData, false, true);
        vm.warp(block.timestamp + 14 hours);
        printlog();
        hookBalanceBeforeClaim0 = MockERC20(Currency.unwrap(key.currency0)).balanceOf(hook);
        hookBalanceBeforeClaim1 = MockERC20(Currency.unwrap(key.currency1)).balanceOf(hook);
        vm.warp(block.timestamp + 15 hours);
        printlog();
        modifyLiquidityRouter.modifyLiquidity(key, AL4params, hookData, false, true);
        hookBalanceAfterClaim0 = MockERC20(Currency.unwrap(key.currency0)).balanceOf(hook);
        hookBalanceAfterClaim1 = MockERC20(Currency.unwrap(key.currency1)).balanceOf(hook);
        vm.warp(block.timestamp + 16 hours);
        printlog();
        assertGt(hookBalanceBeforeClaim0, hookBalanceAfterClaim0);
        assertGt(hookBalanceBeforeClaim1, hookBalanceAfterClaim1);
        vm.warp(block.timestamp + 17 hours);
        printlog();
        
        vm.stopPrank();

        console2.log("hook balance", MockERC20(Currency.unwrap(key.currency0)).balanceOf(hook));
        console2.log("hook balance", MockERC20(Currency.unwrap(key.currency1)).balanceOf(hook));
    }
    function _etchHookAndInitPool(address hookAddr, address implAddr) internal {
        vm.etch(hookAddr, implAddr.code);
        hook = hookAddr;
        (key,) = initPoolAndAddLiquidity(currency0, currency1, IHooks(hook), 100, SQRT_PRICE_1_1);
    }
    function _defaultTestSettings() internal returns (PoolSwapTest.TestSettings memory testSetting) {
        return PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
    }
    function _setApprovalsFor(address _user, address token) internal {
        address[8] memory toApprove = [
            address(swapRouter),
            address(swapRouterNoChecks),
            address(modifyLiquidityRouter),
            address(modifyLiquidityNoChecks),
            address(donateRouter),
            address(takeRouter),
            address(claimsRouter),
            address(nestedActionRouter.executor())
        ];

        for (uint256 i = 0; i < toApprove.length; i++) {
            vm.prank(_user);
            MockERC20(token).approve(toApprove[i], Constants.MAX_UINT256);
        }
    }

    function printlog() internal {
        console2.log("time: ", block.timestamp);
        console2.log("hook 0: ", MockERC20(Currency.unwrap(key.currency0)).balanceOf(hook));
        console2.log("hook 1: ", MockERC20(Currency.unwrap(key.currency1)).balanceOf(hook));
        console2.log("-----------");
    }
}
