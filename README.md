# Web3 Hacks

复现下 Web3 上以往的攻击事件,学习 Web3 安全审计

## 2023-01-10 BRA

[BRA.exp.sol](./test/BRA.exp.sol)

`forge test -contract ./test/BRA.exp.sol -vvv`

漏洞: 漏洞发生在 BRA 代币的本身上,在 BRA 代币的合约实现逻辑上,其 **\_transfer()** 函数针对代币对交易收取 tax,但是没有加上 sync,可以满足两个 if 条件判断,导致可以收取两次 tax,使得代币增发。

![BRA-_transfer()_BUG](images/BRA_BUG.jpeg)
