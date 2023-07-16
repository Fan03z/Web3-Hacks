# Web3 Hacks

复现下 Web3 上以往的攻击事件,学习 Web3 安全审计

## 2023-01-10 BRA

[BRA.exp.sol](./test/BRA.exp.sol)

`forge test --match-path ./test/BRA.exp.sol -vvv`

[Phalcon View](https://explorer.phalcon.xyz/tx/bsc/0x4e5b2efa90c62f2b62925ebd7c10c953dc73c710ef06695eac3f36fe0f6b9348)

**漏洞**: 漏洞发生在 BRA 代币的本身上,在 BRA 代币的合约实现逻辑上,其 **\_transfer()** 函数针对代币对交易收取 tax,但是没有加上 sync,可以满足两个 if 条件判断,导致可以收取两次 tax,使得代币增发。

![BRA-_transfer()_BUG](images/BRA_BUG.jpeg)

## 2022-08-01 NomadBridge

[NomadBridge.exp.sol](./test/NomadBridge.exp.sol)

`forge test --match-path ./test/NomadBridge.exp.sol -vvv`

Nomad Bridge 跨链桥攻击算得上是 2022 年的最大 Web3 攻击事件了,涉及 1.52 亿 $,这金额也是天文数字了,虽然攻击需要对跨链桥技术和默尔克树在其中验证的作用有一定的理解,但攻击实现的代码不长,甚至 gas 费都没花多少,却可以用 0.01 个 WBTC 套 100 个 WBTC.
不止这复现的第一轮合约,往后还有很多次攻击,只要换个目标代币去攻击,或者换一个验证信息(InputData)重复攻击 WBTC 都可以.

[具体分析](https://github.com/SunWeb3Sec/DeFiHackLabs/tree/main/academy/onchain_debug/07_Analysis_nomad_bridge/)
