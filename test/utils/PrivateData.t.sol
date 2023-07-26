// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// 访问私有数据
// 合约里别放私有数据,即使是设置了private,也可以通过访问 slot(数据槽) 来具体得到数据信息
// 理解 EVM 中数据存放在slot的原理和存放规则

// 具体看: https://www.bilibili.com/video/BV1vh4y1p7yp/?vd_source=d0b40de9808bcfb380e48c5feea3012f
