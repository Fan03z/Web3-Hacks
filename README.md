# Web3 Hacks

复现下 Web3 上以往的攻击事件,学习 Web3 安全审计

## 2023-01-10 BRA

[BRA.exp.sol](./test/BRA.exp.sol)

`forge test --match-path ./test/BRA.exp.sol -vvv`

[Phalcon View](https://explorer.phalcon.xyz/tx/bsc/0x4e5b2efa90c62f2b62925ebd7c10c953dc73c710ef06695eac3f36fe0f6b9348)

#### 漏洞

漏洞发生在 BRA 代币的本身上,在 BRA 代币的合约实现逻辑上,其 **\_transfer()** 函数针对代币对交易收取 tax,但是没有加上 sync,可以满足两个 if 条件判断,导致可以收取两次 tax,使得代币增发。

![BRA-_transfer()_BUG](images/BRA_BUG.jpeg)

## 2022-08-01 NomadBridge

[NomadBridge.exp.sol](./test/NomadBridge.exp.sol)

`forge test --match-path ./test/NomadBridge.exp.sol -vvv`

Nomad Bridge 跨链桥攻击算得上是 2022 年的最大 Web3 攻击事件了,涉及 1.52 亿 $,这金额也是天文数字了,虽然攻击需要对跨链桥技术和默尔克树证明在其中验证的作用有一定的理解,但攻击实现的代码不长,甚至 gas 费都没花多少,却可以实现用 0.01 个 WBTC 套 100 个 WBTC.
不止这复现的第一次的攻击合约,在其后面还有很多次攻击,只要换个目标代币去攻击,或者换一个验证信息(InputData)重复攻击 WBTC 都可以.

#### 漏洞

Nomad Bridge 跨链桥采用 Merkle-Proof 来验证用户的请求是否有效,其中具体的实现是先通过调用 链桥锁仓合约 Replica 中的 **process()** 函数,将请求信息传递给跨链桥合约

![NomadBridge_process()](<images/NomadBridge_process().jpeg>)

process() 函数中的验证过程首先通过传入请求消息的哈希找到对应的 Merkle-Root，然后将 Merkle root 传递给 **acceptableRoot()** 函数来查看是否合法

![NomadBridge_acceptableRoot()](<images/NomadBridge_acceptableRoot().jpeg>)

通过上面代码可知, acceptableRoot() 函数要求 Merkle-Root 已经被证明或者未被处理,这两种情况都会直接返回. 如果都不是这两种情况,函数将尝试查询 **confirmAt[]** 映射来查找 Merkle-Root 是否在之前的某个时间点被确认

但是问题就是出在 confirmAt[] 查询上,如果 Merkle-Root 未被确认,则对应的 confirmAt[] 映射结果应为 0,但事实上, **confirmAt[0]** 为 **1**,而在 EVM 智能合约存储中，所有位置（slot）初始值就为 0(0x00),这时只要传入任何此前未被验证过的消息,就可以绕过整段验证流程了,最后结果被验证上为真,跨链桥向攻击者发送对应的解锁代币仓请求,就完成攻击了

![NomadBridge_confirmAt[]](images/NomadBridge_confirmAt[].jpeg)

[具体分析](https://github.com/SunWeb3Sec/DeFiHackLabs/tree/main/academy/onchain_debug/07_Analysis_nomad_bridge/)

[具体漏洞分析](https://twitter.com/BlockSecTeam/status/1554335271964987395)
